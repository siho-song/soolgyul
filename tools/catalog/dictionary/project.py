"""Views of the one dictionary in the shapes the tools and the card code read.

Each function returns what one of the former knowledge files held (style
table, aroma tree, term knowledge, service vocabulary, ABV bands, producer
profiles, enrichment taxonomy). `view(name)` reads the checked-in dictionary once per process and
hands out copies; `rebuild` + `save` persist an edited view.
"""

from __future__ import annotations

import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DICTIONARY = ROOT / "catalog/dictionary/terms.json"

TRAIT_FIELDS = (("level", "level"), ("basis", "basis"), ("reason", "reason_ko"),
                ("evidence", "evidence_ko"), ("detail", "detail_ko"), ("grade", "grade"), ("sources", "sources"))
AROMA_FIELDS = (("key", "key"), ("basis", "basis"), ("reason", "reason_ko"),
                ("source_kind", "source_kind"), ("source", "source_ko"), ("feel", "feel"), ("grade", "grade"),
                ("sources", "sources"))


_cache: dict | None = None


def load() -> dict:
    return json.loads(DICTIONARY.read_text(encoding="utf-8"))


def view(name: str) -> dict:
    """One old shape out of the checked-in dictionary (read once per process)."""
    global _cache
    if _cache is None:
        _cache = load()
    # A fresh copy every time: tools edit what they get.
    return copy.deepcopy(VIEWS[name](_cache))


def views(d: dict) -> dict:
    return {name: fn(d) for name, fn in VIEWS.items()}


def save(d: dict) -> None:
    """Write the dictionary and forget the cached copy."""
    global _cache
    from tools.catalog.dictionary.build import render
    DICTIONARY.write_text(render(d), encoding="utf-8")
    _cache = None


def rebuild(edited_views: dict) -> dict:
    """The dictionary rebuilt from edited views, for tools that still think in
    the old shapes; unchanged views are taken from the current dictionary.

    Only what the views carry is rebuilt. Rows the views do not know (regions)
    and slots they do not carry (collected hints, label words, counted facts)
    are kept from the current dictionary.
    """
    from tools.catalog.dictionary.build import build_from
    current = load()
    sources = views(current)
    sources.update(edited_views)
    rebuilt = build_from(sources)[0]
    return carry_over(current, rebuilt)


def merge_row(old: dict, new: dict) -> dict:
    """The rebuilt row wins on what it carries; everything else stays."""
    out = dict(old)
    for slot, value in new.items():
        if isinstance(value, dict) and isinstance(old.get(slot), dict):
            out[slot] = {**old[slot], **value}
        else:
            out[slot] = value
    return out


def carry_over(current: dict, rebuilt: dict) -> dict:
    by_key = {(t["type"], t["key"]): t for t in rebuilt["terms"]}
    terms = []
    seen = set()
    for old in current["terms"]:
        key = (old["type"], old["key"])
        new = by_key.get(key)
        terms.append(merge_row(old, new) if new else old)
        seen.add(key)
    terms += [t for t in rebuilt["terms"] if (t["type"], t["key"]) not in seen]
    out = {**current, **{k: v for k, v in rebuilt.items() if k != "terms"}}
    out["terms"] = terms
    return out


def rows(d: dict, *types: str) -> list[dict]:
    return [t for t in d["terms"] if t["type"] in types]


def back(obj: dict, fields) -> dict:
    return {old: obj[new] for new, old in fields if new in obj}


def traits(t: dict) -> dict:
    return {axis: back(v, TRAIT_FIELDS) for axis, v in t.get("taste", {}).items()}


def aromas(t: dict) -> list:
    return [back(a, AROMA_FIELDS) for a in t.get("aromas", [])]


def extra(t: dict, *drop: str) -> dict:
    return {k: v for k, v in t.get("extra", {}).items() if k not in drop}


def style_profiles(d: dict) -> dict:
    styles = []
    for t in rows(d, "kind"):
        if "summary" not in t:
            continue
        styles.append({
            "key": t["key"], "name_ko": t["names"]["ko"], "intro_ko": t["summary"],
            "traits": traits(t), "aromas": aromas(t), "varies_ko": t["varies"],
            **extra(t, "taxonomy"),
        })
    grapes = []
    for t in rows(d, "grape"):
        grapes.append({
            "key": t["key"], "name_ko": t["names"]["ko"], "intro_ko": t["summary"],
            "colors": t["hints"]["colors"], "match": {"patterns": t["names"]["label_patterns"]},
            "traits": traits(t), "aromas": aromas(t), "varies_ko": t["varies"], **extra(t),
        })
    regions = []
    for t in rows(d, "regional_style"):
        match = {
            "region_labels": t["hints"].get("region_labels", []),
            "name_patterns": t["names"].get("label_patterns", []),
        }
        if "style_keys" in t["hints"]:
            match["style_keys"] = t["hints"]["style_keys"]
        regions.append({
            "key": t["key"], "name_ko": t["names"]["ko"], "color": t["hints"]["color"],
            "intro_ko": t["summary"], "match": match,
            "traits": traits(t), "aromas": aromas(t), "varies_ko": t["varies"], **extra(t),
        })
    processes = []
    # Only the rows the old style table carried; collected process knowledge
    # reaches the card through the dictionary itself, not this view.
    for t in sorted(
        (t for t in rows(d, "process", "maturation") if "style_table_order" in t.get("extra", {})),
        key=lambda t: t["extra"]["style_table_order"],
    ):
        entry = {"key": t["key"], "name_ko": t["names"]["ko"], "intro_ko": t["summary"]}
        if t.get("taste"):
            entry["traits"] = traits(t)
        entry["aromas"] = aromas(t)
        if t.get("hints", {}).get("fact_label"):
            entry["fact_ko"] = t["hints"]["fact_label"]
        processes.append(entry)
    return {
        "schemaVersion": d["versions"]["style_profiles"],
        "dimensions": d["style_axes"],
        "styles": styles, "wine_grapes": grapes, "wine_regions": regions, "processes": processes,
    }


def sensory_entry(t: dict, with_aliases: bool = True) -> dict:
    entry = {"key": t["key"], "label_ko": t["names"]["ko"]}
    if "en" in t["names"]:
        entry["label_en"] = t["names"]["en"]
    if with_aliases:
        entry["aliases"] = t["names"].get("aliases", [])
    entry["parent_key"] = t.get("parent")
    app = t.get("app", {})
    if "selectable" in app:
        entry["onboarding_selectable"] = app["selectable"]
    if "phases" in app:
        entry["phases"] = app["phases"]
    entry["source_aliases"] = {}
    entry.update(extra(t, "legacy_keys", "knowledge_only", "taxonomy"))
    return entry


def sensory_catalog(d: dict) -> dict:
    def entries(type_: str, with_aliases: bool = True) -> list[dict]:
        return [sensory_entry(t, with_aliases) for t in rows(d, type_) if not t.get("extra", {}).get("knowledge_only")]

    descriptors = entries("aroma")
    textures = entries("texture")
    finish = []
    for e in entries("finish_character", with_aliases=False):
        e.pop("parent_key", None)
        finish.append(e)
    families = [
        {"key": t["key"], "label_ko": t["names"]["ko"], **extra(t, "legacy_keys", "taxonomy")}
        for t in rows(d, "aroma_family")
    ]
    return {
        "service_vocabulary": "catalog/sensory/service-vocabulary.json",
        "families": families, "descriptors": descriptors,
        "expression_rules": d["expression_rules"],
        "finish_characters": finish, "textures": textures,
    }


def source_ids(t: dict) -> list[str]:
    """The reference ids among a row's sources (collected evidence has none)."""
    return [s["id"] for s in t.get("sources", []) if isinstance(s, dict) and "id" in s]


def term_knowledge(d: dict) -> dict:
    terms = {}
    for t in rows(d, "aroma_family", "aroma", "texture", "finish_character"):
        db = t.get("app", {}).get("db")
        if not db:
            continue
        terms[t["key"]] = {
            "catalog": db,
            "sensory_description": t["summary"],
            "sensory_trait_keys": t.get("traits", []),
            "source_ids": source_ids(t),
        }
    dimensions = {}
    for t in rows(d, "axis"):
        if "summary" not in t:
            continue
        dimensions[t["key"]] = {
            "sensory_description": t["summary"],
            "sensory_trait_keys": t.get("traits", []),
            "source_ids": source_ids(t),
        }
    return {
        "version": d["versions"]["term_knowledge"],
        "trait_policy": d["trait_policy"],
        "traits": {t["key"]: {"label_ko": t["names"]["ko"], "summary": t["summary"]} for t in rows(d, "trait")},
        "sources": d["sources"],
        "terms": terms,
        "dimensions": dimensions,
    }


def service_vocabulary(d: dict) -> dict:
    sensory = rows(d, "aroma_family", "aroma", "texture", "finish_character")
    shown = sorted((t for t in sensory if "shown" in t.get("app", {})), key=lambda t: t["app"]["shown"]["order"])
    groups = [{
        "key": t["key"], "label_ko": s["label"], "category_key": s["category"], "domain": s["domain"],
        "source_keys": s["members"], "user_source_labels": s["source_labels"],
        "phases": s["phases"], "decision_origin": s["decision_origin"],
    } for t in shown for s in [t["app"]["shown"]]]
    hidden: dict[str, list[str]] = {}
    for t in sensory:
        reason = t.get("app", {}).get("hidden_reason")
        if reason:
            hidden.setdefault(reason, []).append(t["key"])
    pending = [
        {"key": t["key"], "label_ko": t["app"]["pending"]["label"], "reason": t["app"]["pending"]["reason"]}
        for t in sensory if "pending" in t.get("app", {})
    ]
    legacy = {old: t["key"] for t in sensory for old in t.get("extra", {}).get("legacy_keys", [])}
    v = d["versions"]["service_vocabulary"]
    return {
        "schema_version": v["schema_version"], "taxonomy_version": v["taxonomy_version"],
        "decision": v["decision"],
        "categories": d["app_categories"], "groups": groups,
        "hidden": [{"reason": r, "source_keys": keys} for r, keys in hidden.items()],
        "pending": pending, "legacy_aliases": legacy,
        "folded_reasons": d["app_folded_reasons"],
    }


def abv_bands(d: dict) -> dict:
    def bands(type_: str) -> dict:
        out = {}
        for t in rows(d, type_):
            h = t.get("hints", {})
            if "abv_bounds" in h:
                out[t["key"]] = {"bounds": h["abv_bounds"], "verified": h["abv_verified"], "source": h["abv_source"]}
        return out
    return {
        "description": d["versions"]["abv_bands"], "levels": d["abv_levels"],
        "categories": bands("category"), "styles": bands("kind"),
    }


def producer_profiles(d: dict) -> dict:
    producers = []
    for t in rows(d, "producer"):
        e = t.get("extra", {})
        producers.append({
            "key": t["key"], "kind": e.get("kind"), "name_ko": t["names"]["ko"], "name_en": t["names"].get("en"),
            "country": e.get("country"), "region": e.get("region"), "peat": t.get("hints", {}).get("peat"),
            "house_casks": t.get("hints", {}).get("house_casks", []), "intro_ko": t.get("summary"),
            "traits": traits(t), "aromas": aromas(t), "varies_ko": t.get("varies"),
        })
    return {"schemaVersion": d["versions"]["producer_profiles"], "producers": producers}


def taxonomy_entry(t: dict, fields) -> dict:
    """One taxonomy item in its own field order: (field, value or None) pairs,
    taxonomy-only fields from extra.taxonomy filling the rest."""
    rest = t.get("extra", {}).get("taxonomy", {})
    out = {}
    for field, value in fields:
        if value is not None:
            out[field] = value
        elif field in rest:
            out[field] = rest[field]
    return out


def taxonomy_term(t: dict, key_field: str, parent_field: str | None = None, middle=()) -> dict:
    n = t["names"]
    return taxonomy_entry(t, [
        (key_field, t["key"]),
        *([(parent_field, t.get("parent"))] if parent_field else []),
        *[(f, None) for f in middle],
        ("name_ko", n["ko"]), ("name_en", n.get("en")), ("definition", t.get("definition_en")),
        ("definition_source", None), ("source_standard_url", None),
        ("aliases", n.get("aliases", [])), ("applies_to_categories", t.get("categories")),
        ("parent_ingredient_key", None), ("parent_term_key", None),
        ("excludes_term_keys", None), ("applies_to_styles", None),
    ])


def taxonomy(d: dict) -> dict:
    by_key = {(t["type"], t["key"]): t for t in d["terms"]}

    def kinds_only(type_: str, key_field: str = "key") -> list[dict]:
        return [taxonomy_term(t, key_field) for t in rows(d, type_)]

    def descriptor(key: str) -> dict:
        t = next(by_key[(ty, key)] for ty in ("aroma", "texture", "finish_character", "aroma_family") if (ty, key) in by_key)
        x = t["extra"]["taxonomy"]
        return {"descriptor_key": key, "descriptor_family": x["descriptor_family"],
                "name_ko": x["name_ko"], "name_en": x["name_en"], "definition": t["definition_en"],
                **{f: x[f] for f in ("aliases", "sensory_phases", "applies_to_categories", "parent_descriptor_key") if f in x}}

    unplaced = {x["descriptor_key"]: x for x in d["unplaced_descriptors"]}
    descriptors = [unplaced.get(k) or descriptor(k) for k in d["taxonomy_order"]["descriptors"]]
    dimensions = [
        taxonomy_entry(t, [("dimension_key", t["key"]), ("name_ko", t["names"]["ko"]),
                           ("name_en", t["names"].get("en")), ("definition", t.get("definition_en")),
                           *[(f, None) for f in ("sensory_phase", "minimum", "maximum", "unknown_allowed",
                                                 "supports_explicit_absence", "applies_to_categories", "bands")]])
        for t in rows(d, "axis") if "taxonomy" in t.get("extra", {})
    ]
    v = d["versions"]["taxonomy"]
    return {
        "$schema": v["schema"],
        "taxonomy_version": v["version"],
        "base_taxonomy": d["base_taxonomy"],
        "ingredients": {
            "types": kinds_only("ingredient_type"),
            "roles": d["ingredient_roles"],
            "terms": [taxonomy_term(t, "ingredient_key", "ingredient_type_key") for t in rows(d, "ingredient")],
        },
        "governance": d["governance"],
        "source_mapping_policy": d["source_mapping_policy"],
        "categories": [
            taxonomy_entry(t, [("category_key", t["key"]), ("name_ko", t["names"]["ko"]),
                               ("name_en", t["names"].get("en")), ("sort_order", None)])
            for t in rows(d, "category")
        ],
        "primary_styles": [taxonomy_term(by_key[("kind", k)], "style_key", "category_key")
                           for k in d["taxonomy_order"]["kinds"]],
        "sensory": {"phase_keys": d["sensory_phases"], "descriptors": descriptors, "scalar_dimensions": dimensions},
        "production": {
            "process_kinds": kinds_only("process_kind"),
            "process_terms": [taxonomy_term(t, "term_key", "kind_key", ("process_stage",)) for t in rows(d, "process")],
            "maturation_kinds": kinds_only("maturation_kind"),
            "maturation_terms": [taxonomy_term(t, "term_key", "kind_key", ("process_stage",)) for t in rows(d, "maturation")],
        },
        "style_redirects": d["style_redirects"],
    }


VIEWS = {
    "style_profiles": style_profiles,
    "catalog": sensory_catalog,
    "term_knowledge": term_knowledge,
    "service_vocabulary": service_vocabulary,
    "abv_bands": abv_bands,
    "producer_profiles": producer_profiles,
    "taxonomy": taxonomy,
}
