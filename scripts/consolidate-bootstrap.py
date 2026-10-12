#!/usr/bin/env python3
"""Consolidate embedded bootstrap sources and active migrations into bootstrap."""
from __future__ import annotations

import hashlib
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT / "supabase/bootstrap"
ARCHIVE = ROOT / "archive/supabase/migrations"
ACTIVE = ROOT / "supabase/migrations"
MANIFEST_PATH = BOOTSTRAP / "manifest.json"
BEGIN = re.compile(r"^-- ===== BEGIN SOURCE: (.+) =====$", re.MULTILINE)
END_TEMPLATE = "-- ===== END SOURCE: {name} ====="


def normalized(text: str) -> str:
    return "\n".join(line.rstrip() for line in text.splitlines()).strip() + "\n"


def embedded_sources() -> dict[str, str]:
    sources: dict[str, str] = {}
    bundle_paths = [
        path for path in BOOTSTRAP.glob("*_*.sql")
        if path.name.split("_", 1)[0].isdigit()
    ]
    for bundle in sorted(bundle_paths):
        text = bundle.read_text(encoding="utf-8")
        matches = list(BEGIN.finditer(text))
        for match in matches:
            name = match.group(1)
            start = match.end() + 1
            marker = END_TEMPLATE.format(name=name)
            end = text.find(marker, start)
            if end < 0:
                raise SystemExit(f"missing end marker for {name} in {bundle.name}")
            body = normalized(text[start:end])
            previous = sources.get(name)
            if previous is not None and previous != body:
                raise SystemExit(f"conflicting embedded source: {name}")
            sources[name] = body
    return sources


def bundle_for_source(source_name: str, body: str, number: int) -> tuple[str, dict[str, object]]:
    stamp = source_name[:14]
    bundle_name = f"{number:02d}_{stamp}_to_{stamp}.sql"
    content = (
        "-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.\n"
        "-- DO NOT apply to an existing project with migration history.\n"
        f"-- Source range: {source_name} .. {source_name}\n\n"
        f"-- ===== BEGIN SOURCE: {source_name} =====\n"
        f"{body}\n"
        f"-- ===== END SOURCE: {source_name} =====\n"
    )
    (BOOTSTRAP / bundle_name).write_text(content, encoding="utf-8")
    return bundle_name, {
        "file": bundle_name,
        "source_files": [source_name],
        "sha256": hashlib.sha256(content.encode()).hexdigest(),
        "bytes": len(content.encode()),
    }


def main() -> int:
    BOOTSTRAP.mkdir(parents=True, exist_ok=True)
    ARCHIVE.mkdir(parents=True, exist_ok=True)
    embedded = embedded_sources()
    archive_sources = {p.name: normalized(p.read_text(encoding="utf-8")) for p in ARCHIVE.glob("*.sql")}

    # Restore every source named by existing bundle markers into the audit archive.
    for name, body in sorted(embedded.items()):
        path = ARCHIVE / name
        # The bundle is the deployment canonical source. Older archive copies
        # can legitimately lag behind a later fix already folded into a bundle.
        if not path.exists() or normalized(path.read_text(encoding="utf-8")) != body:
            path.write_text(body, encoding="utf-8")
        archive_sources[name] = body

    # Add only active migrations whose SQL is not already embedded in a bundle.
    active = sorted(ACTIVE.glob("*.sql"), key=lambda p: p.name)
    force_pending = False
    if not active:
        # Recovery path after a partial consolidation: the active files have
        # already been copied to the audit archive, so use their known commit
        # range as the pending source set.
        pending_names = {
            "20260918233000_merchant_paid_ads.sql",
            "20260919123000_active_merchant_category.sql",
            "20260920220000_merchant_free_trial_quota.sql",
            "20260920223000_free_quota_expiry_notifications.sql",
            "20260920230000_seed_free_tier_quota_setting.sql",
            "20260920240000_merchant_categories_and_schedule.sql",
            "20260921170000_order_notification_sounds.sql",
            "20260921193000_admin_direct_chat.sql",
            "20260921201500_admin_chat_notification_link.sql",
            "20260922100000_product_toppings.sql",
            "20260922160000_remove_cod_service_fee.sql",
            "20260922163000_repair_marketplace_checkout_overload.sql",
        }
        active = [ARCHIVE / name for name in sorted(pending_names)]
        force_pending = True
    represented = set(embedded.values()) | set(archive_sources.values())
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    numbered_bundles = [
        path for path in BOOTSTRAP.glob("*_*.sql")
        if path.name.split("_", 1)[0].isdigit()
    ]
    next_number = max(int(p.name.split("_", 1)[0]) for p in numbered_bundles) + 1
    added: list[dict[str, object]] = []
    for path in active:
        body = normalized(path.read_text(encoding="utf-8"))
        # Existing bundles may carry the same migration under a consolidated
        # numbered filename; its original source marker still carries the
        # canonical 14-digit timestamp.
        if any(name.startswith(path.name[:14]) for name in embedded):
            continue
        if not force_pending and body in represented:
            continue
        archive_path = ARCHIVE / path.name
        if archive_path.exists() and normalized(archive_path.read_text(encoding="utf-8")) != body:
            raise SystemExit(f"active/archive content differs: {path.name}")
        archive_path.write_text(body, encoding="utf-8")
        archive_sources[path.name] = body
        bundle_name, entry = bundle_for_source(path.name, body, next_number)
        next_number += 1
        manifest["bundles"].append(entry)
        added.append(entry)
        represented.add(body)

    manifest["source"] = "archive/supabase/migrations"
    manifest["migration_count"] = len(archive_sources)
    manifest["bundle_count"] = len(manifest["bundles"])
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    for path in active:
        path.unlink()
    try:
        ACTIVE.rmdir()
    except OSError:
        pass
    print(f"Embedded sources restored: {len(embedded)}")
    print(f"New bootstrap bundles added: {len(added)}")
    print(f"Archive sources: {len(archive_sources)}")
    print("Active supabase/migrations files moved to bootstrap/archive; duplicate SQL was not emitted.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
