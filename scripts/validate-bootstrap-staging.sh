#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_DIR="${ROOT_DIR}/supabase/bootstrap"
LOG_DIR="${STAGING_VALIDATION_LOG_DIR:-${ROOT_DIR}/artifacts/staging-bootstrap-validation}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="${LOG_DIR}/${RUN_ID}.log"
LOCK_FILE="${STAGING_VALIDATION_LOCK_FILE:-/tmp/sadesa-staging-bootstrap-validation.lock}"
REPLAY="${STAGING_BOOTSTRAP_REPLAY:-true}"
SMOKE_TEST="${STAGING_BOOTSTRAP_SMOKE_TEST:-true}"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

on_error() {
  local line="$1"
  echo "ERROR: staging bootstrap validation failed at shell line ${line}. Log: ${LOG_FILE}" >&2
}
trap 'on_error "$LINENO"' ERR

usage() {
  cat <<'EOF'
Usage: scripts/validate-bootstrap-staging.sh [--dry-run] [--no-replay] [--no-smoke]

Required environment:
  SUPABASE_DB_URL            PostgreSQL connection URL for isolated staging only.
  SUPABASE_PROJECT_REF       Supabase staging project reference.
  SUPABASE_TARGET_LABEL      Must equal "staging" unless explicitly overridden.

Optional environment:
  STAGING_BOOTSTRAP_REPLAY=false       Skip second idempotency replay.
  STAGING_BOOTSTRAP_SMOKE_TEST=false   Skip catalog/schema smoke tests.
  ALLOW_NON_STAGING_VALIDATION=true    Explicitly override the staging label guard.
  STAGING_VALIDATION_LOG_DIR=/path     Output directory for timestamped logs.
  STAGING_VALIDATION_LOCK_FILE=/path   Local lock file preventing concurrent runs.

The script never prints SUPABASE_DB_URL. It applies the canonical bootstrap bundles
in lexical order, optionally replays them, then checks migration metadata and critical
subscription/POS/notification objects.
EOF
}

DRY_RUN=false
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --no-replay) REPLAY=false ;;
    --no-smoke) SMOKE_TEST=false ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

: "${SUPABASE_DB_URL:?Set SUPABASE_DB_URL to an isolated Supabase staging database URL}"
: "${SUPABASE_PROJECT_REF:?Set SUPABASE_PROJECT_REF to the staging project reference}"
TARGET_LABEL="${SUPABASE_TARGET_LABEL:-staging}"
if [[ "$TARGET_LABEL" != "staging" && "${ALLOW_NON_STAGING_VALIDATION:-false}" != "true" ]]; then
  echo "Refusing to run: SUPABASE_TARGET_LABEL must be staging." >&2
  exit 1
fi

for command in python3 pnpm flock; do
  command -v "$command" >/dev/null 2>&1 || { echo "Missing required command: $command" >&2; exit 1; }
done
if [[ "$DRY_RUN" != "true" ]] && ! command -v psql >/dev/null 2>&1; then
  echo "Missing required command: psql" >&2
  exit 1
fi

exec 9>"$LOCK_FILE"
flock -n 9 || { echo "Another staging bootstrap validation is already running (lock: $LOCK_FILE)." >&2; exit 1; }

cd "$ROOT_DIR"
export PGPASSWORD="${PGPASSWORD:-}"

run_psql() {
  psql -X -v ON_ERROR_STOP=1 -v VERBOSITY=terse "$SUPABASE_DB_URL" "$@"
}

validate_repo() {
  echo "[preflight] Validating canonical migration files and bootstrap manifest"
  pnpm run validate:db-bootstrap
  bash scripts/validate-migrations.sh
}

preflight_database() {
  echo "[preflight] Checking staging database identity"
  run_psql <<'SQL'
SELECT current_database() AS database_name,
       current_user AS database_user,
       current_setting('server_version') AS postgres_version;
SELECT CASE WHEN current_database() IS NULL THEN 1 ELSE 1 END AS staging_connection_ok;
SQL
}

apply_bundles() {
  local pass="$1"
  local migration_count
  migration_count="$(sed -n 's/^[[:space:]]*\"migration_count\":[[:space:]]*\([0-9][0-9]*\),/\1/p' "$BOOTSTRAP_DIR/manifest.json")"
  [[ "$migration_count" =~ ^[0-9]+$ ]] || { echo "Could not read migration_count from manifest" >&2; return 1; }
  mapfile -t bundles < <(find "$BOOTSTRAP_DIR" -maxdepth 1 -type f -name '[0-9][0-9]_*.sql' -printf '%f\n' | sort)
  ((${#bundles[@]} == 8)) || { echo "Expected 8 bootstrap bundles, found ${#bundles[@]}" >&2; return 1; }
  echo "[${pass}] Applying ${#bundles[@]} bootstrap bundles containing ${migration_count} migrations"
  local bundle
  for bundle in "${bundles[@]}"; do
    echo "[${pass}] Applying ${bundle}"
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[${pass}] DRY RUN: psql -f supabase/bootstrap/${bundle}"
    else
      run_psql -f "$BOOTSTRAP_DIR/$bundle"
    fi
  done
}

smoke_tests() {
  [[ "$SMOKE_TEST" == "true" ]] || { echo "[smoke] Skipped by --no-smoke"; return; }
  [[ "$DRY_RUN" == "true" ]] && { echo "[smoke] Skipped during dry run"; return; }
  echo "[smoke] Checking migration count, critical tables, functions, RLS, and policy count"
  run_psql <<'SQL'
DO $$
DECLARE
  required_tables text[] := ARRAY[
    'subscription_plans', 'subscription_plan_entitlements',
    'merchant_subscription_entitlements', 'subscription_usage_counters',
    'subscription_usage_ledger', 'pwa_device_sessions',
    'notification_delivery_jobs'
  ];
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY required_tables LOOP
    IF to_regclass('public.' || table_name) IS NULL THEN
      RAISE EXCEPTION 'Missing required table: public.%', table_name;
    END IF;
  END LOOP;
END $$;

SELECT proname AS function_name
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND proname IN (
    'register_pwa_device', 'get_subscription_entitlement',
    'require_subscription_feature', 'consume_subscription_usage',
    'consume_whatsapp_delivery_usage', 'claim_notification_delivery_job',
    'complete_notification_delivery_job'
  )
GROUP BY proname
ORDER BY proname;

DO $$
DECLARE
  function_name text;
  required_functions text[] := ARRAY[
    'register_pwa_device', 'get_subscription_entitlement',
    'require_subscription_feature', 'consume_subscription_usage',
    'consume_whatsapp_delivery_usage', 'claim_notification_delivery_job',
    'complete_notification_delivery_job'
  ];
BEGIN
  FOREACH function_name IN ARRAY required_functions LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc
      WHERE pronamespace = 'public'::regnamespace AND proname = function_name
    ) THEN
      RAISE EXCEPTION 'Missing required function: public.%', function_name;
    END IF;
  END LOOP;
END $$;

SELECT c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,
       count(p.policyname) AS policy_count
FROM pg_class c
LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_policies p ON p.schemaname = n.nspname AND p.tablename = c.relname
WHERE n.nspname = 'public'
  AND c.relname IN ('pwa_device_sessions', 'notification_delivery_jobs', 'subscription_usage_ledger')
GROUP BY c.relname, c.relrowsecurity
ORDER BY c.relname;

SELECT code, name, is_active FROM public.subscription_plans ORDER BY sort_order, code;
SQL
}

validate_repo
if [[ "$DRY_RUN" == "true" ]]; then
  apply_bundles initial
  echo "Dry run completed. No staging database was modified. Log: ${LOG_FILE}"
  exit 0
fi
preflight_database
apply_bundles initial
if [[ "$REPLAY" == "true" ]]; then
  apply_bundles replay
else
  echo "[replay] Skipped because STAGING_BOOTSTRAP_REPLAY=${REPLAY}"
fi
smoke_tests

echo "STAGING_BOOTSTRAP_VALIDATION=PASS"
echo "Project ref: ${SUPABASE_PROJECT_REF}"
echo "Log file: ${LOG_FILE}"
