#!/usr/bin/env bash
set -euo pipefail

# Optional file for local/staging verification. Never print its values.
if [[ -n "${PRODUCTION_ENV_FILE:-}" ]]; then
  if [[ ! -f "$PRODUCTION_ENV_FILE" ]]; then
    echo "Environment file not found: $PRODUCTION_ENV_FILE" >&2
    exit 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "$PRODUCTION_ENV_FILE"
  set +a
fi

required_public=(VITE_SUPABASE_URL VITE_SUPABASE_PUBLISHABLE_KEY VITE_SUPABASE_PROJECT_ID)
server_only=(SUPABASE_SERVICE_ROLE_KEY XENDIT_SECRET_KEY XENDIT_CALLBACK_TOKEN WHATSAPP_ACCESS_TOKEN WORKER_CRON_SECRET DATABASE_URL)
failed=0

check_set() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then
    echo "SET    $name"
  else
    echo "MISSING $name"
    failed=1
  fi
}

for name in "${required_public[@]}"; do check_set "$name"; done

for name in "${server_only[@]}"; do
  if [[ -n "${!name:-}" ]]; then
    echo "SET    $name (server-only; value hidden)"
  else
    echo "INFO   $name not set in this shell (verify in the owning Edge Function/secret manager)"
  fi
done

for name in "${server_only[@]}"; do
  if [[ -n "${!name:-}" && "$name" == VITE_* ]]; then
    echo "ERROR server-only secret is exposed through VITE_: $name" >&2
    failed=1
  fi
done

if [[ -n "${VITE_SUPABASE_URL:-}" && ! "$VITE_SUPABASE_URL" =~ ^https://[^[:space:]]+\.supabase\.co/?$ ]]; then
  echo "ERROR VITE_SUPABASE_URL must be an HTTPS Supabase project URL" >&2
  failed=1
fi

if (( failed )); then
  echo "Production environment check: FAIL" >&2
  exit 1
fi

echo "Production public environment check: PASS"
