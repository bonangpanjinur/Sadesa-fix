#!/usr/bin/env bash
set -Eeuo pipefail

# Safe staging-only drill. This script never writes to the source database.
: "${BACKUP_RESTORE_DB_URL:?Set BACKUP_RESTORE_DB_URL to a disposable staging database URL}"
TARGET_LABEL="${BACKUP_RESTORE_TARGET_LABEL:-staging}"
if [[ "$TARGET_LABEL" =~ (prod|production|live) ]]; then
  echo "Refusing backup drill for production-like target: $TARGET_LABEL" >&2
  exit 2
fi
command -v pg_dump >/dev/null || { echo 'pg_dump is required' >&2; exit 127; }
command -v sha256sum >/dev/null || { echo 'sha256sum is required' >&2; exit 127; }

output_dir="${BACKUP_DRILL_OUTPUT_DIR:-./artifacts/backup-drill-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$output_dir"
chmod 700 "$output_dir"
dump_file="$output_dir/staging-schema.dump"
manifest="$output_dir/manifest.txt"

pg_dump "$BACKUP_RESTORE_DB_URL" --format=custom --schema-only --no-owner --no-privileges --file="$dump_file"
sha256sum "$dump_file" > "$manifest"

for required in orders pos_sales pos_sale_items pos_stock pos_stock_mutations payment_reconciliation_records; do
  if ! pg_restore --list "$dump_file" 2>/dev/null | grep -q "TABLE.*public $required "; then
    echo "Required table missing from snapshot: $required" >&2
    exit 1
  fi
done

cat <<EOF
Backup restore drill snapshot completed safely.
Target: $TARGET_LABEL
Snapshot: $dump_file
Manifest: $manifest
Next manual step: restore this disposable snapshot into a fresh staging database and execute the application smoke tests plus RLS integration suite.
EOF
