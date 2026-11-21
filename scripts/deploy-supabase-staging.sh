#!/usr/bin/env bash
set -euo pipefail

: "${SUPABASE_PROJECT_REF:?Set SUPABASE_PROJECT_REF to the staging project ref}"
: "${SUPABASE_DB_URL:?Set SUPABASE_DB_URL to the staging database connection string}"
TARGET_LABEL="${SUPABASE_TARGET_LABEL:-staging}"
if [[ "${ALLOW_NON_STAGING_DEPLOY:-false}" != "true" && "$TARGET_LABEL" != "staging" ]]; then
  echo "Refusing deployment: SUPABASE_TARGET_LABEL must be staging" >&2
  exit 1
fi

if ! command -v supabase >/dev/null 2>&1; then
  echo "Supabase CLI is required. Install it in the deployment environment, then rerun this script." >&2
  exit 1
fi

./scripts/validate-migrations.sh
python3 scripts/validate-bootstrap-bundles.py

if ! command -v psql >/dev/null 2>&1; then
  echo "PostgreSQL client (psql) is required to apply bootstrap bundles." >&2
  exit 1
fi

echo "Linking Supabase project $SUPABASE_PROJECT_REF ($TARGET_LABEL)"
supabase link --project-ref "$SUPABASE_PROJECT_REF"
echo "Applying canonical bootstrap bundles"
mapfile -t bundles < <(find supabase/bootstrap -maxdepth 1 -type f -name '[0-9]*_*.sql' -printf '%f\n' | sort -V)
for bundle in "${bundles[@]}"; do
  echo "Applying supabase/bootstrap/$bundle"
  psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f "supabase/bootstrap/$bundle"
done

if [[ "${DEPLOY_NOTIFICATION_WORKER:-true}" == "true" ]]; then
  echo "Deploying notification worker"
  supabase functions deploy process-notification-queue
fi

echo "Staging database and selected Edge Functions deployed successfully."
