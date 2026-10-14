#!/usr/bin/env bash
set -euo pipefail

# Single local/CI command for the repository's no-regression rule.
# Run from the repository root: pnpm validate:change-safety

step() {
  printf '\n\n==== %s ====\n' "$1"
  shift
  "$@"
}

step 'Package manager alignment' pnpm run validate:package-manager
step 'Migration filename and destructive SQL validation' pnpm run validate:migrations
step 'Bootstrap manifest and checksum validation' pnpm run validate:db-bootstrap
step 'Static RLS audit' pnpm run audit:rls
step 'TypeScript' pnpm exec tsc --noEmit
step 'Lint' pnpm run lint
step 'Unit and component tests' pnpm test -- --run
step 'Production build' pnpm run build

printf '\nCHANGE_SAFETY_GATE=PASS\n'
