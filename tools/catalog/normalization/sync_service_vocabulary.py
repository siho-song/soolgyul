"""Derive service-vocabulary membership from the catalog tree.

The catalog's ``parent_key`` links say what each sensory name is a kind of, and
``onboarding_selectable`` marks the names a reader is offered. A descriptor
belongs to the nearest selectable name on its own line (itself or an
ancestor). Descriptors with no selectable name above them stay internal tags
(hidden or pending). Group metadata (labels, categories, card labels) is
written by hand; this module derives only membership, source labels, phases
and the hidden set, so the two files cannot disagree.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Mapping

ROOT = Path(__file__).resolve().parents[3]
from tools.catalog.dictionary import project as dictionary
FREQUENCY_PATH = ROOT / "catalog/sensory/aroma-frequency.json"
DERIVED_ORIGIN = "catalog_tree"
AUTO_HIDDEN_REASON = "독자 목록에 없는 이름; 태그로만 보존하고 그 안의 향을 고르면 같은 줄기로 설명에 쓴다"
FOLDED_REASON_MIN_BOTTLES = 500


class VocabularySyncError(ValueError):
    """The vocabulary cannot be derived from the catalog as written."""


def descriptor_rows(catalog: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    return {row["key"]: row for row in catalog["descriptors"]}


def line_of(key: str, rows: Mapping[str, Mapping[str, Any]]) -> list[str]:
    """Self first, then each ancestor up to the root."""
    out: list[str] = []
    current: str | None = key
    while current is not None:
        if current in out:
            raise VocabularySyncError(f"descriptor parent cycle: {current}")
        out.append(current)
        current = rows[current].get("parent_key")
    return out


def reader_name(key: str, rows: Mapping[str, Mapping[str, Any]]) -> str | None:
    """The nearest selectable name on this descriptor's line, or None."""
    for ancestor in line_of(key, rows):
        if rows[ancestor].get("onboarding_selectable") is True:
            return ancestor
    return None


def derive_memberships(catalog: Mapping[str, Any]) -> dict[str, list[str]]:
    """Selectable descriptor -> its members, in catalog order (self first)."""
    rows = descriptor_rows(catalog)
    members: dict[str, list[str]] = {}
    for key, row in rows.items():
        if row.get("onboarding_selectable") is True:
            members[key] = [key]
    for key in rows:
        target = reader_name(key, rows)
        if target is not None and target != key:
            members[target].append(key)
    return members


def _phase_union(keys: list[str], rows: Mapping[str, Mapping[str, Any]]) -> list[str]:
    phases: set[str] = set()
    for key in keys:
        phases.update(rows[key].get("phases", ["finish"]))
    return sorted(phases)


def sync_spec(
    spec: Mapping[str, Any],
    catalog: Mapping[str, Any],
    *,
    hidden_reasons: Mapping[str, str] | None = None,
) -> dict[str, Any]:
    """Return a copy of ``spec`` whose descriptor membership follows the catalog."""
    rows = descriptor_rows(catalog)
    memberships = derive_memberships(catalog)
    result = json.loads(json.dumps(spec))
    groups: list[dict[str, Any]] = result["groups"]
    by_key = {group["key"]: group for group in groups}

    for group in groups:
        if group["domain"] != "descriptor" or group["key"] not in rows:
            continue
        if group["key"] not in memberships:
            raise VocabularySyncError(
                f"reader name is no longer selectable in the catalog; delete or re-mark it: {group['key']}"
            )
    # New reader names need a hand-written place in the list: after their parent name.
    for key, members in memberships.items():
        if key in by_key:
            continue
        parent = next(
            (a for a in line_of(key, rows)[1:] if a in memberships), None,
        )
        if parent is None:
            raise VocabularySyncError(
                f"new root-level reader name needs a hand-written group entry (category): {key}"
            )
        group = {
            "key": key,
            "label_ko": rows[key]["label_ko"],
            "category_key": by_key[parent]["category_key"],
            "domain": "descriptor",
            "source_keys": [],
            "user_source_labels": [],
            "phases": [],
            "decision_origin": DERIVED_ORIGIN,
        }
        groups.insert(groups.index(by_key[parent]) + 1, group)
        by_key[key] = group

    for group in groups:
        key = group["key"]
        if group["domain"] != "descriptor" or key not in memberships:
            continue
        members = memberships[key]
        old = list(group["source_keys"])
        kept = [m for m in old if m in members]
        added = [m for m in members if m not in kept]
        group["source_keys"] = kept + added
        departed = [m for m in old if m not in members]
        labels = list(group["user_source_labels"])
        kept_labels = {rows[m]["label_ko"] for m in kept if m in rows}
        for m in departed:
            label = rows[m]["label_ko"] if m in rows else None
            if label in labels and label not in kept_labels:
                labels.remove(label)
        for m in added:
            if rows[m]["label_ko"] not in labels:
                labels.append(rows[m]["label_ko"])
        group["user_source_labels"] = labels
        group["phases"] = _phase_union(group["source_keys"], rows)

    listed = {m for members in memberships.values() for m in members}
    unlisted = [k for k in rows if k not in listed]
    hidden_blocks: list[dict[str, Any]] = result["hidden"]
    for block in hidden_blocks:
        block["source_keys"] = [k for k in block["source_keys"] if k not in rows or k in unlisted]
    result["hidden"] = [b for b in hidden_blocks if b["source_keys"]]
    result["pending"] = [p for p in result["pending"] if p["key"] not in rows or p["key"] in unlisted]
    covered = {k for b in result["hidden"] for k in b["source_keys"]} | {p["key"] for p in result["pending"]}
    reasons = dict(hidden_reasons or {})
    for key in unlisted:
        if key in covered:
            continue
        reason = reasons.get(key, AUTO_HIDDEN_REASON)
        block = next((b for b in result["hidden"] if b["reason"] == reason), None)
        if block is None:
            block = {"reason": reason, "source_keys": []}
            result["hidden"].append(block)
        block["source_keys"].append(key)
    return result


def check_spec(spec: Mapping[str, Any], catalog: Mapping[str, Any]) -> list[str]:
    """Human-readable differences between the committed spec and the derived one."""
    derived = sync_spec(spec, catalog)
    problems: list[str] = []
    old = {g["key"]: g for g in spec["groups"]}
    new = {g["key"]: g for g in derived["groups"]}
    for key in new.keys() - old.keys():
        problems.append(f"missing group for selectable name: {key}")
    for key, group in new.items():
        if key not in old:
            continue
        for field in ("source_keys", "user_source_labels", "phases"):
            if old[key][field] != group[field]:
                problems.append(f"{key}.{field}: {old[key][field]} -> {group[field]}")
    old_hidden = {k for b in spec["hidden"] for k in b["source_keys"]}
    new_hidden = {k for b in derived["hidden"] for k in b["source_keys"]}
    for key in sorted(old_hidden ^ new_hidden):
        problems.append(f"hidden set differs at: {key}")
    old_pending = {p["key"] for p in spec["pending"]}
    new_pending = {p["key"] for p in derived["pending"]}
    for key in sorted(old_pending ^ new_pending):
        problems.append(f"pending set differs at: {key}")
    return problems


def folded_without_reason(
    spec: Mapping[str, Any], catalog: Mapping[str, Any], frequency: Mapping[str, int],
) -> list[str]:
    """Frequent names folded into a reader name without a written reason."""
    rows = descriptor_rows(catalog)
    reasons = spec.get("folded_reasons", {})
    out: list[str] = []
    for key, row in rows.items():
        if row.get("onboarding_selectable") is True or frequency.get(key, 0) < FOLDED_REASON_MIN_BOTTLES:
            continue
        if reader_name(key, rows) is not None and key not in reasons:
            out.append(key)
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="rewrite the vocabulary from the catalog")
    args = parser.parse_args(argv)
    spec = dictionary.view("service_vocabulary")
    catalog = dictionary.view("catalog")
    if args.write:
        dictionary.save(dictionary.rebuild({"service_vocabulary": sync_spec(spec, catalog)}))
        return 0
    problems = check_spec(spec, catalog)
    for line in problems:
        print(line)
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
