#!/usr/bin/env bash
set -euo pipefail

if [[ "${SUPABASE_TARGET_LABEL:-staging}" != "staging" ]]; then
  echo "Refusing simulation: set SUPABASE_TARGET_LABEL=staging" >&2
  exit 1
fi

./scripts/validate-migrations.sh
python3 scripts/audit-rls-static.py
npx tsc --noEmit
npm run lint
npm test
npm run test:integration

if command -v supabase >/dev/null 2>&1 && [[ -n "${SUPABASE_PROJECT_REF:-}" ]]; then
  echo "Supabase CLI detected; use deploy-supabase-staging.sh for the authenticated database apply."
else
  echo "SIMULATION_ONLY: Supabase CLI/project ref unavailable; database apply and server-side migration conflict detection remain pending."
fi
