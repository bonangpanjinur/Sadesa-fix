from __future__ import annotations
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
manifest_path = root / 'supabase/bootstrap/manifest.json'
file_name = '37_20260909140000_chat_retention_operations.sql'
path = root / 'supabase/bootstrap' / file_name
manifest = json.loads(manifest_path.read_text())
if not any(bundle['file'] == file_name for bundle in manifest['bundles']):
    manifest['bundles'].append({
        'file': file_name,
        'source_files': [file_name],
        'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'bytes': path.stat().st_size,
    })
manifest['bundle_count'] = len(manifest['bundles'])
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
print(file_name, manifest['bundles'][-1]['bytes'], manifest['bundles'][-1]['sha256'])
