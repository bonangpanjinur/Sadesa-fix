#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${POS_BASELINE_OUTPUT_DIR:-${ROOT_DIR}/artifacts/pos-baseline}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT_FILE="${OUTPUT_DIR}/${RUN_ID}.txt"

usage() {
  cat <<'EOF'
Usage: scripts/run-pos-baseline-report.sh [--output PATH]

Required environment:
  SUPABASE_DB_URL       PostgreSQL connection URL for the intended target.

Optional environment:
  POS_BASELINE_OUTPUT_DIR  Directory for timestamped reports.

The report contains counts and totals only. It never prints SUPABASE_DB_URL.
Use a read-only database role when running against staging or production.
EOF
}

while (($#)); do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || { echo "--output requires a path" >&2; exit 2; }
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

: "${SUPABASE_DB_URL:?Set SUPABASE_DB_URL to the intended target database URL}"
command -v psql >/dev/null 2>&1 || { echo "Missing required command: psql" >&2; exit 1; }

mkdir -p "$(dirname "$OUTPUT_FILE")"
cd "$ROOT_DIR"
psql -X -v ON_ERROR_STOP=1 -v VERBOSITY=terse "$SUPABASE_DB_URL" -f scripts/pos-baseline-report.sql >"$OUTPUT_FILE"
printf 'Baseline report written to %s\n' "$OUTPUT_FILE"
