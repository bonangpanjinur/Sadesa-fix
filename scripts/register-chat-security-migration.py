from __future__ import annotations

import hashlib
import json
from pathlib import Path

bundle_dir = Path('supabase/bootstrap')
migration_names = [
    '34_20260909110000_chat_security_pair_isolation.sql',
    '35_20260909120000_chat_message_retention.sql',
]
manifest_path = bundle_dir / 'manifest.json'
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))

for migration_name in migration_names:
    migration = bundle_dir / migration_name
    if not migration.exists():
        raise SystemExit(f'missing migration: {migration}')

    content = migration.read_bytes()
    entry = {
        'file': migration_name,
        'source_files': [migration_name],
        'sha256': hashlib.sha256(content).hexdigest(),
        'bytes': len(content),
    }
    existing = next(
        (bundle for bundle in manifest['bundles'] if migration_name in bundle.get('source_files', [])),
        None,
    )
    if existing is None:
        manifest['bundles'].append(entry)
    else:
        existing.update(entry)
manifest['bundle_count'] = len(manifest['bundles'])
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
print(f'registered {len(migration_names)} chat migrations')
