# Final Production Release Checklist

**Project:** DesaMart / UMKM SaaS

**Release baseline:** `ca1e035` on `main`

**Release decision:** Conditional GO for local code readiness; NO-GO until Supabase staging execution and restore drill pass.

## A. Release governance

| Check | Owner | Status | Evidence |
|---|---|---|---|
| Main branch contains reviewed P0, P1, P2 commits | Engineering | Ready | `ca1e035` |
| Working tree clean before release | Engineering | Required | `git status --short` |
| Release tag and rollback commit recorded | Release manager | Required | Tag + commit SHA |
| Change window and operator assigned | Operations | Required | Deployment ticket |
| Production go/no-go approval recorded | Product/Operations | Required | Approval record |

## B. Local quality gate

Run the following commands from repository root:

```bash
pnpm install --frozen-lockfile
pnpm exec tsc --noEmit
pnpm lint
pnpm test
pnpm build
pnpm audit:rls
pnpm validate:migrations
git diff --check
git status --short
```

The current local baseline has TypeScript and ESLint passing, 17 test files passing, 48 tests passing, 14 skipped tests, production build passing, 146/146 database tables detected with RLS enabled, and 182 migration files validated. The skipped tests must not be ignored for production approval; they are staging-dependent tests and must be executed in the staging gate below.

## C. P0 transaction and security gate

| Area | Required verification |
|---|---|
| Atomic POS checkout | Server-authoritative totals, stock locks, recipe consumption, voucher/loyalty side effects, rollback on failure, duplicate request behavior |
| Payment webhook | Provider signature/callback verification, event idempotency, duplicate delivery, invalid payload, amount mismatch, replay behavior |
| Refund/return | Full and partial refund, approval, restock, fee handling, status transition, duplicate approval prevention |
| Reconciliation | Order/invoice/settlement/fee/merchant balance matching and unresolved variance workflow |
| Cashier controls | Void and price override require approval; browser cannot direct-update sensitive state |
| Offline sync | Same-price reconnect succeeds; changed server price returns explicit conflict; conflict is persisted and not retried blindly |
| RLS isolation | Tenant A cannot read/write tenant B data or outlet B data; internal request tables remain deny-by-default |
| Storage | Ownership policy, MIME/size validation, path isolation, delete authorization, no public sensitive files |
| Secrets | No service-role key, provider secret, private key, or webhook secret in repository or `VITE_*` variables |

## D. P1 operational gate

Verify supplier payable terms/partial payments, batch and expiry FEFO ordering, warehouse transfer locking, stock reservation release/consume/expiry, courier commission/payroll, COD reconciliation, partial fulfillment quantity limits, dispute center, approval center, import preview/rollback, price book priority/period/outlet/segment, and loyalty earn/redeem idempotency and concurrency.

## E. P2 growth and platform gate

Verify CRM customer mapping for POS customers without login accounts, campaign delivery queue and retry/dead-letter behavior, WhatsApp opt-in and provider configuration, subscription event processing, accounting journal/tax export, structured observability, PWA registration/heartbeat/revoke, device status view, accessibility of critical cashier flows, and route chunk performance.

## F. Database and staging gate

Use a separate Supabase staging project. Set staging variables only in a protected environment file and never commit them:

```bash
export SUPABASE_PROJECT_REF="<staging-project-ref>"
export SUPABASE_TARGET_LABEL="staging"
pnpm deploy:staging:db
```

Then run:

```bash
RLS_ENV_FILE=.env.rls.staging ./scripts/run-rls-staging.sh
pnpm test:integration
SUPABASE_TEST_ENV_FILE=.env.rls.staging bash scripts/security-api-smoke.sh
bash scripts/backup-restore-drill.sh
```

The staging report must include migration apply output, migration version, RLS mutation results, P0 price/loyalty/RPC results, API CORS/auth/rate-limit results, notification worker result, and backup restore verification. Any migration error, unexpected row visibility, missing privilege denial, failed atomic rollback, or unverified restore is a production blocker.

## G. Railway deployment gate

Confirm Railway variables contain only public browser configuration: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, and `VITE_SUPABASE_PROJECT_ID`. Confirm server-only secrets are stored in the appropriate Supabase/worker secret store. Deploy the Docker image, then verify:

```bash
curl -fsS "$RAILWAY_PUBLIC_URL/health"
curl -fsS -I "$RAILWAY_PUBLIC_URL/"
```

Expected health response is `{"status":"ok"}`. Verify HTTPS, SPA fallback, service worker, no secret in `dist`, cache behavior, and browser login redirect URLs.

## H. Go/no-go and rollback

Release is **GO** only when local gates, staging migration/RPC/RLS tests, API smoke tests, backup restore drill, and business smoke tests pass. If the frontend is defective, redeploy the previous Railway commit. If a database migration is defective, stop traffic or affected worker paths and use an approved compensating migration or restore drill; never manually delete production tables or edit migration history.

Record release SHA, migration version, deploy timestamp, operator, staging report, production smoke results, dashboard links, and rollback decision.
