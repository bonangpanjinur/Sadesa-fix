#!/usr/bin/env bash
set -euo pipefail

# Load a local, untracked fixture file when provided.
if [[ -n "${RLS_ENV_FILE:-}" ]]; then
  if [[ ! -f "$RLS_ENV_FILE" ]]; then
    echo "Fixture file not found: $RLS_ENV_FILE" >&2
    exit 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "$RLS_ENV_FILE"
  set +a
fi

: "${RUN_RLS_INTEGRATION:=true}"
: "${SUPABASE_TEST_URL:?Set SUPABASE_TEST_URL to a staging Supabase URL}"
: "${SUPABASE_TEST_ANON_KEY:?Set SUPABASE_TEST_ANON_KEY to a staging publishable/anon key}"

if [[ "${SUPABASE_TEST_URL}" != *staging* && "${ALLOW_NON_STAGING_RLS_TARGET:-}" != "true" ]]; then
  echo "Refusing to run: SUPABASE_TEST_URL does not look like a staging target." >&2
  echo "Set ALLOW_NON_STAGING_RLS_TARGET=true only for an explicitly isolated test project." >&2
  exit 1
fi

required_vars=(
  RLS_TEST_BUYER_EMAIL RLS_TEST_BUYER_PASSWORD
  RLS_TEST_MERCHANT_EMAIL RLS_TEST_MERCHANT_PASSWORD
  RLS_TEST_MERCHANT_OWN_ID RLS_TEST_MERCHANT_OTHER_ID
  RLS_TEST_BUYER_OWN_ORDER_ID RLS_TEST_BUYER_OTHER_ORDER_ID
  RLS_TEST_POS_TENANT_OWN_ID RLS_TEST_POS_TENANT_OTHER_ID
  RLS_TEST_POS_OUTLET_OWN_ID RLS_TEST_POS_OUTLET_OTHER_ID
  RLS_TEST_POS_PRODUCT_OTHER_ID
  RLS_TEST_POS_STAFF_EMAIL RLS_TEST_POS_STAFF_PASSWORD
  RLS_TEST_POS_OUTLET_ASSIGNED_ID RLS_TEST_POS_OUTLET_UNASSIGNED_ID
)
for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing fixture variable: $name" >&2
    exit 1
  fi
done

export RUN_RLS_INTEGRATION=true
export CI=true
exec pnpm exec vitest run --config vitest.integration.config.ts
