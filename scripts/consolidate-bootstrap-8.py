#!/usr/bin/env python3
"""Consolidate the canonical bootstrap SQL into eight ordered bundles."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT / "supabase/bootstrap"
SOURCE_MARKER = re.compile(r"^-- ===== BEGIN SOURCE: (.+) =====$", re.MULTILINE)


def numeric_order(path: Path) -> tuple[int, str]:
    prefix = path.name.split("_", 1)[0]
    return int(prefix), path.name


def source_names(path: Path, text: str) -> list[str]:
    names = SOURCE_MARKER.findall(text)
    return names or [path.name]


def main() -> int:
    files = sorted(BOOTSTRAP.glob("[0-9]*_*.sql"), key=numeric_order)
    if len(files) < 8:
        raise SystemExit(f"expected at least 8 bootstrap bundles, found {len(files)}")

    chunks: list[list[Path]] = [[] for _ in range(8)]
    base, remainder = divmod(len(files), 8)
    cursor = 0
    for index in range(8):
        size = base + (1 if index < remainder else 0)
        chunks[index] = files[cursor:cursor + size]
        cursor += size

    contents = {path: path.read_text(encoding="utf-8") for path in files}
    for path in files:
        path.unlink()

    manifest_bundles: list[dict[str, object]] = []
    for index, group in enumerate(chunks, start=1):
        first = group[0].stem.split("_", 1)[1]
        last = group[-1].stem.split("_", 1)[1]
        output = BOOTSTRAP / f"{index:02d}_{first}_to_{last}.sql"
        parts = [
            "-- DesaMart canonical bootstrap bundle; consolidated from ordered bundles.\n",
            "-- DO NOT apply to an existing project with migration history.\n",
            f"-- Consolidated range: {group[0].name} .. {group[-1].name}\n\n",
        ]
        sources: list[str] = []
        for original in group:
            text = contents[original]
            parts.append(f"-- ===== BEGIN BUNDLE: {original.name} =====\n")
            parts.append(text.rstrip() + "\n")
            parts.append(f"-- ===== END BUNDLE: {original.name} =====\n\n")
            sources.extend(source_names(original, text))
        content = "".join(parts)
        output.write_text(content, encoding="utf-8")
        manifest_bundles.append({
            "file": output.name,
            "source_files": sources,
            "sha256": hashlib.sha256(content.encode()).hexdigest(),
            "bytes": len(content.encode()),
        })

    manifest = {
        "source": "supabase/bootstrap consolidated ordered bundles",
        "migration_count": sum(len(bundle["source_files"]) for bundle in manifest_bundles),
        "bundle_count": len(manifest_bundles),
        "bundles": manifest_bundles,
    }
    (BOOTSTRAP / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Consolidated {len(files)} bundles into {len(manifest_bundles)} ordered bundles")
    print(f"Manifest sources: {manifest['migration_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
