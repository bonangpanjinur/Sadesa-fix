#!/usr/bin/env bash
set -euo pipefail

: "${SUPABASE_PROJECT_REF:?Set SUPABASE_PROJECT_REF to the staging project ref}"
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

echo "Linking Supabase project $SUPABASE_PROJECT_REF ($TARGET_LABEL)"
supabase link --project-ref "$SUPABASE_PROJECT_REF"
echo "Applying migrations"
supabase db push

if [[ "${DEPLOY_NOTIFICATION_WORKER:-true}" == "true" ]]; then
  echo "Deploying notification worker"
  supabase functions deploy process-notification-queue
fi

echo "Staging database and selected Edge Functions deployed successfully."
