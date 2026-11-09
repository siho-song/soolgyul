"""Typed, fail-closed catalog assignments. No inference, persistence or network.

The enrichment taxonomy owns the rules. This module compiles its serving subset
and validates actual assignments (which validating the dictionary does not do).
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from functools import lru_cache
import re
from types import MappingProxyType
from typing import Any, Mapping

from tools.catalog.enrichment.generate_assignment_contract import compile_contract
from tools.catalog.enrichment.assignment_keys_generated import (
    CatalogCategoryKey, CatalogStyleKey, CatalogIngredientKey, CatalogProcessKey,
)


class AssignmentTarget(str, Enum):
    PRODUCT = "product"
    RELEASE = "release"


class TermKind(str, Enum):
    STYLE = "style"
    INGREDIENT = "ingredient"
    PROCESS = "process"
    MATURATION = "maturation"


FIELDS = ("ingredient_keys", "production_process_keys")
KINDS = {"ingredient_keys": {"ingredient"}, "production_process_keys": {"process", "maturation"}}


@dataclass(frozen=True, slots=True)
class AssignmentIssue:
    code: str
    field: str
    key: str = ""

    def as_dict(self) -> dict[str, str]:
        return {"code": self.code, "field": self.field, "key": self.key}


class InvalidCatalogAssignment(ValueError):
    def __init__(self, issues: tuple[AssignmentIssue, ...]):
        self.issues = issues
        super().__init__("; ".join(f"{i.code}:{i.field}:{i.key}" for i in issues))


_VALIDATION_TOKEN = object()


@dataclass(frozen=True, slots=True, init=False)
class ValidatedCatalogAssignment:
    category_key: CatalogCategoryKey
    style_key: CatalogStyleKey | None
    target: AssignmentTarget
    ingredient_keys: tuple[CatalogIngredientKey, ...]
    production_process_keys: tuple[CatalogProcessKey, ...]

    def __init__(self, token: object, values: Mapping[str, Any]):
        if token is not _VALIDATION_TOKEN:
            raise TypeError("Use AssignmentRegistry.validate().require_valid()")
        values = {**values,
                  'category_key': CatalogCategoryKey(values['category_key']),
                  'style_key': None if values['style_key'] is None else CatalogStyleKey(values['style_key']),
                  'ingredient_keys': tuple(CatalogIngredientKey(k) for k in values['ingredient_keys']),
                  'production_process_keys': tuple(CatalogProcessKey(k) for k in values['production_process_keys'])}
        for name, value in values.items():
            object.__setattr__(self, name, value)

    def to_wire(self) -> dict[str, Any]:
        return {"category_key": self.category_key.value, "style_key": self.style_key.value if self.style_key else None,
                "target": self.target.value,
                **{field: [key.value for key in getattr(self, field)] for field in FIELDS}}


@dataclass(frozen=True, slots=True)
class AssignmentValidation:
    value: ValidatedCatalogAssignment | None
    issues: tuple[AssignmentIssue, ...]

    def require_valid(self) -> ValidatedCatalogAssignment:
        if self.value is None:
            raise InvalidCatalogAssignment(self.issues)
        return self.value




class AssignmentRegistry:
    def __init__(self, contract: Mapping[str, Any]):
        if contract.get("schema_version") != 2:
            raise ValueError("Unsupported assignment contract")
        self.categories = frozenset(contract["categories"])
        for category in self.categories:
            CatalogCategoryKey(category)
        terms: dict[tuple[str, str], Mapping[str, Any]] = {}
        for raw in contract["terms"]:
            term = dict(raw)
            kind = TermKind(term["kind"]).value
            {'style': CatalogStyleKey, 'ingredient': CatalogIngredientKey, 'process': CatalogProcessKey,
             'maturation': CatalogProcessKey}[kind](term['key'])
            if term["target"] not in {"product", "release", "both"}:
                raise ValueError("Invalid rule target")
            if not term["categories"] or not set(term["categories"]) <= self.categories:
                raise ValueError("Invalid rule categories")
            for key in ("categories", "styles", "excludes"):
                term[key] = tuple(term[key])
            identity = (kind, term["key"])
            if identity in terms:
                raise ValueError("Duplicate registry identity")
            terms[identity] = MappingProxyType(term)
        self.terms = MappingProxyType(terms)

    def validate(self, raw: Mapping[str, Any]) -> AssignmentValidation:
        issues: list[AssignmentIssue] = []
        def issue(code: str, field: str, key: str = "") -> None:
            issues.append(AssignmentIssue(code, field, key))
        category, style = raw.get("category_key"), raw.get("style_key")
        try:
            target = AssignmentTarget(raw.get("target", "product"))
        except (ValueError, TypeError):
            target = AssignmentTarget.PRODUCT
            issue("invalid_target", "target")
        if not isinstance(category, str) or category not in self.categories:
            issue("unknown_category", "category_key")
        selected: dict[str, list[Mapping[str, Any]]] = {}
        arrays: dict[str, tuple[str, ...]] = {}
        def check(term: Mapping[str, Any], field: str) -> None:
            key = term["key"]
            if category not in term["categories"]:
                issue("wrong_category", field, key)
            if term["styles"] and style not in term["styles"]:
                issue("wrong_style", field, key)
            if term["target"] not in (target.value, "both"):
                issue("wrong_target", field, key)
        if style is not None:
            term = self.terms.get(("style", style)) if isinstance(style, str) else None
            if term is None:
                issue("unknown_term", "style_key", style if isinstance(style, str) else "")
            else:
                check(term, "style_key")
        for field in FIELDS:
            values = raw.get(field, [])
            selected[field] = []
            if not isinstance(values, (list, tuple)):
                issue("invalid_array", field)
                arrays[field] = ()
                continue
            if len(values) > 64:
                issue("too_many_terms", field)
            seen: set[str] = set()
            for key in values:
                if not isinstance(key, str) or re.fullmatch(r"[a-z][a-z0-9_]*", key) is None:
                    issue("invalid_key", field)
                    continue
                if key in seen:
                    issue("duplicate_term", field, key)
                seen.add(key)
                matches = [self.terms[kind, key] for kind in KINDS[field] if (kind, key) in self.terms]
                if len(matches) != 1:
                    issue("unknown_term" if not matches else "ambiguous_term", field, key)
                    continue
                check(matches[0], field)
                selected[field].append(matches[0])
            arrays[field] = tuple(sorted(seen))
            for term in selected[field]:
                if any(other in seen for other in term["excludes"]):
                    issue("excluded_combination", field, term["key"])
        ordered = tuple(sorted(set(issues), key=lambda i: (i.code, i.field, i.key)))
        value = None if ordered else ValidatedCatalogAssignment(_VALIDATION_TOKEN, {
            "category_key": category, "style_key": style, "target": target, **arrays})
        return AssignmentValidation(value, ordered)


@lru_cache(maxsize=1)
def assignment_registry() -> AssignmentRegistry:
    return AssignmentRegistry(compile_contract())
