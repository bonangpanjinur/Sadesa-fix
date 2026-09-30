# Regression-Safe Change Policy

Apply these rules to every change in this repository.

## Keep changes isolated
- Make the smallest change that fully addresses the requested behavior. Do not refactor, rename, reformat, or edit unrelated code as part of a bug fix.
- Before editing, identify affected callers, routes, shared components, hooks, data contracts, permissions, and downstream workflows. Prefer local changes over shared behavior changes.
- Preserve existing behavior for other user roles, tenants, devices, and service types unless the request explicitly requires changing it.
- Do not casually change APIs, database schemas, query-cache keys, authorization rules, shared styles, or global configuration. Explain the blast radius and add compatibility handling when a shared contract must change.

## Learn the existing contract first
- Before changing an established flow, read `.agents/memory/MEMORY.md` and the relevant linked note(s). Treat documented contracts as constraints, not optional implementation suggestions.
- Trace a feature end to end—UI, hooks/services, RPC/API, database policy or trigger, and tests—before deciding where to fix it. A UI workaround is not a complete fix when the underlying failure is in the backend.
- Preserve distinct order types and state machines. Do not assume marketplace delivery, table-QR orders, POS sales, and Ojek rides have interchangeable statuses, permissions, or lifecycle behavior.
- Model state transitions explicitly. A pending/assigned offer is not acceptance: do not expose buyer-facing courier identity, chat, or live tracking until the documented acceptance state allows it.
- Keep shared values on their source of truth: use admin-managed categories rather than a second hard-coded list; preserve identifiers/slugs and normalize PostgreSQL `TIME` values for browser controls as documented.

## Protect data, money, stock, and access
- Treat balances, deposits/withdrawals, earnings, commission, COD, courier approval/status, trust/eligibility, bank details, order totals, and stock as server-authoritative data. Use validated server-side RPCs or transactions; do not trust client-calculated values or broad row updates.
- For money, inventory, checkout, offline replay, and retryable mutations, check concurrency, duplicate submission, idempotency, and rollback/release behavior. Test retries and competing requests where practical.
- Keep anonymous/public flows narrowly scoped. For table-QR ordering, preserve the dedicated RPC boundary and server-side checks for tenant, outlet, table, product, price, and stock; do not replace it with direct anonymous table access or a retired POS bridge.
- For RLS or permission changes, verify intended access and denied access for every affected role, including cross-tenant and unrelated-user cases. Preserve least privilege; never broaden access as a shortcut.
- Database migrations must be forward-only, idempotent where practical, and backward-compatible with currently deployed application versions. Do not run migrations, data repair, deletion, or other state-changing operations against production without explicit authorization and a verified rollback/recovery plan.
- When changing ratings or courier profile summaries, preserve the documented aggregation across both completed marketplace deliveries and completed Ojek rides.
- Never put credentials, service-role keys, or user data into source code, logs, tests, or generated artifacts.

## Preserve offline, print, and PWA behavior
- Keep offline mutations safe to replay and idempotent. For POS queue sync, drive synchronization from the committed online state/effect rather than relying only on the browser `online` event.
- Preserve the single injected Workbox service worker as the owner of both caching and push behavior. Validate the production-built worker and manifest for PWA changes; development mode alone is insufficient.
- Keep POS receipt/reprint behavior on its shared persisted, idempotent print contract, including explicit printed-versus-queued outcomes. Do not merge that contract with marketplace A4 invoices without a product requirement.

## Keep database artifacts in sync
- Identify the canonical migration source before editing SQL. This repository has archived migration sources and ordered bootstrap bundles; some manual bootstrap bundles may not exist in the archive. Do not assume one directory is a complete substitute for the other.
- When changing bootstrap bundles, update the ordered manifest and its integrity metadata using the repository's supported workflow, then run the bootstrap validator. Review the generated diff for unrelated bundle changes.
- A successful PostgREST/API smoke test does not prove a SQL bundle was applied. Separate local/CI validation, staging database verification, and production deployment evidence.
- Do not replay bootstrap bundles against an existing production database as a shortcut; use the authorized migration/deployment process for that environment.

## Prevent regressions
- Add or update a regression test for the reported failure. Cover the affected neighboring flows, user roles, and important loading/error/empty/success states where applicable; do not make a backend error look like valid empty data.
- Run the narrowest relevant tests first, then applicable lint, type-check, integration tests, migration/bootstrap validation, and production build. Check the repository's pinned runtime/package-manager requirements before diagnosing tool failures.
- Review the final diff for unintended files, behavior changes, generated output, lockfile drift, and whitespace issues. Do not claim a check passed unless it was run successfully.
- If a check or environment is unavailable, state that clearly and describe remaining risk rather than assuming success.

## Report delivery clearly
- Summarize the precise behavior changed, files/contracts affected, blast radius considered, and checks run.
- Call out deployment steps that are not automatic—especially database migrations—and distinguish local/CI validation from production verification.
