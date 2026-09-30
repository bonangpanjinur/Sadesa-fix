# Regression-Safe Change Policy

Apply these rules to every change in this repository.

## Keep changes isolated
- Make the smallest change that fully addresses the requested behavior. Do not refactor, rename, reformat, or edit unrelated code as part of a bug fix.
- Before editing, identify the affected callers, routes, shared components, hooks, data contracts, permissions, and downstream workflows. Prefer local changes over changes to shared behavior.
- Preserve existing behavior for other user roles, tenants, devices, and service types unless the request explicitly requires changing it.
- Do not change APIs, database schemas, query-cache keys, authorization rules, shared styles, or global configuration casually. Explain the blast radius and add explicit compatibility handling when a shared contract must change.

## Protect data and access boundaries
- Database migrations must be forward-only, idempotent where practical, and backward-compatible with currently deployed application versions.
- For RLS or permission changes, verify both intended access and denied access for each affected role. Preserve least privilege; never broaden access as a shortcut.
- Do not run migrations, data repair, deletion, or other state-changing operations against production without explicit authorization and a verified rollback/recovery plan.
- Never put credentials, service-role keys, or user data into source code, logs, tests, or generated artifacts.

## Prevent regressions
- Add or update a regression test for the reported failure, and test the affected neighboring flows and user roles where practical.
- Run the narrowest relevant tests first, then the applicable lint, type-check, integration tests, migration/bootstrap validation, and production build.
- Review the final diff for unintended files, behavior changes, generated output, and whitespace issues. Do not claim a check passed unless it was run successfully.
- If a check or environment is unavailable, state that clearly and describe any remaining risk rather than assuming success.

## Report delivery clearly
- Summarize the precise behavior changed, the files or contracts affected, and the checks run.
- Call out deployment steps that are not automatic (especially database migrations) and distinguish local/CI validation from production verification.
