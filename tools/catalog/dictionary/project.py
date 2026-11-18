"""The dictionary as the tools read and write it.

The dictionary is a tree in catalog/dictionary, one file per part:

  wine.json, whisky.json, sake.json, korean_traditional.json
      one drink each: its taste axes, kinds and their styles, grapes (wine),
      producers, label words, and how ingredients, processes and maturations
      move its taste
  places.json   countries and the places inside them
  making.json   the name tags of ingredients, processes and maturations
  senses.json   the words for what is smelled, felt and left after
  evidence.json where values came from, by row (`type:key`); tools only

A row holds values and links to other rows by key, never a copy of them.
`load` reads the files into one dict and `save` writes them back in the
dictionary's layout (few line breaks, a row per line where it fits).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Iterator

ROOT = Path(__file__).resolve().parents[3]
FOLDER = ROOT / "catalog/dictionary"
DRINKS = ("wine", "whisky", "sake", "korean_traditional")
PARTS = ("places", "making", "senses")
EVIDENCE = FOLDER / "evidence.json"
# The DB term contract (catalog_taxonomy): names, definitions and order of
# every term a bottle can be assigned. It is not the dictionary.
TAXONOMY = ROOT / "config/catalog/enrichment_taxonomy_v2.json"
# The words for what is sensed come in three kinds; families group them.
SENSE_TYPES = {"descriptor": "aroma", "texture": "texture", "finish_character": "finish_character"}


def path(part: str) -> Path:
    return FOLDER / f"{part}.json"


def load() -> dict:
    """{"drinks": {wine: …}, "places": […], "making": {…}, "senses": {…}}"""
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
    return json.loads(TAXONOMY.read_text(encoding="utf-8"))


def places(tree: dict) -> Iterator[tuple[dict, str | None]]:
    """Every place with the key of the place it sits in, the outer one first."""
    def walk(nodes: list, above: str | None):
        for node in nodes:
            yield node, above
            yield from walk(node.get("places", []), node["key"])
    yield from walk(tree["places"], None)


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


def name_tags(tree: dict, part: str) -> Iterator[tuple[dict, dict]]:
    """Every ingredient, process or maturation with its group."""
    for group in tree["making"][part]:
        for item in group["items"]:
            yield item, group


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
