# API Endpoint Security Audit

Tanggal: 2026-08-23.

## Scope and architecture

The repository is a Vite SPA. There is no active Node/Express API server in the Railway container; privileged API behavior is implemented in Supabase Edge Functions. The legacy `/api/*` bridge intentionally fails closed and is not an API deployment target.

## Endpoint review

| Endpoint | Authentication | Main review result |
|---|---|---|
| `admin-create-user` | Bearer token + admin role | Method guard, JWT verification, allowlisted roles, password/email/name limits, and rollback on provisioning failure are present |
| `xendit-payment` | Bearer token + order ownership | Secret stays server-side, order amount is read from database, invoice reservation and provider idempotency are present |
| `xendit-webhook` | Callback token | Constant-time token comparison, invoice/amount checks, event deduplication, and terminal PAID state are present |
| `assign-courier` | Bearer token + admin/merchant ownership | Added method guard, CORS allowlist, coordinate/distance validation, service-config fail-closed check, and compare-and-set courier assignment |
| `send-push-notification` | Bearer token + admin role | Added method guard, CORS allowlist, admin requirement for every target, content/recipient/URL limits, and generic error response |
| `wilayah-proxy` | Public by design | Public upstream proxy with input validation and cache; keep restricted to non-sensitive regional data |

## Remediations

`assign-courier` previously accepted unrestricted CORS, unbounded distance and coordinate values, and used a check-then-update sequence that could double-assign an order under concurrent requests. The endpoint now validates method, required secrets, bearer authentication, distance range, coordinate range, and uses a `courier_id IS NULL` compare-and-set update.

`send-push-notification` previously accepted unrestricted CORS, did not explicitly reject non-POST requests, and allowed any authenticated user to send to a direct target. It now requires an admin role before querying subscriptions or sending any notification, validates title/body/recipient/URL size, restricts URLs to internal paths, and returns a generic error rather than provider internals.

Payment endpoints retain the previous hardening: secret separation, order ownership, database-derived amount, idempotency reservation, constant-time webhook token verification, provider event deduplication, invoice matching, amount matching, and PAID terminal-state behavior.

## Local validation

The following passed after the endpoint changes: `pnpm exec tsc --noEmit`, `pnpm lint`, `pnpm test`, `pnpm build`, and `git diff --check`. The test suite reports 16 files passed, 46 tests passed, and 11 intentionally skipped RLS staging tests. The production bundle contains a 51,586-byte `POSKasirPage` chunk with no chunk warning. Production dependency audit reports zero critical, high, or moderate advisories and one low advisory.

## Required staging validation

Static review cannot prove Supabase role behavior or provider callback correctness. Before production, run tests against a dedicated staging project for anon/authenticated/service-role access, unauthorized admin/courier calls, cross-tenant order IDs, concurrent courier assignment, forged callback token, duplicate webhook ID, changed payment amount, out-of-order payment state, push recipient limits, and invalid CORS origins. Do not use production credentials for these tests.
