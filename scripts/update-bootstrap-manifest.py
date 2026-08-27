from __future__ import annotations

import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
old = root / "supabase/bootstrap/08_20260825180000_to_20260829130000.sql"
new = root / "supabase/bootstrap/08_20260825180000_to_20260829140000.sql"
if old.exists() and not new.exists():
    old.rename(new)
manifest_path = root / "supabase/bootstrap/manifest.json"
manifest = json.loads(manifest_path.read_text())
for bundle in manifest["bundles"]:
    if bundle["file"] == old.name:
        bundle["file"] = new.name
        if "20260829140000_subscription_runtime_enforcement.sql" not in bundle["source_files"]:
            bundle["source_files"].append("20260829140000_subscription_runtime_enforcement.sql")
        payload = new.read_bytes()
        bundle["sha256"] = hashlib.sha256(payload).hexdigest()
        bundle["bytes"] = len(payload)
manifest["migration_count"] = len(list((root / "archive/supabase/migrations").glob("*.sql")))
manifest["bundle_count"] = len(manifest["bundles"])
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
print(new.name, manifest["bundles"][-1]["bytes"], manifest["bundles"][-1]["sha256"])
