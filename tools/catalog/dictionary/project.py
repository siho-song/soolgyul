"""The dictionary as the tools read and write it.

The dictionary is a tree in catalog/dictionary, one file per part:

  wine.json, whisky.json, sake.json, korean_traditional.json
      everything about one drink: its kinds and their styles,
      grapes (wine), producers, label words, the places its bottles come
      from (`places`), and its ingredients, processes and maturations
      (`making`), each with what it does to this drink
  senses.json   the words for what is smelled, felt and left after; the
                same for every drink
  evidence.json where values came from, by row (`type:key`); tools only

A place or a making row that two drinks share sits in both files under one
key, with the same names and the same place above it; what it says
(summary, climate, effect) is the drink's own. The term table in the
database holds one row per key, the union of the drink files.

A row holds values and links to other rows by key, never a copy of them.
`load` reads the files into one dict and `save` writes them back in the
dictionary's layout (few line breaks, a row per line where it fits).
"""

from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path
from typing import Iterator

from tools.catalog.enrichment.taxonomy import load_taxonomy_registry

ROOT = Path(__file__).resolve().parents[3]
FOLDER = ROOT / "catalog/dictionary"
DRINKS = ("wine", "whisky", "sake", "korean_traditional")
PARTS = ("senses",)
MAKING_PARTS = ("ingredients", "processes", "maturations")
EVIDENCE = FOLDER / "evidence.json"
# The gauge sheet the app and the server ask from: the gauges of each drink,
# and the name the catalog and the dictionary give each gauge's axis.
GAUGES = ROOT / "catalog/sensory/gauge-definitions.json"
# The words for what is sensed come in three kinds; families group them.
SENSE_TYPES = {"descriptor": "aroma", "texture": "texture", "finish_character": "finish_character"}


def path(part: str) -> Path:
    return FOLDER / f"{part}.json"


def load() -> dict:
    """{"drinks": {wine: …}, "senses": {…}}"""
    return {
        "drinks": {d: json.loads(path(d).read_text(encoding="utf-8")) for d in DRINKS},
        **{p: json.loads(path(p).read_text(encoding="utf-8")) for p in PARTS},
    }


def save(tree: dict) -> None:
    for d in DRINKS:
        path(d).write_text(render(tree["drinks"][d]) + "\n", encoding="utf-8")
    for p in PARTS:
        path(p).write_text(render(tree[p]) + "\n", encoding="utf-8")


def taxonomy() -> dict:
    """The DB term contract (catalog_taxonomy): names, definitions and order
    of every term a bottle can be assigned. It is not the dictionary."""
    return load_taxonomy_registry()


def gauges() -> dict:
    return json.loads(GAUGES.read_text(encoding="utf-8"))


def catalog_names(sheet: dict) -> dict[str, str]:
    """Each gauge axis and the catalog's name for it: tannin is astringency."""
    return {a["axis"]: a["catalog"] for a in sheet["axes"]}


def drink_axes(sheet: dict, drink: str) -> set[str]:
    """The axes a drink is asked, by the catalog's names: those a row's taste speaks of."""
    names = catalog_names(sheet)
    kind = sheet["kinds"][drink]
    return {names[g["axis"]] for g in kind["palate"] + kind["finish"]}


def places(tree: dict, drink: str | None = None) -> Iterator[tuple[dict, str | None]]:
    """Every place of a drink with the key of the place it sits in, the outer
    one first. Without a drink, every place once: a shared one as the first
    drink file (in DRINKS order) holds it."""
    def walk(nodes: list, above: str | None):
        for node in nodes:
            yield node, above
            yield from walk(node.get("places", []), node["key"])
    if drink is not None:
        yield from walk(tree["drinks"][drink].get("places", []), None)
        return
    seen: set[str] = set()
    for d in DRINKS:
        for node, above in walk(tree["drinks"][d].get("places", []), None):
            if node["key"] not in seen:
                seen.add(node["key"])
                yield node, above


def place_drinks(tree: dict) -> dict[str, list[str]]:
    """The drinks whose file holds each place."""
    out: dict[str, list[str]] = {}
    for d in DRINKS:
        for node, _ in places(tree, d):
            out.setdefault(node["key"], []).append(d)
    return out


def senses(tree: dict) -> Iterator[tuple[dict, str, str | None, str | None]]:
    """Every word for what is sensed: (word, its type, its family, the word above it)."""
    def walk(words: list, type_: str, family: str | None, above: str | None):
        for word in words:
            yield word, type_, family, above
            yield from walk(word.get("words", []), type_, family, word["key"])
    for family in tree["senses"]["families"]:
        yield from walk(family["words"], SENSE_TYPES[family["of"]], family["key"], None)
    for type_, words in tree["senses"]["words_of_no_family"].items():
        yield from walk(words, type_, None, None)


def name_tags(tree: dict, part: str, drink: str | None = None) -> Iterator[tuple[dict, dict]]:
    """Every ingredient, process or maturation of a drink with its group.
    Without a drink, every row once, as the first drink file holds it."""
    if drink is not None:
        for group in tree["drinks"][drink]["making"][part]:
            for item in group["items"]:
                yield item, group
        return
    seen: set[str] = set()
    for d in DRINKS:
        for item, group in name_tags(tree, part, d):
            if item["key"] not in seen:
                seen.add(item["key"])
                yield item, group


def making_groups(tree: dict, part: str) -> list[dict]:
    """Every group of a part once, as the first drink file holds it."""
    seen: dict[str, dict] = {}
    for d in DRINKS:
        for group in tree["drinks"][d]["making"][part]:
            seen.setdefault(group["key"], group)
    return list(seen.values())


# ------------------------------------------------------------- place names

_APPELLATION = re.compile(
    r"(?<![A-Za-z])(AVA|AOC|AOP|DOCG|DOCa|DOC|DOQ|DOP|DO|IGT|IGP|GI|UGA|MGA|VQA|WO|DAC|PDO|PGI)(?![A-Za-z])")
_PROVINCE = re.compile(
    r"^(경기도|경기|강원특별자치도|강원도|강원|충청북도|충북|충청남도|충남|전북특별자치도|전라북도|전북|전라남도|전남|"
    r"경상북도|경북|경상남도|경남|제주특별자치도|제주도|서울특별시|부산광역시|인천광역시|대구광역시|대전광역시|광주광역시|"
    r"울산광역시|세종특별자치시)\s+")


def name_key(name: str) -> str:
    """A name as matching sees it: no case, accents or punctuation."""
    name = "".join(c for c in unicodedata.normalize("NFKD", name) if not unicodedata.combining(c))
    return re.sub(r"[\s\-_/.,'’`]+", " ", name.lower()).strip()


def _name_pieces(text: str) -> list[tuple[str, str | None]]:
    """The names a written place may hold, the most specific first, each with
    the Korean province written in front of it, if any:
    'Bourgogne > Beaune' -> Beaune, Bourgogne; '켄터키 (Bardstown, Kentucky)'
    -> Bardstown, Kentucky, 켄터키; '경기도 광주' -> 경기도 광주, then 광주 inside
    경기도. An appellation tag is taken off as well."""
    out: list[tuple[str, str | None]] = []
    for part in reversed([p for p in text.split(">") if p.strip()]):
        inner = re.findall(r"\(([^()]*)\)", part)
        outer = re.sub(r"\([^()]*\)", " ", part)
        for piece in [*inner, outer]:
            for name in re.split(r"[,;/]| 또는 ", piece):
                name = name.strip()
                if not name:
                    continue
                province = _PROVINCE.match(name)
                forms = [(name, None), (_APPELLATION.sub(" ", name), None)]
                if province:
                    forms.append((name[province.end():], province.group(1)))
                for form, within in forms:
                    form = name_key(form)
                    if form and (form, within) not in out:
                        out.append((form, within))
    return out


class PlaceNames:
    """A drink's places by (country, name as matching sees it), and the place
    each sits in."""

    def __init__(self, tree: dict, drink: str):
        self.by_name: dict[tuple[str, str], set[str]] = {}
        # Korean names without 시/군 (충주시 -> 충주), read only after a province.
        self.by_short: dict[tuple[str, str], set[str]] = {}
        self.above: dict[str, str | None] = {}
        country_of: dict[str, str] = {}
        for node, above in places(tree, drink):
            self.above[node["key"]] = above
            country_of[node["key"]] = node["key"] if above is None else country_of[above]
            for name in (node["ko"], node.get("en"), *node.get("aliases", [])):
                if name:
                    self.by_name.setdefault((country_of[node["key"]], name_key(name)), set()).add(node["key"])
                    short = re.sub(r"(?<=[가-힣])[시군]$", "", name.split(" ")[-1])
                    if short != name:
                        self.by_short.setdefault((country_of[node["key"]], name_key(short)), set()).add(node["key"])

    def inside(self, key: str, outer: set[str]) -> bool:
        while key is not None:
            if key in outer:
                return True
            key = self.above.get(key)
        return False


def place_names(tree: dict, drink: str) -> PlaceNames:
    return PlaceNames(tree, drink)


def find_place(names: PlaceNames, country: str, text: str) -> str | None:
    """The key of the place a written place name names, inside the bottle's
    country (a lower-case ISO code), from `place_names` of the bottle's drink.
    A name written after a Korean province finds only a place inside that
    province. A name two places share finds nothing. When the text names
    several places, one inside the other ('Barolo (Piemonte)'), the narrowest
    is found. Places side by side: the one outside the brackets, which is the
    label's ('Pays d'Oc (Corbières)'), else the narrowest place holding them
    all ('Rioja / Navarra' -> Spain)."""
    found: list[str] = []
    for piece, province in _name_pieces(text):
        keys = names.by_name.get((country, piece), set())
        if province:
            outer = names.by_name.get((country, name_key(province)), set())
            keys = {k for k in keys | names.by_short.get((country, piece), set()) if names.inside(k, outer)}
        if len(keys) == 1:
            found.append(next(iter(keys)))
    narrowest = next((k for k in found if all(names.inside(k, {o}) for o in found)), None)
    if narrowest or not found:
        return narrowest
    unbracketed = re.sub(r"\([^()]*\)", " ", text)
    if unbracketed != text and (key := find_place(names, country, unbracketed)):
        return key
    holder = found[0]
    while holder and not all(names.inside(k, {holder}) for k in found):
        holder = names.above.get(holder)
    return holder


def styles(drink: dict) -> Iterator[tuple[dict, dict]]:
    """Every style of a drink with the kind it sits under."""
    for kind in drink["kinds"]:
        for style in kind["styles"]:
            yield style, kind


# ------------------------------------------------------------------ layout

ROW_WIDTH = 170   # a whole row that fits in this is one line
PACK_WIDTH = 150  # short fields of a row share a line up to this
LONG = 60         # a field longer than this has a line of its own


def _scalar(v) -> bool:
    return not isinstance(v, (dict, list))


def _flat(v) -> bool:
    if isinstance(v, list):
        return all(_scalar(x) for x in v)
    if isinstance(v, dict):
        return all(_scalar(x) or (isinstance(x, list) and all(_scalar(y) for y in x)) for x in v.values())
    return True


def render(v, depth: int = 0) -> str:
    """JSON with as few line breaks as stay readable."""
    pad, inner = " " * depth, " " * (depth + 1)
    one = json.dumps(v, ensure_ascii=False)
    if _scalar(v) or v in ([], {}) or isinstance(v, list) and _flat(v):
        return one
    if isinstance(v, list):
        return "[\n" + ",\n".join(inner + render(x, depth + 1) for x in v) + "\n" + pad + "]"
    if _flat(v) and ("key" not in v or len(one) <= ROW_WIDTH):
        return one
    rows, line = [], []
    for k, x in v.items():
        part = f"{json.dumps(k, ensure_ascii=False)}: {render(x, depth + 1)}"
        alone = "\n" in part or len(part) > LONG
        if line and (alone or len(", ".join(line + [part])) > PACK_WIDTH):
            rows.append(", ".join(line))
            line = []
        if alone:
            rows.append(part)
        else:
            line.append(part)
    if line:
        rows.append(", ".join(line))
    return "{\n" + ",\n".join(inner + r for r in rows) + "\n" + pad + "}"
