"""Views of the one dictionary in the shapes the tools and the card code read.

Each function returns what one of the former knowledge files held (style
table, aroma tree, term knowledge, service vocabulary, ABV bands, producer
profiles, enrichment taxonomy). `view(name)` reads the checked-in dictionary once per process and
hands out copies; `rebuild` + `save` persist an edited view.

The dictionary is kept as two files. terms.json holds what the card
functions and the app read. evidence.json holds where each value came from
(references, quotes, addresses, collection dates), which only the tools
read. `load` puts the evidence back in place, so a tool sees one dictionary
with `sources` where they belong; `save` writes the two files apart again.
Edit either file through `load` and `save`: a choice cue's evidence is kept
by the cue's position in its row.

In terms.json a row sits where it belongs (SECTIONS): what a drink is
(attributes: identity, terroir, making) or a word for what is sensed (senses:
nose, palate, finish), under its group and its parent. A regional style sits
under the region it is of (HELD). The tools still work
on one flat list of rows, each naming its type and parent: `flatten` reads
the file into that list and `nest` puts the list back into its sections.
The file states its own sections under `layout`, which the functions and the
app read it by.
"""

from __future__ import annotations

import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DICTIONARY = ROOT / "catalog/dictionary/terms.json"
EVIDENCE = ROOT / "catalog/dictionary/evidence.json"

TRAIT_FIELDS = (("level", "level"), ("basis", "basis"), ("reason", "reason_ko"),
                ("evidence", "evidence_ko"), ("detail", "detail_ko"), ("grade", "grade"), ("sources", "sources"))
AROMA_FIELDS = (("key", "key"), ("basis", "basis"), ("reason", "reason_ko"),
                ("source_kind", "source_kind"), ("source", "source_ko"), ("feel", "feel"), ("grade", "grade"),
                ("sources", "sources"))


# Where each type of row sits in terms.json: path, the type of the groups at
# the top of the section (None when the rows have no group), the type of the
# rows, and how a row names its group (`parent`, or `family` for
# extra.family_key). Below its group a row is kept under its parent row.
SECTIONS = (
    (("attributes", "identity", "kinds"), "category", "kind", "parent"),
    (("attributes", "identity", "ingredients"), "ingredient_type", "ingredient", "parent"),
    (("attributes", "identity", "grapes"), None, "grape", None),
    (("attributes", "identity", "producers"), None, "producer", None),
    (("attributes", "terroir", "regions"), None, "region", None),
    (("attributes", "making", "processes"), "process_kind", "process", "parent"),
    (("attributes", "making", "maturations"), "maturation_kind", "maturation", "parent"),
    (("senses", "nose", "axes"), None, "axis", None),
    (("senses", "nose", "aromas"), "aroma_family", "aroma", "family"),
    (("senses", "nose", "aromas_without_family"), None, "aroma", None),
    (("senses", "palate", "axes"), None, "axis", None),
    (("senses", "palate", "textures"), "aroma_family", "texture", "family"),
    (("senses", "palate", "textures_without_family"), None, "texture", None),
    (("senses", "finish", "axes"), None, "axis", None),
    (("senses", "finish", "characters"), "aroma_family", "finish_character", "family"),
    (("unplaced", "regional_styles"), None, "regional_style", None),
    (("unplaced", "label_words"), None, "label_word", None),
    (("unplaced", "traits"), None, "trait", None),
)
# Rows kept under a row of another type: the type of the row above, then for
# each kind of row it holds the name they are kept under, their type and the
# field of `extra` by which they name the row above. A regional style sits
# under the region it is of; one that is of no region stays unplaced.
HELD = {"region": (("styles", "regional_style", "region_key"),)}
# What a regional style is made from and how (hints.grapes, hints.making): the
# keys of grape rows, or of process and maturation rows, the leading one
# first, and whether the place's rules set them or its makers usually choose
# them. `note` says a link was written without a checked source (문헌 근거 미확인).
LINK_BASES = ("rule", "typical")
# A region's climate (hints.climate), which the acidity, weight and ripeness
# of what grows there follow from. A region that states none has the climate
# of the region above it.
CLIMATES = ("cool", "moderate", "warm", "hot")
# A taste line's level is a step from 1 to 5, the scale an answer and a
# bottle are on. A line written before the steps were collected still holds
# the word for where it stands (low is 1 or 2, mid is 3, high is 4 or 5), and
# a drink with no bubbles states "none" for carbonation.
LEVEL_WORDS = ("low", "mid", "high")


def level_word(axis: str, level) -> str:
    """The word a line's level stands under, for readers that compare by word.

    Sweetness counts from none (1 is dry), so its second step already says
    some sweetness is there; every other axis has little of itself at 2.
    """
    if isinstance(level, str):
        return level
    if axis == "sweetness":
        return "low" if level == 1 else "mid" if level <= 3 else "high"
    return "low" if level <= 2 else "mid" if level == 3 else "high"
# The place an axis is sensed; every other axis is of the palate.
AXIS_PLACE = {"aroma_intensity": "nose", "finish_length": "finish", "finish_cleanliness": "finish"}
# The rows a family groups, by the family's extra.domain.
FAMILY_ITEMS = {"descriptor": "aroma", "texture": "texture", "finish_character": "finish_character"}


def flatten(file: dict) -> dict:
    """terms.json as one flat list of rows, each naming its type and parent."""
    rows: list[dict] = []

    def walk(nodes: list, type_: str, item_type: str, link: str | None, above: dict | None) -> None:
        held = HELD.get(type_, ())
        own = {"key", "items", *(name for name, _, _ in held)}
        for node in nodes:
            row = {"key": node["key"], "type": type_}
            if above is not None and (above["type"] == type_ or link == "parent"):
                row["parent"] = above["key"]
            row.update((k, v) for k, v in node.items() if k not in own)
            if above is not None and "parent" not in row:
                row["extra"] = {**row.get("extra", {}), "family_key": above["key"]}
            rows.append(row)
            for name, held_type, field in held:
                for kept in node.get(name, []):
                    rows.append({"key": kept["key"], "type": held_type, **kept,
                                 "extra": {**kept.get("extra", {}), field: node["key"]}})
            walk(node.get("items", []), item_type, item_type, link, row)

    for path, group_type, item_type, link in SECTIONS:
        nodes = file
        for name in path:
            nodes = nodes[name]
        walk(nodes, group_type or item_type, item_type, link, None)
    out = {k: v for k, v in file.items() if k not in ("layout", "attributes", "senses", "unplaced")}
    out["terms"] = rows
    return out


def nest(d: dict) -> dict:
    """The flat list of rows put into the sections of terms.json."""
    by_type: dict[str, list[dict]] = {}
    for t in d["terms"]:
        by_type.setdefault(t["type"], []).append(t)
    placed = 0

    # A row's parent names a row of its own type only where no group does
    # (a region under a region, an aroma under an aroma): 포도 the ingredient
    # sits under 포도 the ingredient type, which has the same key.
    children: dict[tuple[str, str], list[dict]] = {}
    for item_type in {s[2] for s in SECTIONS} - {s[2] for s in SECTIONS if s[3] == "parent"}:
        for t in by_type.get(item_type, []):
            if t.get("parent"):
                children.setdefault((item_type, t["parent"]), []).append(t)

    # The rows kept under a row of another type, by their type and the row they name.
    held_by = {held_type: field for helds in HELD.values() for _, held_type, field in helds}
    kept_under: dict[tuple[str, str], list[dict]] = {}
    for held_type, field in held_by.items():
        for t in by_type.get(held_type, []):
            if field in t.get("extra", {}):
                kept_under.setdefault((held_type, t["extra"][field]), []).append(t)

    def node(t: dict, named_by: str | None = None) -> dict:
        """A row as the file keeps it; `named_by` is the field of extra its place already states."""
        nonlocal placed
        placed += 1
        # A country keeps the empty parent it is written with; any other parent is the row above.
        out = {k: v for k, v in t.items() if k != "type" and (k != "parent" or v is None)}
        if named_by:
            extra = {k: v for k, v in t["extra"].items() if k != named_by}
            out.pop("extra")
            if extra:
                out["extra"] = extra
        for name, held_type, field in HELD.get(t["type"], ()):
            kept = [node(c, field) for c in kept_under.pop((held_type, t["key"]), [])]
            if kept:
                out[name] = kept
        items = [node(c) for c in children.pop((t["type"], t["key"]), [])]
        if items:
            out["items"] = items
        return out

    def group_of(t: dict, link: str | None) -> str | None:
        if t.get("parent"):
            return None if link == "family" else t["parent"]
        return t.get("extra", {}).get("family_key") if link == "family" else None

    out = {k: v for k, v in d.items() if k != "terms"}
    # The functions and the app read the file by this table, so they need no copy of SECTIONS.
    out["layout"] = [
        {"path": list(path), "group": group_type, "item": item_type, "link": link,
         **({"held": [{"under": name, "item": held_type, "names": field}
                      for type_ in (group_type, item_type) for name, held_type, field in HELD.get(type_, ())]}
            if HELD.get(group_type) or HELD.get(item_type) else {})}
        for path, group_type, item_type, link in SECTIONS
    ]
    for path, group_type, item_type, link in SECTIONS:
        items = by_type.get(item_type, [])
        if item_type == "axis":
            nodes = [node(t) for t in items if AXIS_PLACE.get(t["key"], "palate") == path[1]]
        elif group_type is None:
            # Rows under no group: the top of a tree, or the rows a family does not hold.
            grouped = any(s[2] == item_type and s[1] for s in SECTIONS)
            nodes = [node(t) for t in items
                     if not t.get("parent") and not (grouped and t.get("extra", {}).get("family_key"))
                     and held_by.get(item_type) not in t.get("extra", {})]
        else:
            groups = [g for g in by_type.get(group_type, [])
                      if group_type != "aroma_family" or FAMILY_ITEMS[g["extra"]["domain"]] == item_type]
            nodes = []
            for g in groups:
                held = [node(t, "family_key" if link == "family" else None) for t in items if group_of(t, link) == g["key"]]
                nodes.append({**node(g), **({"items": held} if held else {})})
        section = out
        for name in path[:-1]:
            section = section.setdefault(name, {})
        section[path[-1]] = nodes
    if placed != len(d["terms"]):
        raise ValueError(f"{len(d['terms']) - placed} rows have no place in the dictionary's sections")
    return out


_cache: dict | None = None


def load() -> dict:
    """The dictionary with the evidence of its values put back in place."""
    return with_evidence(
        flatten(json.loads(DICTIONARY.read_text(encoding="utf-8"))),
        json.loads(EVIDENCE.read_text(encoding="utf-8")),
    )


def source_holders(t: dict):
    """Every place of a row that can carry sources, as (slot, name, holder)."""
    yield None, None, t
    for axis, trait in t.get("taste", {}).items():
        yield "taste", axis, trait
    for aroma in t.get("aromas", []):
        yield "aromas", aroma["key"], aroma
    for place, cue in enumerate(t.get("hints", {}).get("choice_cues", [])):
        yield "choice_cues", str(place), cue


def without_evidence(d: dict) -> tuple[dict, dict]:
    """The dictionary as terms.json keeps it, and what evidence.json keeps."""
    d = copy.deepcopy(d)
    evidence = {"references": d.pop("sources"), "terms": {}}
    for t in d["terms"]:
        kept: dict = {}
        for slot, name, holder in source_holders(t):
            sources = holder.pop("sources", None)
            if not sources:
                continue
            if slot is None:
                kept["sources"] = sources
            else:
                kept.setdefault(slot, {})[name] = sources
        if kept:
            evidence["terms"][f"{t['type']}:{t['key']}"] = kept
    return d, evidence


def with_evidence(d: dict, evidence: dict) -> dict:
    d = {**d, "sources": evidence["references"]}
    left = copy.deepcopy(evidence["terms"])
    for t in d["terms"]:
        kept = left.pop(f"{t['type']}:{t['key']}", None)
        if not kept:
            continue
        for slot, name, holder in source_holders(t):
            sources = kept.pop("sources", None) if slot is None else kept.get(slot, {}).pop(name, None)
            if sources:
                holder["sources"] = sources
        stray = {slot: names for slot, names in kept.items() if names}
        if stray:
            raise ValueError(f"evidence for places {t['type']}:{t['key']} does not have: {stray}")
    if left:
        raise ValueError(f"evidence for rows the dictionary does not have: {sorted(left)}")
    return d


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
    """Write the dictionary as its two files and forget the cached copy."""
    global _cache
    from tools.catalog.dictionary.build import render
    terms, evidence = without_evidence(d)
    DICTIONARY.write_text(render(nest(terms)), encoding="utf-8")
    EVIDENCE.write_text(render(evidence), encoding="utf-8")
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


def style_regions(t: dict) -> list[str]:
    """The regions whose bottles read as a regional style without the label naming it.

    The region the style sits under, unless hints.regions says otherwise: only
    some of the places inside it, more than one region, or none (the style is
    then read from the name on the label alone).
    """
    if "regions" in t["hints"]:
        return t["hints"]["regions"]
    return [t["extra"]["region_key"]]


def region_label(key: str, regions: dict) -> str:
    """A region as a bottle's region line names it: '부르고뉴(Bourgogne) > 샤블리(Chablis)', country left out.

    A country is named by itself. No region line starts with a country, so a
    style of a whole country (젝트) is read only from the name on a bottle
    that states no region.
    """
    def name(key: str) -> str:
        names = regions[key]["names"]
        return f"{names['ko']}({names['en']})" if names.get("en") else names["ko"]

    parts: list[str] = []
    while regions[key]["parent"]:
        parts.insert(0, name(key))
        key = regions[key]["parent"]
    return " > ".join(parts) or name(key)


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
            "traits": traits(t), "aromas": aromas(t), "varies_ko": t.get("varies"), **extra(t),
        })
    regions = []
    region_rows = {t["key"]: t for t in rows(d, "region")}
    for t in rows(d, "regional_style"):
        match = {
            "region_labels": [region_label(key, region_rows) for key in style_regions(t)],
            "name_patterns": t["names"].get("label_patterns", []),
        }
        if "regions" in t["hints"]:
            match["regions"] = t["hints"]["regions"]
        if "not_named" in t["hints"]:
            match["not_named"] = t["hints"]["not_named"]
        if "style_keys" in t["hints"]:
            match["style_keys"] = t["hints"]["style_keys"]
        regions.append({
            "key": t["key"], "name_ko": t["names"]["ko"], "color": t["hints"]["color"],
            "intro_ko": t["summary"], "match": match,
            "traits": traits(t), "aromas": aromas(t), "varies_ko": t.get("varies"), **extra(t),
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
