#!/usr/bin/env python3
"""Validate ordered bootstrap bundles against the canonical migration directory."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> int:
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('supabase/migrations')
    bundle_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path('supabase/bootstrap')
    manifest_path = bundle_dir / 'manifest.json'
    if not manifest_path.exists():
        print(f'ERROR: missing {manifest_path}')
        return 1

    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    expected = [path.name for path in sorted(source.glob('*.sql'))]
    actual = [name for bundle in manifest['bundles'] for name in bundle['source_files']]
    errors: list[str] = []
    if expected != actual:
        if expected[: len(actual)] != actual[: len(expected)]:
            errors.append('bundle source order does not match canonical migration order')
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        duplicates = sorted({name for name in actual if actual.count(name) > 1})
        if missing:
            errors.append(f'missing source migrations: {missing[:5]}')
        if extra:
            errors.append(f'unknown source migrations: {extra[:5]}')
        if duplicates:
            errors.append(f'duplicate source migrations: {duplicates[:5]}')
    for bundle in manifest['bundles']:
        if not (bundle_dir / bundle['file']).exists():
            errors.append(f'missing bundle file: {bundle["file"]}')
    if errors:
        print('Bootstrap bundle validation FAILED')
        for error in errors:
            print(f'- {error}')
        return 1
    print(f'Bootstrap bundle validation OK: {len(expected)} migrations in {len(manifest["bundles"])} ordered bundles')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
