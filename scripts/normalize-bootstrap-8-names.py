#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
directory = root / "supabase/bootstrap"
pattern = re.compile(r"(\d{14})")
manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
renames: dict[str, str] = {}
for index, path in enumerate(sorted(directory.glob("[0-9][0-9]_*.sql")), start=1):
    timestamps = pattern.findall(path.name)
    if len(timestamps) < 2:
        raise SystemExit(f"cannot determine range from {path.name}")
    new_name = f"{index:02d}_{timestamps[0]}_to_{timestamps[-1]}.sql"
    new_path = directory / new_name
    path.rename(new_path)
    renames[path.name] = new_name

for bundle in manifest["bundles"]:
    bundle["file"] = renames.get(bundle["file"], bundle["file"])
    path = directory / bundle["file"]
    content = path.read_bytes()
    bundle["sha256"] = hashlib.sha256(content).hexdigest()
    bundle["bytes"] = len(content)
manifest["bundles"] = sorted(manifest["bundles"], key=lambda item: item["file"])
manifest["bundle_count"] = len(manifest["bundles"])
(directory / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print("Normalized eight bootstrap bundle names")
