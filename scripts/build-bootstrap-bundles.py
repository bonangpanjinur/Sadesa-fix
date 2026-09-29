#!/usr/bin/env python3
"""Build ordered SQL bundles for bootstrapping a brand-new Supabase project.

The canonical deployment SQL is kept in supabase/bootstrap. The archived
migration files are used only to regenerate and audit these bundles. Rebuilds
refuse to proceed when the archive is incomplete relative to the current
manifest, so an incomplete history cannot erase checked-in deployment SQL.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path('archive/supabase/migrations'))
    parser.add_argument('--output', type=Path, default=Path('supabase/bootstrap'))
    parser.add_argument('--bundles', type=int, default=8)
    parser.add_argument(
        '--separate-final',
        action=argparse.BooleanOptionalAction,
        default=True,
        help='Keep the newest migration in its own final bootstrap SQL file.',
    )
    args = parser.parse_args()

    files = sorted(args.source.glob('*.sql'))
    if not files:
        raise SystemExit(f'No SQL migrations found in {args.source}')
    # Never delete/rebuild checked-in deployment bundles from an incomplete
    # archive. The current bundle manifest is the compatibility floor: if any
    # source entry it references is absent, a rebuild would silently omit SQL
    # that may already exist in deployed environments.
    existing_manifest_path = args.output / 'manifest.json'
    if existing_manifest_path.exists():
        existing_manifest = json.loads(existing_manifest_path.read_text(encoding='utf-8'))
        existing_sources = {
            name
            for bundle in existing_manifest.get('bundles', [])
            for name in bundle.get('source_files', [])
        }
        available_sources = {path.name for path in files}
        missing_sources = sorted(existing_sources - available_sources)
        if missing_sources:
            preview = ', '.join(missing_sources[:5])
            suffix = ' ...' if len(missing_sources) > 5 else ''
            raise SystemExit(
                'Refusing to rebuild bootstrap bundles: the current manifest references '
                f'{len(missing_sources)} source file(s) missing from {args.source} '
                f'({preview}{suffix}). Restore the complete source archive first; '
                'no existing bootstrap files were changed.'
            )
    if args.bundles < 1 or args.bundles > len(files):
        raise SystemExit('--bundles must be between 1 and the migration count')

    args.output.mkdir(parents=True, exist_ok=True)
    for old in args.output.glob('*.sql'):
        old.unlink()
    base, remainder = divmod(len(files), args.bundles)
    selected_groups: list[list[Path]] = []
    start = 0
    for bundle_number in range(1, args.bundles + 1):
        size = base + (1 if bundle_number <= remainder else 0)
        selected_groups.append(files[start:start + size])
        start += size
    if args.separate_final:
        newest = selected_groups[-1].pop()
        selected_groups.append([newest])

    manifest: dict[str, object] = {
        'source': str(args.source),
        'migration_count': len(files),
        'bundle_count': len(selected_groups),
        'bundles': [],
    }

    for bundle_number, selected in enumerate(selected_groups, start=1):
        first = selected[0].stem[:14]
        last = selected[-1].stem[:14]
        output = args.output / f'{bundle_number:02d}_{first}_to_{last}.sql'
        chunks = [
            '-- DesaMart canonical bootstrap bundle; generated from archive source migrations.\n'
            '-- DO NOT apply to an existing project with migration history.\n'
            f'-- Source range: {selected[0].name} .. {selected[-1].name}\n\n'
        ]
        for source in selected:
            chunks.append(f'\n-- ===== BEGIN SOURCE: {source.name} =====\n')
            source_text = source.read_text(encoding='utf-8')
            source_text = '\n'.join(line.rstrip() for line in source_text.splitlines()) + '\n'
            chunks.append(source_text)
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
    print(f'Built {len(selected_groups)} ordered bundles from {len(files)} migrations in {args.output}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
