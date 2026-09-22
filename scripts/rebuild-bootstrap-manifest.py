#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
bundle_dir = root / "supabase/bootstrap"
begin = re.compile(r"^-- ===== BEGIN SOURCE: (.+) =====$", re.MULTILINE)
entries = []
for path in sorted(bundle_dir.glob("[0-9][0-9]*_*.sql")):
    text = path.read_text(encoding="utf-8")
    sources = [match.group(1) for match in begin.finditer(text)]
    if not sources:
        sources = [path.name]
    entries.append({
        "file": path.name,
        "source_files": sources,
        "sha256": hashlib.sha256(text.encode()).hexdigest(),
        "bytes": len(text.encode()),
    })
manifest = {
    "source": "supabase/bootstrap embedded source archive",
    "migration_count": sum(len(entry["source_files"]) for entry in entries),
    "bundle_count": len(entries),
    "bundles": entries,
}
(bundle_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(f"Rebuilt manifest: {manifest['migration_count']} sources in {manifest['bundle_count']} bundles")
