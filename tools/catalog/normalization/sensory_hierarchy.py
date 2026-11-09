"""Traverse the canonical vocabulary without inventing sensory observations.

Grouping classifies supplied descriptors only. It does not expand broad evidence
into children, grant UI visibility, or turn recognition into a preference score.
"""

from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Any, Iterable, Literal, Mapping
import unicodedata


DescriptorPhase = Literal["aroma", "palate", "finish", "texture"]
ChoicePhase = Literal["aroma", "palate", "finish", "texture"]


class SensoryHierarchyError(ValueError):
    """The descriptor hierarchy or a requested key is invalid."""


@dataclass(frozen=True)
class SensoryFamily:
    key: str
    label_ko: str
    domain: str
    kind: str


def _families(rows: Iterable[Mapping[str, Any]]) -> dict[str, SensoryFamily]:
    result = {}
    for row in rows:
        key, label = row.get("key"), row.get("label_ko")
        if not isinstance(key, str) or not key.strip() or key in result:
            raise SensoryHierarchyError(f"invalid or duplicate family key: {key}")
        if not isinstance(label, str) or not label.strip():
            raise SensoryHierarchyError(f"invalid family label: {key}")
        domain, kind = row.get("domain"), row.get("kind")
        if domain not in {"descriptor", "texture", "finish_character"}:
            raise SensoryHierarchyError(f"invalid family domain: {key}")
        if kind not in {"sensory", "character", "unresolved"}:
            raise SensoryHierarchyError(f"invalid family kind: {key}")
        if domain != "descriptor" and kind != "sensory":
            raise SensoryHierarchyError(f"non-descriptor family must be sensory: {key}")
        result[key] = SensoryFamily(key, label, domain, kind)
    return result


@dataclass(frozen=True)
class DescriptorGroup:
    family_key: str
    group_key: str | None
    group_label_ko: str | None
    phase: DescriptorPhase
    descriptor_keys: tuple[str, ...]
    family_label_ko: str | None = None
    kind: str = "sensory"


@dataclass(frozen=True)
class DescriptorChoice:
    """A display/answer key plus provenance, never an inferred raw observation.

    A representative key names a reviewed display group, not necessarily the
    exact descriptor bearing that key in the source vocabulary.
    """

    key: str
    label_ko: str
    phase: ChoicePhase
    catalog_descriptor_keys: tuple[str, ...]
    is_representative: bool = False


class SensoryHierarchy:
    """A validated snapshot of descriptor paths and optional named groups."""

    def __init__(
        self, descriptors: Iterable[Mapping[str, Any]], *,
        families: Iterable[Mapping[str, Any]] | None = None,
    ) -> None:
        rows = list(descriptors)
        self._families = _families(families) if families is not None else {}
        self._parents: dict[str, str | None] = {}
        self._groups: dict[str, str] = {}
        self._phases: dict[str, frozenset[str]] = {}
        self._paths: dict[str, tuple[str, ...]] = {}
        self._root_families: dict[str, SensoryFamily] = {}
        self._facets: dict[str, tuple[str, ...]] = {}
        self._facet_terms: set[str] = set()
        self._labels: dict[str, str] = {}
        self._selectable: dict[str, bool] = {}
        self._service_vocabulary = None
        for row in rows:
            key = row.get("key")
            if not isinstance(key, str) or not key.strip():
                raise SensoryHierarchyError("descriptor key must be non-empty")
            if key in self._parents:
                raise SensoryHierarchyError(f"duplicate descriptor key: {key}")
            self._labels[key] = row.get("label_ko", key)
            self._selectable[key] = row.get("onboarding_selectable") is True
            parent = row.get("parent_key")
            if parent is not None and not isinstance(parent, str):
                raise SensoryHierarchyError(f"invalid descriptor parent: {key}")
            self._parents[key] = parent
            phases = row.get("phases", [])
            if not isinstance(phases, list) or any(
                phase not in {"aroma", "palate", "finish"}
                and not (phase == "texture" and key in {"clean_character", "immediate_onset", "tannin", "first_impression", "slim_texture", "glossy_texture", "effervescent_texture", "fine_grained_character", "restrained_character", "gentle_spread_character", "intensity_character", "wide_spread_character", "crisp_character", "gradual_emergence", "toward_finish_emergence", "integrated_character", "angular_character", "persistent_character"}
                         and row.get("onboarding_selectable") is False)
                for phase in phases
            ) or (families is not None and not phases):
                raise SensoryHierarchyError(f"invalid descriptor phases: {key}")
            self._phases[key] = frozenset(phases)
            family_key = row.get("family_key")
            if parent is not None and family_key is not None:
                raise SensoryHierarchyError(f"child must inherit its family: {key}")
            if parent is None and (families is not None or family_key is not None):
                family = self._families.get(family_key)
                if family is None or family.domain != "descriptor":
                    raise SensoryHierarchyError(f"missing descriptor family: {key}")
                if family.kind == "unresolved" and not row.get("classification_note"):
                    raise SensoryHierarchyError(f"unresolved descriptor needs a note: {key}")
                self._root_families[key] = family
            if "group_label_ko" in row:
                label = row["group_label_ko"]
                if not isinstance(label, str) or not label.strip():
                    raise SensoryHierarchyError(f"invalid group label: {key}")
                if parent is None and key not in self._root_families:
                    raise SensoryHierarchyError(f"intermediate group needs a parent: {key}")
                self._groups[key] = label
            facets = row.get("facet_keys", [])
            if not isinstance(facets, list) or any(not isinstance(f, str) for f in facets):
                raise SensoryHierarchyError(f"invalid descriptor facets: {key}")
            self._facets[key] = tuple(dict.fromkeys(facets))
            if row.get("is_facet") is True:
                if facets:
                    raise SensoryHierarchyError(f"facet cannot point to other facets: {key}")
                self._facet_terms.add(key)

        for key, parent in self._parents.items():
            if parent is not None and parent not in self._parents:
                raise SensoryHierarchyError(f"missing descriptor parent: {key} -> {parent}")
        for key in self._parents:
            path: list[str] = []
            visited: set[str] = set()
            current: str | None = key
            while current is not None:
                if current in visited:
                    raise SensoryHierarchyError(
                        "descriptor parent cycle: " + " -> ".join([*path, current])
                    )
                visited.add(current)
                path.append(current)
                current = self._parents[current]
            self._paths[key] = tuple(reversed(path))
        for key, facets in self._facets.items():
            for facet in facets:
                if facet not in self._facet_terms or facet == key:
                    raise SensoryHierarchyError(f"invalid facet target: {key} -> {facet}")
                if self.family_for(key).key != self.family_for(facet).key:
                    raise SensoryHierarchyError(f"facet crosses families: {key} -> {facet}")
        for key, selectable in self._selectable.items():
            # A reader-offered name must be a sensory descriptor; membership
            # itself is derived from parent links by sync_service_vocabulary.
            if selectable and self.family_for(key).kind != "sensory":
                raise SensoryHierarchyError(f"selectable descriptor must be sensory: {key}")

    @classmethod
    def from_catalog(cls, catalog: Mapping[str, Any]) -> SensoryHierarchy:
        hierarchy = cls(catalog["descriptors"], families=catalog["families"])
        if catalog.get("service_vocabulary") == "catalog/sensory/service-vocabulary.json":
            from tools.catalog.dictionary import project as dictionary
            from tools.catalog.normalization.sensory_service_vocabulary import ServiceVocabulary

            hierarchy._service_vocabulary = ServiceVocabulary(
                dictionary.view("service_vocabulary"), catalog)
        return hierarchy

    def path_to(self, key: str) -> tuple[str, ...]:
        """Return a root-to-self path; ancestors are not extra observations."""
        try:
            return self._paths[key]
        except KeyError as exc:
            raise SensoryHierarchyError(f"unknown descriptor key: {key}") from exc

    def family_for(self, key: str) -> SensoryFamily:
        root = self.path_to(key)[0]
        return self._root_families.get(root, SensoryFamily(root, root, "descriptor", "sensory"))

    def facet_keys_for(self, key: str) -> tuple[str, ...]:
        """Return classification facets, never additional recorded descriptors."""
        result: list[str] = []
        for ancestor in self.path_to(key):
            if ancestor in self._facet_terms:
                result.append(ancestor)
            result.extend(self._facets[ancestor])
        return tuple(dict.fromkeys(result))

    def questionnaire_choices(
        self, keys: Iterable[str], *, phase: ChoicePhase,
    ) -> tuple[DescriptorChoice, ...]:
        """Offer the reader names that already eligible catalog evidence maps to.

        The caller still owns source, release and publication gates. With the
        service vocabulary present, a key is offered as the nearest selectable
        name on its own line (derived from parent links). Catalog provenance
        must never be expanded into individual observations the user did not
        select.
        """
        if self._service_vocabulary is not None:
            try:
                return tuple(DescriptorChoice(
                    key=row["key"], label_ko=row["label_ko"], phase=phase,
                    catalog_descriptor_keys=tuple(row["catalog_descriptor_keys"]),
                    is_representative=True,
                ) for row in self._service_vocabulary.questionnaire_choices(keys, phase=phase))
            except ValueError as exc:
                raise SensoryHierarchyError(str(exc)) from exc
        if phase not in {"aroma", "palate", "finish"}:
            raise SensoryHierarchyError(f"unsupported descriptor phase: {phase}")
        choices: dict[str, list[str]] = {}
        for key in keys:
            family = self.family_for(key)  # Reject unknown keys, even if hidden.
            if family.kind != "sensory" or phase not in self._phases[key]:
                continue
            target = next((a for a in reversed(self.path_to(key)) if self._selectable[a]), None)
            if target is None or phase not in self._phases[target]:
                continue
            sources = choices.setdefault(target, [])
            if key not in sources:
                sources.append(key)
        return tuple(
            DescriptorChoice(key, self._labels[key], phase, tuple(sources),
                             is_representative=False)
            for key, sources in choices.items()
        )

    def group_descriptors(
        self, keys: Iterable[str], *, phase: DescriptorPhase,
        include_non_sensory: bool = False,
    ) -> tuple[DescriptorGroup, ...]:
        """Group given keys by root and nearest named group, including self.

        The supplied descriptor's own phases govern eligibility, not its parent's.
        Group and member order follow first appearance. Duplicate keys are removed;
        no descendants, reactions or visibility permissions are synthesized.
        """
        if phase not in {"aroma", "palate", "finish"}:
            raise SensoryHierarchyError(f"unsupported descriptor phase: {phase}")
        grouped: dict[tuple[str, str | None], list[str]] = {}
        seen: set[str] = set()
        for key in keys:
            path = self.path_to(key)
            if key in seen or phase not in self._phases[key]:
                continue
            family = self.family_for(key)
            if family.kind != "sensory" and not include_non_sensory:
                continue
            seen.add(key)
            group_key = next(
                (ancestor for ancestor in reversed(path) if ancestor in self._groups),
                None,
            )
            grouped.setdefault((family.key, group_key), []).append(key)
        return tuple(
            DescriptorGroup(
                family_key=family,
                group_key=group,
                group_label_ko=self._groups.get(group) if group is not None else None,
                phase=phase,
                descriptor_keys=tuple(members),
                family_label_ko=self._families[family].label_ko if family in self._families else None,
                kind=self._families[family].kind if family in self._families else "sensory",
            )
            for (family, group), members in grouped.items()
        )


def validate_sensory_catalog(catalog: Mapping[str, Any]) -> SensoryHierarchy:
    """Check every term's family, phase, facets and lexical identity in one place."""
    hierarchy = SensoryHierarchy.from_catalog(catalog)
    families = _families(catalog["families"])
    used = {hierarchy.family_for(row["key"]).key for row in catalog["descriptors"]}
    for section, domain in (("textures", "texture"), ("finish_characters", "finish_character")):
        rows = catalog[section]
        keys = {row["key"] for row in rows}
        if len(keys) != len(rows):
            raise SensoryHierarchyError(f"duplicate {domain} key")
        for row in rows:
            family = families.get(row.get("family_key"))
            if family is None or family.domain != domain:
                raise SensoryHierarchyError(f"missing {domain} family: {row['key']}")
            # These domains are deliberately flat; don't invent descriptor parents.
            if row.get("parent_key") is not None:
                raise SensoryHierarchyError(f"unexpected {domain} parent: {row['key']}")
            phases = row.get("phases", ["finish"])
            allowed = {"palate", "texture", "finish"} if domain == "texture" else {"finish"}
            if not isinstance(phases, list) or not phases or not set(phases) <= allowed:
                raise SensoryHierarchyError(f"invalid {domain} phases: {row['key']}")
            used.add(family.key)
    if used != set(families):
        raise SensoryHierarchyError(f"unused sensory families: {sorted(set(families) - used)}")
    for section in ("descriptors", "textures", "finish_characters"):
        aliases: dict[tuple[str, str], str] = {}
        for row in catalog[section]:
            phases = row.get("phases", ["finish"])
            words = [row["key"], row["label_ko"], *row.get("aliases", [])]
            if section == "descriptors":
                words.append(row["label_en"])
            for values in row.get("source_aliases", {}).values():
                words.extend(values)
            for word in words:
                normalized = re.sub(r"\s+", " ", unicodedata.normalize("NFKC", word)).strip().casefold()
                for phase in phases:
                    identity = (phase, normalized)
                    previous = aliases.setdefault(identity, row["key"])
                    if previous != row["key"]:
                        raise SensoryHierarchyError(
                            f"ambiguous {section} alias: {word}: {previous}, {row['key']}"
                        )
    return hierarchy
