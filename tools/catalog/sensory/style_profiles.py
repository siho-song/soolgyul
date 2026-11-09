"""Style character table: sensory traits fixed by how a drink is made.

The table (the kind, grape, regional style and process rows of
``catalog/dictionary/terms.json``) has layers, from broad to
specific: drink style, wine grape, wine region, producer and stated process
(a cask or peat the product name declares). A product gets its style entry,
for wine every grape and region entry whose patterns match its name or region,
its producer entry (the producer rows of the same dictionary) and the process
entries for its process keys. More specific layers override broader ones per
dimension; conflicting claims inside the grape layer cancel each other.

Two product layers sit on top: the stated ABV of a spirit sets its alcohol
presence, and levels the product's own notes, retailer scales or name state win
over the table. Prose adjusts the table by one step at most; an outright figure
(a 1-5 scale, a word in the name, the ABV) is taken as it is.
"""

from __future__ import annotations

from typing import Any, Iterable

from tools.catalog.dictionary import project as dictionary

DIMENSIONS = (
    "sweetness", "acidity", "bitterness", "astringency", "body", "carbonation",
    "alcohol_presence", "finish_length", "finish_cleanliness", "aroma_intensity",
)
# Lines the card reads but the catalog never stores as a level: how the still
# and the cask round a spirit's alcohol off (매끄러움, 거침).
TRAIT_ONLY_DIMENSIONS = ("smoothness",)
LEVELS = frozenset({"low", "mid", "high"})
CARBONATION_LEVELS = LEVELS | {"none"}
BASES = frozenset({"production", "typical", "collected", "aggregate"})
WINE_COLORS = {
    "red_wine": "red", "white_wine": "white", "sparkling_wine": "sparkling",
    "rose_wine": "rose", "orange_wine": "orange",
}
# Fortified styles carry no colour; region entries reach them only via match.style_keys.
WINE_STYLE_KEYS = frozenset(WINE_COLORS) | {
    "fortified_wine", "port_wine", "sherry_wine", "madeira_wine",
}
SECTIONS = ("styles", "wine_grapes", "wine_regions", "processes", "producers")
HOUSE_PEAT_LEVELS = frozenset({"medium", "heavy"})
PRODUCER_KINDS = frozenset({"distillery", "blend_brand", "brand", "winery", "brewery"})
# Below 20% ABV the style entry already describes the heat; above it ABV decides.
SPIRIT_ABV_FLOOR = 20.0
HIGH_HEAT_ABV = 35.0
# Level sources that come from the product itself; "catalog" levels are placeholders
# and "style", "same_line" and "fill" are estimates.
PRODUCT_LEVEL_SOURCES = frozenset({
    "note", "note_modifier", "name", "abv", "term_map", "wine21_scale", "wine21_note",
    "dailyshot", "sdh_note", "shop_note", "tippsy_note", "sbsaq_note", "review",
})
# Sources that state a figure outright rather than an adjective read out of prose.
EXPLICIT_LEVEL_SOURCES = frozenset({"wine21_scale", "name", "abv", "review"})
SPARKLING_NAME_PATTERNS = ("sparkling", "스파클링", "발포", "활성")


def load_style_profiles() -> dict[str, Any]:
    """The style table out of the dictionary, producer entries under ``producers``."""
    table = dictionary.view("style_profiles")
    table["producers"] = dictionary.view("producer_profiles")["producers"]
    return table


def taxonomy_process_keys() -> set[str]:
    production = dictionary.view("taxonomy")["production"]
    return {term["term_key"] for term in production["process_terms"] + production["maturation_terms"]}


def taxonomy_style_keys() -> set[str]:
    taxonomy = dictionary.view("taxonomy")
    return {style["style_key"] for style in taxonomy["primary_styles"]}


def sensory_descriptor_keys() -> set[str]:
    return {term["key"] for term in dictionary.view("catalog")["descriptors"]}


def validate_style_profiles(
    table: dict[str, Any], style_keys: set[str], aroma_keys: set[str], process_keys: set[str]
) -> list[str]:
    """Return human-readable problems; an empty list means the table is valid."""
    errors: list[str] = []
    seen: set[str] = set()
    for section in SECTIONS:
        for entry in table.get(section, []):
            where = f"{section}:{entry.get('key')}"
            if entry.get("key") in seen:
                errors.append(f"{where}: duplicate key")
            seen.add(entry.get("key"))
            for field in ("name_ko", "intro_ko"):
                if not entry.get(field):
                    errors.append(f"{where}: missing {field}")
            errors.extend(_trait_errors(where, entry.get("traits", {})))
            for key in entry.get("replaces_aromas", []):
                if key not in aroma_keys:
                    errors.append(f"{where}: unknown replaced aroma key {key}")
            for aroma in entry.get("aromas", []):
                if aroma.get("key") not in aroma_keys:
                    errors.append(f"{where}: unknown aroma key {aroma.get('key')}")
                if aroma.get("basis") not in BASES:
                    errors.append(f"{where}: aroma {aroma.get('key')} has bad basis")
            if section == "styles" and entry["key"] not in style_keys:
                errors.append(f"{where}: unknown style key")
            if section == "wine_grapes":
                if not set(entry.get("colors", [])) <= set(WINE_COLORS.values()):
                    errors.append(f"{where}: bad colors")
                if not entry.get("match", {}).get("patterns"):
                    errors.append(f"{where}: no match patterns")
            if section == "wine_regions":
                if entry.get("color") not in set(WINE_COLORS.values()) | {"any"}:
                    errors.append(f"{where}: bad color")
                match = entry.get("match", {})
                if not (match.get("region_labels") or match.get("name_patterns")):
                    errors.append(f"{where}: no match labels or patterns")
                if not set(match.get("style_keys", [])) <= WINE_STYLE_KEYS:
                    errors.append(f"{where}: bad match.style_keys")
            if section == "processes" and entry["key"] not in process_keys:
                errors.append(f"{where}: unknown process key")
            if section == "producers" and entry.get("kind") not in PRODUCER_KINDS:
                errors.append(f"{where}: bad kind {entry.get('kind')}")
    covered = {entry["key"] for entry in table.get("styles", [])}
    for missing in sorted(style_keys - covered):
        errors.append(f"styles: taxonomy style {missing} has no entry")
    return errors


def _trait_errors(where: str, traits: dict[str, Any]) -> list[str]:
    errors = []
    for dimension, claim in traits.items():
        if dimension not in DIMENSIONS + TRAIT_ONLY_DIMENSIONS:
            errors.append(f"{where}: unknown dimension {dimension}")
            continue
        allowed = CARBONATION_LEVELS if dimension == "carbonation" else LEVELS
        if claim.get("level") not in allowed:
            errors.append(f"{where}: {dimension} has bad level {claim.get('level')}")
        if claim.get("basis") not in BASES:
            errors.append(f"{where}: {dimension} has bad basis")
        if not claim.get("reason_ko"):
            errors.append(f"{where}: {dimension} has no reason_ko")
    return errors


def house_process_keys(producer: dict[str, Any]) -> list[str]:
    """Processes that define a producer's core range: house casks and real peating."""
    keys = list(producer.get("house_casks", []))
    if producer.get("peat") in HOUSE_PEAT_LEVELS:
        keys.append("peated_malt")
    return keys


def label_level(dimension: str, value: int) -> str:
    """Map a 1-5 catalog level to the table's level words."""
    if dimension == "carbonation" and value <= 1:
        return "none"
    return "low" if value <= 2 else "mid" if value == 3 else "high"


def anchored_level(dimension: str, table_level: str | None, stated_level: str) -> str:
    """Notes adjust the table by one step at most: "soft tannins" on a cabernet
    means mid, not low. Bubbles a style fixes are never talked down."""
    if table_level is None:
        return stated_level
    if dimension == "carbonation":
        return stated_level if table_level == "none" else table_level
    order = ["low", "mid", "high"]
    if table_level not in order or stated_level not in order:
        return stated_level
    table_index, stated_index = order.index(table_level), order.index(stated_level)
    return order[max(table_index - 1, min(table_index + 1, stated_index))]


def product_levels(row: dict[str, Any]) -> dict[str, str]:
    """Levels a tasting-profile row states from its own notes, scales, name or ABV."""
    return {
        dimension: label_level(dimension, row[dimension])
        for dimension, source in (row.get("level_sources") or {}).items()
        if dimension in DIMENSIONS and source in PRODUCT_LEVEL_SOURCES
        and isinstance(row.get(dimension), int)
    }


def explicit_dimensions(row: dict[str, Any]) -> set[str]:
    """Dimensions whose stated level is an outright figure, not prose."""
    return {
        dimension for dimension, source in (row.get("level_sources") or {}).items()
        if dimension in DIMENSIONS and source in EXPLICIT_LEVEL_SOURCES
    }


class StyleProfileResolver:
    """Resolve one product to its applicable entries and merged traits."""

    def __init__(self, table: dict[str, Any]):
        self.styles = {entry["key"]: entry for entry in table["styles"]}
        self.grapes = table["wine_grapes"]
        self.regions = table["wine_regions"]
        self.processes = {entry["key"]: entry for entry in table.get("processes", [])}
        self.producers = {entry["key"]: entry for entry in table.get("producers", [])}

    def matching_entries(
        self,
        style_key: str | None,
        name_text: str,
        region: str,
        producer_key: str | None = None,
        process_keys: Iterable[str] = (),
        grape_keys: Iterable[str] = (),
    ) -> list[tuple[str, dict[str, Any]]]:
        matched: list[tuple[str, dict[str, Any]]] = []
        style = self.styles.get(style_key or "")
        if style:
            matched.append(("style", style))
        if style_key in WINE_STYLE_KEYS:
            matched.extend(self._wine_entries(style_key, name_text, region, set(grape_keys)))
        producer = self.producers.get(producer_key or "")
        if producer:
            matched.append(("producer", producer))
        stated = [*house_process_keys(producer or {}), *process_keys]
        matched.extend(
            ("process", self.processes[key])
            for key in dict.fromkeys(stated) if key in self.processes
        )
        return matched

    def _wine_entries(
        self, style_key: str, name_text: str, region: str, grape_keys: set[str]
    ) -> list[tuple[str, dict[str, Any]]]:
        """Grape entries come from the stated grape keys, or else from the name."""
        matched: list[tuple[str, dict[str, Any]]] = []
        color = WINE_COLORS.get(style_key)
        text = name_text.lower()
        for grape in self.grapes:
            if grape_keys:
                stated = grape["key"] in grape_keys
            else:
                stated = any(pattern in text for pattern in grape["match"]["patterns"])
            if stated and color in grape["colors"]:
                matched.append(("grape", grape))
        # Deeper matches (a sub-region label, or an appellation in the product name)
        # are applied after broader ones, so they win on shared dimensions.
        # A grape name such as "melon de bourgogne" must not read as a region.
        region_text = text
        for grape in self.grapes:
            for pattern in grape["match"]["patterns"]:
                region_text = region_text.replace(pattern, " ")
        regions: list[tuple[int, int, dict[str, Any]]] = []
        for order, entry in enumerate(self.regions):
            match = entry["match"]
            if "style_keys" in match:
                if style_key not in match["style_keys"]:
                    continue
            elif color is None or entry["color"] not in (color, "any"):
                continue
            depth = max(
                (
                    label.count(" > ") + 1
                    for label in match.get("region_labels", [])
                    if region == label or region.startswith(label + " > ")
                ),
                default=0,
            )
            # A known region from elsewhere outranks a name hint ("Melon de Bourgogne" from the Loire).
            labels = match.get("region_labels", [])
            region_top = region.split(" > ")[0]
            elsewhere = region and labels and all(label.split(" > ")[0] != region_top for label in labels)
            if not elsewhere and any(pattern in region_text for pattern in match.get("name_patterns", [])):
                depth = max(depth, 2)
            if depth:
                regions.append((depth, order, entry))
        matched.extend(("region", entry) for _, _, entry in sorted(regions, key=lambda r: r[:2]))
        return matched

    def resolve(
        self,
        style_key: str | None,
        name_text: str,
        region: str,
        producer_key: str | None = None,
        process_keys: Iterable[str] = (),
        grape_keys: Iterable[str] = (),
        abv_percent: float | None = None,
        stated_levels: dict[str, str] | None = None,
        explicit_dimensions: Iterable[str] = (),
    ) -> dict[str, Any]:
        grape_keys = list(grape_keys)
        entries = self.matching_entries(
            style_key, name_text, region, producer_key, process_keys, grape_keys
        )
        traits: dict[str, dict[str, Any]] = {}
        grape_claims: dict[str, list[dict[str, Any]]] = {}
        for kind, entry in entries:
            for dimension, claim in entry.get("traits", {}).items():
                resolved = {**claim, "source_key": entry["key"], "source_kind": kind}
                if kind == "grape":
                    grape_claims.setdefault(dimension, []).append(resolved)
                else:
                    traits[dimension] = resolved
        # Grapes sit between style and region: apply after styles, before regions.
        for dimension, claims in grape_claims.items():
            levels = {claim["level"] for claim in claims}
            if len(levels) == 1:
                current = traits.get(dimension)
                if not current or current["source_kind"] == "style":
                    traits[dimension] = claims[0]
            elif traits.get(dimension, {}).get("source_kind") == "style":
                # A blend of grapes that disagree says nothing about this dimension.
                del traits[dimension]
        if abv_percent is not None and abv_percent >= SPIRIT_ABV_FLOOR:
            level = "high" if abv_percent >= HIGH_HEAT_ABV else "mid"
            traits["alcohol_presence"] = {
                "level": level, "basis": "production", "source_key": "abv", "source_kind": "product",
                "reason_ko": f"도수 {abv_percent:g}%라 알코올감이 {'강하게' if level == 'high' else '적당히'} 느껴져요.",
            }
        stated = dict(stated_levels or {})
        still = traits.get("carbonation", {}).get("level") in (None, "none")
        if still and any(pattern in name_text for pattern in SPARKLING_NAME_PATTERNS):
            stated.setdefault("carbonation", "mid")
        explicit = set(explicit_dimensions)
        for dimension, level in stated.items():
            if dimension not in explicit:
                level = anchored_level(dimension, traits.get(dimension, {}).get("level"), level)
            traits[dimension] = {
                "level": level, "basis": "production", "source_key": "product", "source_kind": "product",
                "reason_ko": "이 상품의 설명에 나온 특징이에요.",
            }
        # A specific entry can drop a broader entry's aroma that does not fit it,
        # e.g. pinot noir drops the generic red_wine black_fruit.
        replaced = {key for _, entry in entries for key in entry.get("replaces_aromas", [])}
        # In a blend only the main (first stated) grape with an entry speaks for the aromas;
        # a minor cabernet franc should not add bell pepper.
        matched_grapes = {entry["key"] for kind, entry in entries if kind == "grape"}
        main_grape = next((key for key in grape_keys if key in matched_grapes), None)
        aromas: list[dict[str, Any]] = []
        seen: set[str] = set()
        for kind, entry in reversed(entries):
            if kind == "grape" and main_grape and entry["key"] != main_grape:
                continue
            for aroma in entry.get("aromas", []):
                if aroma["key"] not in seen and aroma["key"] not in replaced:
                    seen.add(aroma["key"])
                    aromas.append({**aroma, "source_key": entry["key"], "source_kind": kind})
        return {
            "entries": [(kind, entry["key"]) for kind, entry in entries],
            "traits": traits,
            "aromas": aromas,
        }
