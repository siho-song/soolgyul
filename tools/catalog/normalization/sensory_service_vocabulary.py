"""ADR-113/119 service vocabulary: explicit source projection, never inferred children.

The detailed catalog remains the collection/recognition dictionary. This module
is the only projection from those keys to the user's service representatives.
It neither collects information nor connects to a database.
"""

from __future__ import annotations

from functools import cache
import json
from pathlib import Path
import re
from typing import Any, Iterable, Mapping

ROOT = Path(__file__).resolve().parents[3]
from tools.catalog.dictionary import project as dictionary
LEGACY_PATH = ROOT / "catalog/sensory/archive/db-terms-before-service-v1.json"
TAG_FIELDS = ("aroma_tags", "palate_tags", "finish_tags", "flavor_tags")
SECTIONS = ("descriptors", "textures", "finish_characters")


class ServiceVocabulary:
    def __init__(self, spec: Mapping[str, Any], source: Mapping[str, Any]) -> None:
        self.spec = spec
        self.source = {row["key"]: row for section in SECTIONS for row in source[section]}
        self.groups: dict[str, Mapping[str, Any]] = {}
        self.targets: dict[str, str | None] = {}
        self.pending = {row["key"] for row in spec["pending"]}
        self.hidden: set[str] = set()
        categories = {row["key"] for row in spec["categories"]}

        def assign(key: str, target: str | None) -> None:
            if key in self.targets:
                raise ValueError(f"duplicate service assignment: {key}")
            self.targets[key] = target

        for group in spec["groups"]:
            key = group["key"]
            if not re.fullmatch(r"[a-z][a-z0-9_]*", key) or key in self.groups:
                raise ValueError(f"invalid service key: {key}")
            if not group["label_ko"].strip() or group["category_key"] not in categories:
                raise ValueError(f"invalid service label/category: {key}")
            if group["domain"] not in {"descriptor", "texture"} or not group["source_keys"]:
                raise ValueError(f"invalid service domain/members: {key}")
            self.groups[key] = group
            phases: set[str] = set()
            for member in group["source_keys"]:
                if member not in self.source:
                    raise ValueError(f"unknown source member: {member}")
                phases.update(self.source[member].get("phases", ["finish"]))
                assign(member, key)
            if phases != set(group["phases"]):
                raise ValueError(f"service group phase union mismatch: {key}")
        for hidden in spec["hidden"]:
            for key in hidden["source_keys"]:
                if key not in self.source:
                    raise ValueError(f"unknown hidden source: {key}")
                # "Hidden" is a display decision, not deletion of the last
                # fact in a source-only profile. Keep internal assignments valid.
                assign(key, key)
                self.hidden.add(key)
        for key in self.pending:
            assign(key, key)
        for key, source_key in spec["legacy_aliases"].items():
            if source_key not in self.targets:
                raise ValueError(f"unknown legacy target: {source_key}")
            assign(key, self.targets[source_key])
        if set(self.source) - self.targets.keys():
            raise ValueError(f"unmapped source terms: {sorted(set(self.source) - self.targets.keys())}")
        for key in self.groups:
            if key in self.targets and self.targets[key] != key:
                raise ValueError(f"representative is remapped again: {key}")
            self.targets[key] = key

    def normalize(self, keys: Iterable[str], *, visible_only: bool = False) -> list[str]:
        result: dict[str, None] = {}
        for key in keys:
            if key not in self.targets:
                raise ValueError(f"unreviewed sensory key: {key}")
            target = self.targets[key]
            if target is not None and (not visible_only or target in self.groups):
                result[target] = None
        return list(result)

    def normalize_profile(self, profile: Mapping[str, Any]) -> dict[str, Any]:
        result = dict(profile)
        for field in TAG_FIELDS:
            if field in profile:
                result[field] = self.normalize(profile[field])
        section_keys = {key for field in TAG_FIELDS[:-1] for key in result.get(field, [])}
        # Legacy archive inputs may still carry the retired aggregate. Current
        # operational profiles contain only section-specific tags.
        if "flavor_tags" in result and not section_keys <= set(result["flavor_tags"]):
            raise ValueError("flavor_tags must contain all section tags; do not guess a missing assignment")
        return result

    def questionnaire_choices(self, keys: Iterable[str], *, phase: str) -> list[dict[str, Any]]:
        if phase not in {"aroma", "palate", "finish", "texture"}:
            raise ValueError(f"invalid sensory phase: {phase}")
        choices: dict[str, dict[str, Any]] = {}
        for key in keys:
            targets = self.normalize([key], visible_only=True)
            if not targets:
                continue
            target = targets[0]
            group = self.groups[target]
            # Source-only keys retain their individual phase restriction. Once
            # collapsed, the representative has only its explicit phase union.
            phases = (self.source[key].get("phases", ["finish"])
                      if key in self.source and key not in self.groups else group["phases"])
            if phase not in phases:
                continue
            choice = choices.setdefault(target, {
                "key": target, "label_ko": group["label_ko"], "phase": phase,
                "catalog_descriptor_keys": [], "is_representative": True,
            })
            if key not in choice["catalog_descriptor_keys"]:
                choice["catalog_descriptor_keys"].append(key)
        return list(choices.values())

    def term_rows(self, legacy_rows: Iterable[Mapping[str, Any]] = ()) -> list[dict[str, Any]]:
        legacy = {row["term_key"]: row for row in legacy_rows}
        categories = {row["key"]: row["label_ko"] for row in self.spec["categories"]}
        rows = []
        for position, group in enumerate(self.groups.values(), start=1):
            labels = {self.source[key]["label_ko"] for key in group["source_keys"]}
            labels.update(group["user_source_labels"])
            labels.discard(group["label_ko"])
            if len(labels) > 64:
                raise ValueError(f"service synonyms exceed DB limit: {group['key']}")
            rows.append({
                "term_type": "sensory_descriptor", "term_key": group["key"],
                "label_ko": group["label_ko"], "label_en": None,
                "synonyms": sorted(labels), "parent_term_key": None,
                "applicable_sections": sorted(group["phases"]),
                "metadata": {"onboarding_selectable": True, "user_visible": True,
                    "sensory_service": {"version": self.spec["schema_version"], "status": "representative",
                        "category_key": group["category_key"], "category_label_ko": categories[group["category_key"]],
                        "domain": group["domain"], "source_keys": group["source_keys"],
                        "is_representative": True}},
                "taxonomy_version": self.spec["taxonomy_version"],
                "sort_order": position * 10, "is_active": True,
            })
        # Unspecified keys stay assignable to preserve existing data, but never
        # become visible representatives or silently split into multiple guesses.
        for key in sorted(self.pending | self.hidden):
            source = self.source.get(key)
            if source:
                label, sections = source["label_ko"], source.get("phases", ["finish"])
            elif key in legacy:
                label, sections = legacy[key]["label_ko"], legacy[key]["applicable_sections"]
            else:
                raise ValueError(f"missing preserved legacy term: {key}")
            rows.append({
                "term_type": "sensory_descriptor", "term_key": key, "label_ko": label,
                "label_en": None, "synonyms": [], "parent_term_key": None,
                "applicable_sections": sorted(sections),
                "metadata": {"onboarding_selectable": False, "user_visible": False,
                    "sensory_service": {"version": self.spec["schema_version"], "status": "hidden" if key in self.hidden else "pending"}},
                "taxonomy_version": self.spec["taxonomy_version"],
                "sort_order": (len(rows) + 1) * 10, "is_active": True,
            })
        return rows


def fold_targets(tree: Mapping[str, Any]) -> dict[str, str | None]:
    """The offered word each word for what is sensed folds into: its own
    `shown_as` where it states one, else the nearest offered word at or above it."""
    words = list(dictionary.senses(tree))
    shown = {w["key"] for w, *_ in words if "choice" in w}
    above = {w["key"]: parent for w, _, _, parent in words}
    out: dict[str, str | None] = {}
    for w, *_ in words:
        if "shown_as" in w:
            out[w["key"]] = w["shown_as"]
            continue
        key: str | None = w["key"]
        while key is not None and key not in shown:
            key = above[key]
        out[w["key"]] = key
    return out


def vocabulary_views(tree: Mapping[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    """What the app offers (groups, hidden, pending) and every source word,
    read off the senses tree."""
    words = list(dictionary.senses(tree))
    targets = fold_targets(tree)
    shown = {w["key"]: w for w, *_ in words if "choice" in w}
    source: dict[str, list] = {"descriptors": [], "textures": [], "finish_characters": []}
    section = {"aroma": "descriptors", "texture": "textures", "finish_character": "finish_characters"}
    for w, type_, family, parent in words:
        if w.get("meaning_only"):
            continue
        entry: dict[str, Any] = {"key": w["key"], "label_ko": w["ko"]}
        if "en" in w:
            entry["label_en"] = w["en"]
        if type_ != "finish_character":
            entry["aliases"] = w.get("aliases", [])
            entry["parent_key"] = parent
        if "said_of" in w:
            entry["phases"] = w["said_of"]
        if family:
            entry["family_key"] = family
        source[section[type_]].append(entry)
    sources = {e["key"] for rows in source.values() for e in rows}
    domain = {"aroma": "descriptor", "texture": "texture", "finish_character": "finish_character"}
    type_of = {w["key"]: type_ for w, type_, *_ in words}
    groups = []
    for key, w in sorted(shown.items(), key=lambda kv: kv[1]["choice"]["order"]):
        c = w["choice"]
        groups.append({
            "key": key, "label_ko": c["label"], "category_key": c["group"], "domain": domain[type_of[key]],
            "source_keys": [k for k, t in targets.items() if t == key and k in sources],
            "user_source_labels": c.get("found_by", []),
            "phases": c.get("said_of", w.get("said_of", [])),
        })
    pending = [{"key": f["key"], "label_ko": f["pending"]["label"], "reason": f["pending"]["reason"]}
               for f in tree["senses"]["families"] if "pending" in f]
    pending += [{"key": w["key"], "label_ko": w["pending"]["label"], "reason": w["pending"]["reason"]}
                for w, *_ in words if "pending" in w]
    held_back = {p["key"] for p in pending}
    hidden = [w["key"] for w, *_ in words
              if w["key"] not in shown and w["key"] not in held_back and targets[w["key"]] not in shown]
    choice = tree["senses"]["choice"]
    spec = {
        "schema_version": choice["version"], "taxonomy_version": choice["taxonomy_version"],
        "categories": [{"key": g["key"], "label_ko": g["ko"]} for g in choice["groups"]],
        "groups": groups,
        "hidden": [{"reason": "not offered", "source_keys": hidden}] if hidden else [],
        "pending": pending,
        "legacy_aliases": {old: w["key"] for w, *_ in words for old in w.get("old_keys", [])},
    }
    return spec, source


@cache
def load_service_vocabulary() -> ServiceVocabulary:
    return ServiceVocabulary(*vocabulary_views(dictionary.load()))


def project_service_terms(source: Mapping[str, Any] | None = None) -> list[dict[str, Any]]:
    """Descriptor keys, labels and visibility only; descriptions stay in the dictionary file."""
    spec, own_source = vocabulary_views(dictionary.load())
    vocabulary = ServiceVocabulary(spec, own_source if source is None else source)
    return vocabulary.term_rows(json.loads(LEGACY_PATH.read_text(encoding="utf-8")))
