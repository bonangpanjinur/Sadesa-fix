#!/usr/bin/env python3
"""Refresh bootstrap manifest metadata after bundle changes."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
bundle_dir = root / "supabase/bootstrap"
marker = re.compile(r"^-- ===== BEGIN SOURCE: (.+) =====$", re.MULTILINE)


def bundle_sort_key(path: Path) -> tuple[int, str]:
    match = re.match(r'^(\d+)_', path.name)
    return (int(match.group(1)) if match else 10**9, path.name)


bundles = []
for path in sorted(bundle_dir.glob("[0-9]*_*.sql"), key=bundle_sort_key):
    payload = path.read_bytes()
    text = payload.decode("utf-8")
    sources = marker.findall(text) or [path.name]
    bundles.append({
        "file": path.name,
        "source_files": sources,
        "sha256": hashlib.sha256(payload).hexdigest(),
        "bytes": len(payload),
    })
manifest = {
    "idempotent": True,
    "source": "supabase/bootstrap consolidated ordered bundles",
    "migration_count": sum(len(bundle["source_files"]) for bundle in bundles),
    "bundle_count": len(bundles),
    "bundles": bundles,
}
(bundle_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(f"Updated manifest: {manifest['bundle_count']} bundles, {manifest['migration_count']} source entries")
