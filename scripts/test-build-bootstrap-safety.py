#!/usr/bin/env python3
"""Regression test: an incomplete source archive must never erase bootstrap SQL."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    builder = repo / 'scripts' / 'build-bootstrap-bundles.py'
    with tempfile.TemporaryDirectory(prefix='bootstrap-safety-') as temp_dir:
        root = Path(temp_dir)
        source = root / 'archive'
        output = root / 'bootstrap'
        source.mkdir()
        output.mkdir()
        (source / '20260929160000_present.sql').write_text('SELECT 1;\n', encoding='utf-8')
        existing_bundle = output / '01_existing.sql'
        existing_bundle.write_text('-- must remain intact\n', encoding='utf-8')
        manifest = {
            'bundles': [{
                'file': existing_bundle.name,
                'source_files': [
                    '20260929160000_present.sql',
                    '20260929150000_missing_from_archive.sql',
                ],
            }],
        }
        (output / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')

        result = subprocess.run(
            [sys.executable, str(builder), '--source', str(source), '--output', str(output), '--bundles', '1'],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            raise SystemExit('Expected incomplete archive rebuild to be rejected')
        if 'Refusing to rebuild bootstrap bundles' not in result.stderr:
            raise SystemExit(f'Unexpected failure: {result.stderr}')
        if existing_bundle.read_text(encoding='utf-8') != '-- must remain intact\n':
            raise SystemExit('Existing bootstrap bundle changed despite incomplete archive')
        print('Bootstrap safety test passed: incomplete archive was refused without modifying existing SQL.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
