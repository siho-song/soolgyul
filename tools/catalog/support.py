"""Small deterministic helpers shared by retained catalog maintenance tools."""

from __future__ import annotations

import json
import uuid
from typing import Any, Iterable, Mapping


_CATALOG_NAMESPACE = uuid.UUID("3b1a1384-30e4-5bb2-a4ec-84927373a8be")


def canonical_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )


def jsonl_bytes(rows: Iterable[Mapping[str, Any]]) -> bytes:
    return "".join(canonical_json(row) + "\n" for row in rows).encode("utf-8")


def stable_database_uuid(entity_type: str, external_id: str) -> str:
    if not entity_type or not external_id:
        raise ValueError("entity_type and external_id are required")
    return str(uuid.uuid5(_CATALOG_NAMESPACE, f"{entity_type}:{external_id}"))
