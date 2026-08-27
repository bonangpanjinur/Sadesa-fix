#!/usr/bin/env python3
"""Build ordered SQL bundles for bootstrapping a brand-new Supabase project.

The canonical migration history remains in supabase/migrations. Bundles are
reproducible convenience artifacts and must not be used with an existing
Supabase project that already has migration history.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path('supabase/migrations'))
    parser.add_argument('--output', type=Path, default=Path('supabase/bootstrap'))
    parser.add_argument('--bundles', type=int, default=8)
    args = parser.parse_args()

    files = sorted(args.source.glob('*.sql'))
    if not files:
        raise SystemExit(f'No SQL migrations found in {args.source}')
    if args.bundles < 1 or args.bundles > len(files):
        raise SystemExit('--bundles must be between 1 and the migration count')

    args.output.mkdir(parents=True, exist_ok=True)
    for old in args.output.glob('*.sql'):
        old.unlink()
    manifest: dict[str, object] = {
        'source': str(args.source),
        'migration_count': len(files),
        'bundle_count': args.bundles,
        'bundles': [],
    }

    base, remainder = divmod(len(files), args.bundles)
    start = 0
    for bundle_number in range(1, args.bundles + 1):
        size = base + (1 if bundle_number <= remainder else 0)
        selected = files[start:start + size]
        start += size
        first = selected[0].stem[:14]
        last = selected[-1].stem[:14]
        output = args.output / f'{bundle_number:02d}_{first}_to_{last}.sql'
        chunks = [
            '-- DesaMart bootstrap bundle; generated from supabase/migrations.\n'
            '-- DO NOT apply to an existing project with migration history.\n'
            f'-- Source range: {selected[0].name} .. {selected[-1].name}\n\n'
        ]
        for source in selected:
            chunks.append(f'\n-- ===== BEGIN SOURCE: {source.name} =====\n')
            chunks.append(source.read_text(encoding='utf-8'))
            chunks.append(f'\n-- ===== END SOURCE: {source.name} =====\n')
        content = ''.join(chunks)
        output.write_text(content, encoding='utf-8')
        manifest['bundles'].append({
            'file': output.name,
            'source_files': [source.name for source in selected],
            'sha256': hashlib.sha256(content.encode()).hexdigest(),
            'bytes': len(content.encode()),
        })

    (args.output / 'manifest.json').write_text(
        json.dumps(manifest, indent=2) + '\n', encoding='utf-8'
    )
    print(f'Built {args.bundles} ordered bundles from {len(files)} migrations in {args.output}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
