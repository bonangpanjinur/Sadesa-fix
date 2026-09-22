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
bundles = []
for path in sorted(bundle_dir.glob("[0-9]*_*.sql")):
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
    "source": "supabase/bootstrap consolidated ordered bundles",
    "migration_count": sum(len(bundle["source_files"]) for bundle in bundles),
    "bundle_count": len(bundles),
    "bundles": bundles,
}
(bundle_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(f"Updated manifest: {manifest['bundle_count']} bundles, {manifest['migration_count']} source entries")
