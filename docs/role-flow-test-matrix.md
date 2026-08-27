# Role Flow Test Matrix

**Repository:** `bonangpanjinur/remix-of-umkm-sadesa`  
**Audit baseline:** 27 August 2026  
**Status rule:** `PASS` means executed and assertions passed; `SKIPPED` means the test exists but required fixtures were absent; `BLOCKED` means execution requires a real staging deployment, provider sandbox, or user-controlled account.

## Test strategy

Testing is divided into three levels. Static checks validate route and source structure. Local automated tests validate deterministic frontend, RPC contract, validation, idempotency, and error-handling behavior without a real Supabase project. Staging tests validate real JWT, RLS, locks, triggers, database constraints, provider events, and multi-tenant behavior.

A green local suite must not be reported as a green role acceptance test when its integration cases are skipped.

## Role matrix

| Role | Primary flow | Local coverage | Staging acceptance flow | Current status |
|---|---|---|---|---|
| Anonymous visitor | Home → catalog → product/merchant/village/tourism → auth/help/privacy/terms | Route source scan and production build | Open public routes; verify no tenant data or mutation is exposed | Partial: public route scan only |
| Buyer/customer | Sign up/login → address → cart → voucher/cashback → checkout → payment → order tracking → chat → review → refund/dispute/reorder | Checkout, payment API/proof, forms, reorder, and UI tests | Use buyer JWT; create order; retry checkout; verify payment state, RLS, delivery visibility, refund, dispute, review ownership | Local PASS; staging BLOCKED |
| Merchant owner | Registration/approval → catalog/variant → price book/promotion → order acceptance → payment proof → fulfillment → inventory → supplier/finance → CRM/WhatsApp → subscription | Form tests, price/loyalty contract tests, build/typecheck | Use merchant JWT; verify only own merchant/outlet data, accept order, receive stock, apply price, manage subscription, dispatch notification | Local partial; staging BLOCKED |
| Cashier/POS user | Device registration → outlet access → open shift → sale → price/loyalty → payment → receipt → close shift → void/override/return | POS checkout, offline sync, operations, validation, price/loyalty tests | Use cashier JWT; test outlet isolation, device entitlement, concurrent sales, supervisor approval, offline conflict, cash mutation | Local partial; staging BLOCKED |
| Courier | Onboarding → availability → accept ride → pickup → delivery proof → failed delivery/return → COD reconciliation → commission → withdrawal | Limited unit coverage; source and build validation | Use courier JWT; verify only assigned rides, location privacy, proof, reassignment, COD discrepancy, commission/payout | BLOCKED: dedicated staging fixtures needed |
| Village admin | Village profile → merchant/event/tourism management → broadcast → donation/financial report | Build and source validation | Use `admin_desa` JWT; verify village scope, public/private visibility, financial audit, moderation, export restrictions | BLOCKED |
| Verifier | Merchant/village verification → evidence review → decision → commission/withdrawal | Build and source validation | Use verifier JWT; verify separation of duties, immutable evidence/decision, no self-approval, commission calculation | BLOCKED |
| Platform admin | User/role → merchant/order/refund/dispute/approval → finance/withdrawal → SEO/banner/backup → settings/API/PWA/health/logs | Admin page build/typecheck; static RLS audit; selected page tests | Use admin JWT; verify privileged actions, audit log, step-up controls, cross-tenant visibility, backup/restore, API key lifecycle | Local partial; staging BLOCKED |
| Service worker/provider | Claim queue → entitlement check → provider dispatch → retry/dead-letter → completion/reconciliation | Worker source lint and contract review | Use service role only; test signature/secret, quota idempotency, provider failure compensation, retry/out-of-order events | Local partial; staging/provider BLOCKED |

## Current automated results

| Command | Result |
|---|---|
| `pnpm exec tsc --noEmit` | PASS |
| `pnpm lint` | PASS with 0 errors and 3 Fast Refresh warnings |
| `pnpm test` | 18 files passed; 53 tests passed; 14 skipped |
| `pnpm test:integration` | 2 files passed; 2 tests passed; 14 skipped |
| `pnpm build` | PASS; PWA generated successfully |
| `pnpm validate:db-bootstrap` | PASS; 187 migrations in 8 ordered bundles |
| `pnpm audit:rls` | PASS according to current static checker |

## Required staging fixtures

The integration suite currently requires a real staging URL and publishable key, plus a dedicated POS staff account and IDs for tenant, outlet, product, customer, and cashier. The RLS role matrix additionally requires isolated accounts for buyer, merchant owner, cashier, courier, village administrator, verifier, admin, and at least two tenants.

Use disposable staging accounts and data. Do not use production accounts, production service-role keys, real customer personal data, or real payment credentials.

## Acceptance rule

A role is accepted only when its happy path, unauthorized path, retry/idempotency path, and relevant failure path pass. For financial, inventory, entitlement, and approval flows, at least one concurrent or replay test is mandatory. Any skipped role test remains an open release item.
