"""The one dictionary: every term the reader can meet, one row shape.

catalog/dictionary/terms.json is the only knowledge source. It was merged on
2026-10-27 from the six knowledge files that used to live in catalog/sensory
(style table, aroma tree, term knowledge, service vocabulary, ABV bands,
producer profiles); `build_from` still takes those six shapes, which
tools/catalog/dictionary/project.py projects back out of the dictionary, so a
tool may edit a view and persist it (`project.rebuild` + `project.save`).
The enrichment taxonomy (names, definitions and term lists of kinds,
ingredients, processes, maturation, axes and aroma descriptors, plus its
file-level policy sections) was folded in on 2026-10-28; `project.taxonomy`
gives back its old shape and `build_from` takes that shape as a seventh input.

Row shape (empty slots are left out of the file):
  key, type, parent, categories, names{ko,en,aliases,label_patterns}, summary,
  definition_en, taste{axis:{level,basis,reason,evidence,detail,sources}},
  aromas[{key,basis,reason,source_kind,source,sources}], varies,
  hints{...}, traits[], app{...}, sources[], extra{...}

Usage:
  python3 -m tools.catalog.dictionary.build    # rebuilds terms.json from its own views
                                               # (a no-op unless the build code changed)
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "catalog/dictionary/terms.json"

TYPES = (
    "category", "kind", "grape", "regional_style", "ingredient_type", "ingredient",
    "process_kind", "process", "maturation_kind", "maturation", "axis", "trait",
    "aroma_family", "aroma", "texture", "finish_character", "producer",
)

SLOTS = (
    "key", "type", "parent", "categories", "names", "summary", "definition_en",
    "taste", "aromas", "varies", "hints", "traits", "app", "sources", "extra",
)

TRAIT_FIELDS = {"level": "level", "basis": "basis", "reason_ko": "reason",
                "evidence_ko": "evidence", "detail_ko": "detail", "grade": "grade",
                "sources": "sources"}
AROMA_FIELDS = {"key": "key", "basis": "basis", "reason_ko": "reason",
                "source_kind": "source_kind", "source_ko": "source", "feel": "feel",
                "grade": "grade", "sources": "sources"}


def read(path: str):
    with open(ROOT / path, encoding="utf-8") as fp:
        return json.load(fp)


def row(key: str, type_: str, **slots) -> dict:
    base = {s: None for s in SLOTS}
    base.update(key=key, type=type_, names={"ko": None, "en": None, "aliases": [], "label_patterns": []},
                taste={}, aromas=[], hints={}, traits=[], app={}, sources=[], extra={})
    for name, value in slots.items():
        if name not in base:
            raise KeyError(f"{key}: unknown slot {name}")
        base[name] = value
    return base


def rename(obj: dict, fields: dict, where: str) -> dict:
    unknown = set(obj) - set(fields)
    if unknown:
        raise ValueError(f"{where}: unexpected fields {sorted(unknown)}")
    return {fields[k]: obj[k] for k in fields if k in obj}


def trait_slots(traits: dict, where: str) -> dict:
    return {axis: rename(t, TRAIT_FIELDS, f"{where}.{axis}") for axis, t in traits.items()}


def aroma_slots(aromas: list, where: str) -> list:
    return [rename(a, AROMA_FIELDS, f"{where}.aromas") for a in aromas]


def names(ko, en=None, aliases=(), label_patterns=()) -> dict:
    return {"ko": ko, "en": en, "aliases": list(aliases), "label_patterns": list(label_patterns)}


def abv_hint(band) -> dict:
    if not band:
        return {}
    return {"abv_bounds": band["bounds"], "abv_verified": band.get("verified"), "abv_source": band.get("source")}


def leftovers(obj: dict, used: set) -> dict:
    return {k: v for k, v in obj.items() if k not in used}


def taxonomy_extra(obj: dict, used: set) -> dict:
    """Taxonomy-only fields (standards, evidence policy) sit under one key so
    knowledge leftovers and registry leftovers never mix."""
    rest = leftovers(obj, used)
    return {"taxonomy": rest} if rest else {}


def build() -> tuple[dict, dict]:
    """The dictionary rebuilt from its own views, keeping every row and slot the views do not carry."""
    from tools.catalog.dictionary import project

    dictionary = project.rebuild({})
    return dictionary, report_of(dictionary)


def build_from(sources: dict) -> tuple[dict, dict]:
    """The dictionary from the seven old shapes (files or views), taxonomy included.

    Views projected out of the dictionary rebuild the same dictionary, so a tool
    may edit a view and persist it through this function.
    """
    sp = sources["style_profiles"]
    cat = sources["catalog"]
    tk = sources["term_knowledge"]
    sv = sources["service_vocabulary"]
    abv = sources["abv_bands"]
    producers = sources["producer_profiles"]
    tax = sources["taxonomy"]

    rows: dict[tuple[str, str], dict] = {}

    def put(r: dict) -> dict:
        k = (r["type"], r["key"])
        if k in rows:
            raise ValueError(f"duplicate row {k}")
        rows[k] = r
        return r

    # --- categories and kinds
    for c in tax["categories"]:
        put(row(
            c["category_key"], "category",
            names=names(c["name_ko"], c["name_en"]),
            hints=abv_hint(abv["categories"].get(c["category_key"])),
            extra=taxonomy_extra(c, {"category_key", "name_ko", "name_en"}),
        ))
    profiles = {s["key"]: s for s in sp["styles"]}
    kind_order = {k: i for i, k in enumerate(profiles)}
    for s in sorted(tax["primary_styles"], key=lambda s: kind_order.get(s["style_key"], len(kind_order))):
        p = profiles.get(s["style_key"], {})
        put(row(
            s["style_key"], "kind",
            parent=s["category_key"],
            categories=s.get("applies_to_categories"),
            names=names(s["name_ko"], s["name_en"], s.get("aliases", [])),
            summary=p.get("intro_ko"),
            definition_en=s.get("definition"),
            taste=trait_slots(p.get("traits", {}), s["style_key"]),
            aromas=aroma_slots(p.get("aromas", []), s["style_key"]),
            varies=p.get("varies_ko"),
            hints=abv_hint(abv["styles"].get(s["style_key"])),
            extra={
                **leftovers(p, {"key", "name_ko", "intro_ko", "traits", "aromas", "varies_ko"}),
                **taxonomy_extra(s, {"style_key", "category_key", "applies_to_categories", "name_ko", "name_en", "aliases", "definition"}),
            },
        ))
    missing_profiles = sorted(set(profiles) - {s["style_key"] for s in tax["primary_styles"]})
    if missing_profiles:
        raise ValueError(f"style-profiles kinds not in the taxonomy: {missing_profiles}")

    # --- grapes and regional styles
    for g in sp["wine_grapes"]:
        put(row(
            g["key"], "grape",
            categories=["wine"],
            names=names(g["name_ko"], label_patterns=g["match"]["patterns"]),
            summary=g["intro_ko"],
            taste=trait_slots(g.get("traits", {}), g["key"]),
            aromas=aroma_slots(g.get("aromas", []), g["key"]),
            varies=g.get("varies_ko"),
            hints={"colors": g.get("colors", [])},
            extra=leftovers(g, {"key", "name_ko", "intro_ko", "colors", "match", "traits", "aromas", "varies_ko"}),
        ))
    for r in sp["wine_regions"]:
        put(row(
            r["key"], "regional_style",
            categories=["wine"],
            names=names(r["name_ko"], label_patterns=r["match"].get("name_patterns", [])),
            summary=r["intro_ko"],
            taste=trait_slots(r.get("traits", {}), r["key"]),
            aromas=aroma_slots(r.get("aromas", []), r["key"]),
            varies=r.get("varies_ko"),
            hints={
                "color": r.get("color"),
                "region_labels": r["match"].get("region_labels", []),
                **({"style_keys": r["match"]["style_keys"]} if "style_keys" in r["match"] else {}),
            },
            extra=leftovers(r, {"key", "name_ko", "color", "intro_ko", "match", "traits", "aromas", "varies_ko"}),
        ))

    # --- ingredient types, process kinds, maturation kinds
    for section, type_ in (
        (tax["ingredients"]["types"], "ingredient_type"),
        (tax["production"]["process_kinds"], "process_kind"),
        (tax["production"]["maturation_kinds"], "maturation_kind"),
    ):
        for g in section:
            put(row(
                g["key"], type_,
                names=names(g["name_ko"], g["name_en"], g.get("aliases", [])),
                definition_en=g.get("definition"),
                extra=taxonomy_extra(g, {"key", "name_ko", "name_en", "aliases", "definition"}),
            ))

    # --- ingredients, processes, maturation
    for i in tax["ingredients"]["terms"]:
        put(row(
            i["ingredient_key"], "ingredient",
            parent=i.get("ingredient_type_key"),
            categories=i.get("applies_to_categories"),
            names=names(i["name_ko"], i["name_en"], i.get("aliases", [])),
            definition_en=i.get("definition"),
            extra=taxonomy_extra(i, {"ingredient_key", "ingredient_type_key", "applies_to_categories", "name_ko", "name_en", "aliases", "definition"}),
        ))
    process_knowledge = {p["key"]: p for p in sp["processes"]}
    process_order = {k: i for i, k in enumerate(process_knowledge)}
    for section, type_ in (("process_terms", "process"), ("maturation_terms", "maturation")):
        for t in tax["production"][section]:
            p = process_knowledge.pop(t["term_key"], {})
            if p:
                p = {**p, "style_table_order": process_order[t["term_key"]]}
            put(row(
                t["term_key"], type_,
                parent=t.get("kind_key"),
                categories=t.get("applies_to_categories"),
                names=names(t["name_ko"], t["name_en"], t.get("aliases", [])),
                summary=p.get("intro_ko"),
                definition_en=t.get("definition"),
                taste=trait_slots(p.get("traits", {}), t["term_key"]),
                aromas=aroma_slots(p.get("aromas", []), t["term_key"]),
                hints={"fact_label": p["fact_ko"]} if p.get("fact_ko") else {},
                extra={
                    **leftovers(p, {"key", "name_ko", "intro_ko", "traits", "aromas", "fact_ko"}),
                    **taxonomy_extra(t, {"term_key", "kind_key", "applies_to_categories", "name_ko", "name_en", "aliases", "definition"}),
                },
            ))
    if process_knowledge:
        raise ValueError(f"style-profiles processes not in the taxonomy: {sorted(process_knowledge)}")

    def references(ids) -> list[dict]:
        """A source as one object: the reference id with its title and url."""
        return [{"id": i, **tk["sources"][i]} for i in ids]

    # --- axes: taxonomy dimensions plus the style table's extra ones
    tax_dims = {d["dimension_key"]: d for d in tax["sensory"]["scalar_dimensions"]}
    for key in list(tax_dims) + [d for d in sp["dimensions"] if d not in tax_dims]:
        d = tax_dims.get(key, {})
        k = tk["dimensions"].get(key, {})
        put(row(
            key, "axis",
            names=names(d.get("name_ko", key), d.get("name_en")),
            summary=k.get("sensory_description"),
            definition_en=d.get("definition"),
            traits=k.get("sensory_trait_keys", []),
            sources=references(k.get("source_ids", [])),
            extra={
                **taxonomy_extra(d, {"dimension_key", "name_ko", "name_en", "definition"}),
                **({"style_axis": True} if key in sp["dimensions"] else {}),
            },
        ))
    # A trait's view entry is {"label_ko", "summary"}; the old one-text shape
    # (label = summary) is still accepted.
    for key, text in tk["traits"].items():
        label, summary = (text, text) if isinstance(text, str) else (text["label_ko"], text["summary"])
        put(row(key, "trait", names=names(label), summary=summary))

    # --- aromas, textures, finish characters, families
    group_rows = {g["key"]: g for g in sv["groups"]}
    group_of = {src: g["key"] for g in sv["groups"] for src in g["source_keys"]}
    hidden = {k: h["reason"] for h in sv["hidden"] for k in h["source_keys"]}
    pending = {p["key"]: p for p in sv["pending"]}
    legacy = {}
    for old, new in sv["legacy_aliases"].items():
        legacy.setdefault(new, []).append(old)

    def knowledge(key: str) -> dict:
        k = tk["terms"].get(key)
        if not k:
            return {}
        return {
            "summary": k.get("sensory_description"),
            "traits": k.get("sensory_trait_keys", []),
            "sources": references(k.get("source_ids", [])),
        }

    def app_slots(key: str, entry: dict) -> dict:
        app = {}
        g = group_of.get(key)
        if g:
            app["group"] = g
        if "onboarding_selectable" in entry:
            app["selectable"] = entry["onboarding_selectable"]
        if "phases" in entry:
            app["phases"] = entry["phases"]
        own = group_rows.get(key)
        if own:
            app["shown"] = {
                "order": list(group_rows).index(key),
                "label": own["label_ko"], "category": own["category_key"], "domain": own["domain"],
                "members": own["source_keys"], "source_labels": own["user_source_labels"],
                "phases": own["phases"], "decision_origin": own["decision_origin"],
            }
        if key in hidden:
            app["hidden_reason"] = hidden[key]
        if key in pending:
            app["pending"] = {"label": pending[key]["label_ko"], "reason": pending[key]["reason"]}
        tk_entry = tk["terms"].get(key)
        if tk_entry:
            app["db"] = tk_entry["catalog"]
        return app

    sensory_keys = {d["key"] for section, _ in (("descriptors", 0), ("textures", 0), ("finish_characters", 0)) for d in cat[section]}
    for f in cat["families"]:
        # A family that is also a sensory entry (꽃·과일 …) keeps its app and knowledge on that entry.
        shared = f["key"] in sensory_keys
        put(row(
            f["key"], "aroma_family",
            names=names(f["label_ko"]),
            **({} if shared else knowledge(f["key"])),
            app={} if shared else app_slots(f["key"], f),
            extra={**leftovers(f, {"key", "label_ko"}), "legacy_keys": [] if shared else legacy.get(f["key"], [])},
        ))
    sensory_sections = (("descriptors", "aroma"), ("textures", "texture"), ("finish_characters", "finish_character"))
    for section, type_ in sensory_sections:
        for d in cat[section]:
            put(row(
                d["key"], type_,
                parent=d.get("parent_key"),
                names=names(d["label_ko"], d.get("label_en"), d.get("aliases", [])),
                **knowledge(d["key"]),
                app=app_slots(d["key"], d),
                extra={
                    **leftovers(d, {"key", "label_ko", "label_en", "aliases", "parent_key", "onboarding_selectable", "phases"}),
                    "legacy_keys": legacy.get(d["key"], []),
                },
            ))
    # Service groups and DB-only terms that are not catalog entries of their own.
    known = {k for (_, k) in rows}
    for key, k in tk["terms"].items():
        if key in known:
            continue
        type_ = "texture" if key.endswith("_texture") or key.endswith("_sensation") else "aroma"
        put(row(
            key, type_,
            names=names(k["catalog"]["label_ko"]),
            summary=k.get("sensory_description"),
            traits=k.get("sensory_trait_keys", []),
            sources=references(k.get("source_ids", [])),
            app=app_slots(key, {}),
            extra={"knowledge_only": True, "legacy_keys": legacy.get(key, [])},
        ))
    unplaced = sorted(set(pending) - {k for (_, k) in rows}) + sorted(set(legacy) - {k for (_, k) in rows}) + sorted(set(hidden) - {k for (_, k) in rows}) + sorted(set(group_of) - {k for (_, k) in rows})
    if unplaced:
        raise ValueError(f"service vocabulary keys without a row: {unplaced}")

    # --- producers
    for p in producers["producers"]:
        put(row(
            p["key"], "producer",
            names=names(p["name_ko"], p.get("name_en")),
            summary=p.get("intro_ko"),
            taste=trait_slots(p.get("traits", {}), p["key"]),
            aromas=aroma_slots(p.get("aromas", []), p["key"]),
            varies=p.get("varies_ko"),
            hints={k: p[k] for k in ("house_casks", "peat") if p.get(k)},
            extra={k: p.get(k) for k in ("kind", "country", "region")},
        ))

    # --- aroma descriptors of the taxonomy: definition and registry fields onto the sensory row
    unplaced_descriptors = []
    for x in tax["sensory"]["descriptors"]:
        r = next((rows[(t, x["descriptor_key"])] for t in ("aroma", "texture", "finish_character", "aroma_family")
                  if (t, x["descriptor_key"]) in rows), None)
        if r is None:
            unplaced_descriptors.append(x)
            continue
        r["definition_en"] = x["definition"]
        r["extra"]["taxonomy"] = leftovers(x, {"descriptor_key", "definition"})

    # Source order is kept inside each type: readers that match in order keep their result.
    terms = [compact(rows[k]) for k in sorted(rows, key=lambda k: TYPES.index(k[0]))]
    dictionary = {
        "schema_version": 1,
        "versions": {
            "style_profiles": sp["schemaVersion"],
            "term_knowledge": tk["version"],
            "service_vocabulary": {"schema_version": sv["schema_version"], "taxonomy_version": sv["taxonomy_version"], "decision": sv["decision"]},
            "abv_bands": abv.get("description"),
            "producer_profiles": producers["schemaVersion"],
            "taxonomy": {"schema": tax["$schema"], "version": tax["taxonomy_version"]},
        },
        "style_axes": sp["dimensions"],
        "abv_levels": abv["levels"],
        "app_categories": sv["categories"],
        "app_folded_reasons": sv["folded_reasons"],
        "sources": tk["sources"],
        "trait_policy": tk["trait_policy"],
        "expression_rules": cat["expression_rules"],
        "base_taxonomy": tax["base_taxonomy"],
        "governance": tax["governance"],
        "source_mapping_policy": tax["source_mapping_policy"],
        "ingredient_roles": tax["ingredients"]["roles"],
        "sensory_phases": tax["sensory"]["phase_keys"],
        "style_redirects": tax["style_redirects"],
        # Row order inside a type follows the style table; the taxonomy's own order is kept here.
        "taxonomy_order": {
            "kinds": [s["style_key"] for s in tax["primary_styles"]],
            "descriptors": [x["descriptor_key"] for x in tax["sensory"]["descriptors"]],
        },
        "unplaced_descriptors": unplaced_descriptors,
        "terms": terms,
    }
    return dictionary, report_of(dictionary)


def report_of(dictionary: dict) -> dict:
    terms = dictionary["terms"]
    keys = {(t["type"], t["key"]) for t in terms}
    types = sorted({t["type"] for t in terms}, key=lambda t: TYPES.index(t) if t in TYPES else len(TYPES))
    return {
        "rows": len(terms),
        "by_type": {t: sum(1 for r in terms if r["type"] == t) for t in types},
        "unresolved_parents": sorted({
            r["parent"] for r in terms
            if r.get("parent") and not any((t, r["parent"]) in keys for t in types)
        }),
        "with_summary": sum(1 for r in terms if r.get("summary")),
        "with_taste": sum(1 for r in terms if r.get("taste")),
    }


def compact(r: dict) -> dict:
    """Drop empty slots so the file reads as what is known, not what is missing."""
    out = {}
    for k, v in r.items():
        if k == "names":
            out[k] = {nk: nv for nk, nv in v.items() if nv not in (None, [], {})}
        elif k == "extra":
            cleaned = {ek: ev for ek, ev in v.items() if ev not in (None, [], {})}
            if cleaned:
                out[k] = cleaned
        elif v not in (None, [], {}):
            out[k] = v
    return out


def render(dictionary: dict) -> str:
    return json.dumps(dictionary, ensure_ascii=False, indent=1) + "\n"


def main() -> int:
    dictionary, report = build()
    OUT.write_text(render(dictionary), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
