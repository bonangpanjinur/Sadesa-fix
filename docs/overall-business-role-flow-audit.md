# Overall Business, Role, and Flow Audit

**Repository:** `bonangpanjinur/remix-of-umkm-sadesa`  
**Audit date:** 27 August 2026  
**Scope:** Business model, end-to-end transaction flow, role access, tenant isolation, database/RPC, subscription, inventory, logistics, CRM, offline operation, observability, CI/CD, and production readiness.

## Executive assessment

The repository has evolved into a broad multi-sided commerce and POS platform for UMKM. It covers marketplace buying, merchant operations, cashier POS, courier delivery, village administration, verifier workflows, platform administration, subscription entitlements, CRM, inventory, payment processing, refunds, settlement, and operational reporting.

The architecture is directionally strong because critical operations increasingly use PostgreSQL RPCs, row-level security, idempotency keys, approval workflows, and durable queues. However, the system is not yet fully production-proven. The largest gap is not the absence of screens; it is the absence of enough **real-environment evidence** that the screens, RPCs, RLS policies, concurrency controls, payment events, and background workers work together under real JWT identities and failure conditions.

> Current status: **feature-rich release candidate; not yet fully production-certified**.

## Repository evidence

The local audit produced the following results.

| Check | Result | Interpretation |
|---|---:|---|
| TypeScript | Passed | No compile-time TypeScript error detected by `tsc --noEmit`. |
| ESLint | 0 errors, 3 warnings | Remaining warnings are Fast Refresh export warnings in `MerchantProductDetailEditor.tsx`, `RegisterMerchantPage.tsx`, and `MerchantProductsPage.tsx`. |
| Unit tests | 53 passed, 14 skipped | The suite passes, but skipped tests mean integration coverage is incomplete without staging fixtures. |
| Integration test command | 2 passed, 14 skipped | The command is structurally healthy but most real database tests are opt-in. |
| Bootstrap validation | Passed | Current canonical set contains 187 migrations in 8 ordered bundles. |
| Static RLS audit | Passed | No table without RLS/policy was reported by the current static audit, but this is not proof of runtime tenant isolation. |
| Staging database execution | Not run | `SUPABASE_DB_URL` and valid staging fixtures were not available in the current environment. |

The migration count is now **187**, rather than 186, because the explicit `pos_tenants.merchant_id` mapping migration was added. The staging validator reads this value dynamically from the manifest.

## Business model and value chain

The platform has five connected value loops. Buyers discover products, place orders, pay, track delivery, receive goods, and review merchants. Merchants manage catalog, pricing, inventory, POS, fulfillment, promotions, CRM, finance, and withdrawals. Couriers accept rides, deliver orders, reconcile COD, and receive commission or payouts. Village administrators and verifiers support local merchant onboarding, village commerce, events, tourism, and economic reporting. The platform owner controls governance, subscriptions, risk, payment reconciliation, approvals, and operational configuration.

| Business loop | Existing foundation | Main business risk still requiring proof |
|---|---|---|
| Marketplace order-to-delivery | Orders, payment proof/webhook controls, courier rides, fulfillment, partial fulfillment, reviews | Exceptions across payment timeout, stock change, failed delivery, cancellation, return, and partial shipment need one canonical state machine. |
| POS-to-inventory | Atomic POS sale, price book, loyalty, FEFO, reservation, warehouse transfer, shift/cashier controls | Concurrent sales, offline conflicts, negative stock, refund restock, and outlet isolation need real concurrency tests. |
| Merchant monetization | Subscription plans, entitlements, usage ledger, POS device limit, WhatsApp quota | Billing lifecycle, grace period, retry, refund, downgrade, and entitlement revocation need provider-event integration tests. |
| Platform revenue and control | Fees, commissions, ads, subscriptions, reconciliation, approval center, anomaly scans | Revenue leakage and fraud detection need settlement-level reconciliation and alert thresholds. |
| Village/local economy | Desa pages, merchant/village roles, events, tourism, donations, reports | Role boundaries, moderation, fund transparency, and data ownership need explicit operational policies. |

## Role-by-role audit

### Buyer/customer

The buyer flow is conceptually complete from discovery through checkout, payment proof, order tracking, chat, review, voucher, cashback, loyalty, referral, and reorder. The most important missing controls are customer identity unification between marketplace/auth users and POS customers, transparent refund/return status, clear partial fulfillment behavior, and protection against double charge or duplicate order submission during network retries.

A buyer should always see a single order timeline with payment state, fulfillment state, courier state, refund state, and support/dispute state. These states should not be inferred independently by each page. The recommended next improvement is a canonical order-status projection or view used by buyer, merchant, courier, and admin interfaces.

### Merchant owner

Merchant capabilities are extensive: onboarding, products, variants, pricing, wholesale, pre-order, flash sale, advertising, analytics, tax, finance, supplier dues, fulfillment, chat, loyalty rules, CRM, WhatsApp notification, import/export, and POS. The main risk is operational complexity. A merchant can have many screens but still lack a guided daily operating workflow.

The merchant dashboard should prioritize today’s actions: orders requiring acceptance, payment proofs requiring review, low stock, expiring batches, pending refunds, pending approvals, unpaid supplier invoices, COD exceptions, failed notifications, and settlement mismatch. The current feature set should be reorganized around these queues rather than only around CRUD pages.

### Cashier/POS user

The POS foundation is strong and includes outlet access, price book, stock, loyalty, payment, shift, void, price override, and offline concepts. The most sensitive risk is that cashier authorization must be enforced identically in UI, RPC, RLS, and audit log. A cashier must not be able to bypass supervisor approval by calling a table mutation directly or reusing a stale client request.

A production cashier flow needs a visible state for offline transaction, server reconciliation, price conflict, stock conflict, payment pending, and supervisor approval. Every void, discount override, refund, and cash mutation should include actor, approver, reason, timestamp, source device, and correlation ID.

### Courier

Courier pages cover dashboard, rides, history, earnings, deposit, withdrawal, chat, location, performance, and COD reconciliation. The remaining business risks are delivery proof integrity, location privacy, COD discrepancy handling, failed-delivery policy, commission calculation transparency, and payout timing.

Courier settlement should be generated from immutable completed-order facts. Manual edits should create adjustment records rather than changing the original commission or COD amount. The courier must be able to see why a payout changed and which orders contributed to the amount.

### Village administrator (`admin_desa`)

The village domain includes profile, merchants, economic reports, events, broadcasts, tourism, maps, tourism packages, guides, membership, donations, and financial reports. This is a distinct institutional domain and should not be treated as a lighter merchant admin.

The main gaps are governance and data ownership. Village financial data, donations, merchant verification, and public broadcasts require explicit audit trails, approval boundaries, moderation, retention, and public/private visibility rules. The system should distinguish village-owned records from merchant-owned records and define who may export or delete them.

### Verifier (`verifikator`)

Verifier routes and commission/withdrawal functionality exist. The critical control is separation of duties: a verifier who reviews merchant or village submissions should not be able to approve their own financial payout or modify the evidence being reviewed. Approval decisions should be immutable and should record the evidence snapshot, decision reason, and conflict-of-interest check.

### Platform admin

The admin area is broad and includes users, roles, merchants, villages, orders, refunds, disputes, approvals, finance, withdrawals, commissions, POS, SEO, settings, backup, banners, advertising, broadcasts, support tickets, system health, logs, realtime, PWA devices, API keys, and quota. Dynamicization has improved several pages, but the admin domain still needs a formal control-plane model.

Admin actions should be categorized as read, operational mutation, financial mutation, security mutation, and configuration mutation. Financial and security mutations should require stronger authentication, reason capture, approval or dual control, immutable audit records, and an emergency rollback procedure.

### Platform owner/operator

The owner needs metrics that are not currently proven end-to-end: GMV, net revenue, take rate, payment success, refund rate, fulfillment SLA, courier utilization, merchant retention, subscription conversion, WhatsApp cost per active merchant, stock shrinkage, fraud rate, and support resolution time.

A profitable platform should optimize revenue without harming users by charging for genuine operational value—additional outlets, automation, analytics, storage, API usage, and CRM volume—while preserving a usable free tier, transparent limits, export capability, and clear cancellation/grace-period rules.

## End-to-end flow audit

### Registration and identity

The repository contains role and merchant onboarding logic, but the identity model remains more complex than the UI suggests. A single person may be a buyer, merchant owner, cashier, courier, village administrator, verifier, or admin. The platform needs one identity-to-organization matrix, not only a list of roles. The explicit POS tenant-to-merchant mapping migration improves this area, but ambiguous existing users still require operational resolution.

Required improvement: define whether one user may own multiple merchants. If yes, every merchant-facing query and subscription action must carry an explicit merchant ID. If no, enforce uniqueness at database level after a data audit.

### Catalog, pricing, and promotion

Price book, wholesale pricing, loyalty rules, voucher, cashback, flash sale, and advertising capabilities exist. The critical requirement is a single effective-price resolver used consistently by marketplace, POS, cart, checkout, invoice, refund, and reporting. Price displayed on the client must never become the source of truth.

Required test cases include overlapping price books, outlet-specific priority, tier/member price, promotion expiration, tax-inclusive price, variant price, offline price conflict, refund price reconstruction, and supervisor-approved override.

### Checkout and payment

Atomic POS checkout, payment proof, provider webhook idempotency, invoice reservation, and reconciliation foundations exist. The remaining risk is cross-system state divergence. The system must distinguish order created, payment initiated, payment authorized, payment captured, payment failed, payment expired, payment refunded, and settlement completed.

Webhook processing must reject invalid signatures, deduplicate provider event IDs, tolerate out-of-order events, and never downgrade a paid state without an explicit refund or reversal event. Every provider response should be linked to an internal payment attempt and order correlation ID.

### Fulfillment and delivery

The platform has reservation, warehouse, shipment, partial fulfillment, courier, and COD foundations. The recommended canonical model is order → fulfillment group → shipment/package → delivery attempt. A single order can then be split without corrupting the buyer-facing order state.

Required edge cases include one item unavailable, one package delivered and another delayed, courier reassignment, failed delivery, customer refusal, damaged goods, return-to-merchant, and COD shortfall.

### Refund, return, dispute, and support

Approval and refund foundations exist, but user trust depends on a single consistent state machine. Refund amount, restocking, shipping fee, payment fee, cashback reversal, loyalty reversal, merchant balance impact, and customer notification must be calculated atomically or represented as compensating ledger entries.

Support tickets and disputes should link to the order, payment, shipment, refund, actors, evidence, and SLA. A ticket should not become a second uncontrolled source of transaction truth.

### Inventory and procurement

Supplier, payable, purchase order, batch/expiry, FEFO, warehouse, reservation, stock opname, and transfer features are present. The remaining gap is operational closure: receiving, quality check, batch capture, expiry alerts, supplier return, partial receipt, cost update, and accounting impact.

Stock should be an event ledger with derived balance. Manual adjustment must require reason, actor, approval where material, and before/after values. Offline stock decisions must be server-authoritative once synchronization occurs.

### Subscription and entitlement

The subscription design includes plans, plan entitlements, merchant overrides, invoices, usage counters, usage ledger, device limits, and WhatsApp metering. The principal risk is billing lifecycle completeness rather than schema coverage.

Required lifecycle tests are activation, duplicate payment event, out-of-order event, failed payment, grace period, suspension, renewal, upgrade, downgrade, prorated charge, cancellation, provider refund, invoice failure, and entitlement revocation. Entitlement denial must be clear to the user and must not silently discard queued business data.

### CRM, WhatsApp, and notifications

CRM segments, campaigns, abandoned-cart recovery, durable notification jobs, retry, dead-letter, and WhatsApp worker foundations exist. The explicit merchant mapping now prevents quota from being assigned through an ambiguous user-to-merchant lookup.

The remaining policy decision is whether quota is consumed on attempt or provider acceptance. A fair user-protective policy is to consume quota when the provider accepts the message and reverse it for permanent provider failure. If the business chooses attempt-based billing, that rule must be disclosed in the subscription terms and admin reporting.

### Offline-first operation

Offline queue and sync concepts exist, but production safety requires a formal conflict policy. The server must be authoritative for price, stock, payment, and entitlement. Each offline command needs a stable idempotency key, creation timestamp, device ID, client version, base entity version, and reconciliation outcome.

The user-facing result must distinguish accepted, duplicated, rejected, partially accepted, and requires-review. Silent overwrite is not acceptable for financial or stock data.

## Concrete findings discovered during route and copy review

| Finding | Severity | Why it matters | Recommended action |
|---|---|---|---|
| `/pos/harga` is intentionally public and presents package pricing, so it is not itself a data breach; however, it must remain a read-only marketing page and must not be reused for merchant data. | Medium | The route is unguarded while most POS routes are protected. Future edits could accidentally add sensitive queries to a public page. | Add a route classification test that asserts public POS pricing has no authenticated data mutation or tenant query. |
| The pricing page contains the claim that data is stored on “server Replit”, while the current deployment plan uses Vercel/Railway/Supabase. | High | Inaccurate infrastructure and privacy claims can create legal, trust, and support risk. | Replace infrastructure-specific copy with the approved hosting/privacy statement and maintain it from canonical app settings. |
| The pricing page claims “ribuan UMKM” and a 30-day no-card trial, while trial configuration is also runtime-driven elsewhere. | Medium | Marketing claims can diverge from actual entitlement and billing configuration. | Make trial days, plan features, and proof points data-driven; require product-owner approval for public claims. |
| The route scan found many public pages plus protected role pages, but there is no single machine-readable route-permission matrix. | High | A new route can be accidentally exposed or assigned to the wrong role. | Create a route policy registry and test every route for expected anonymous, authenticated, and role access. |

## Security and authorization findings

Static RLS coverage is encouraging, but runtime authorization still requires staging proof. Tests must use actual authenticated sessions for each role and two separate tenants. The minimum matrix should test select, insert, update, delete, and RPC execution for owner, staff, cashier, buyer, courier, village administrator, verifier, admin, anonymous, and service worker contexts.

The most important security controls are service-role isolation, `SECURITY DEFINER` search path hardening, explicit function grants, no direct client mutation of financial tables, signed webhook verification, replay protection, rate limiting, API-key scopes, secret rotation, storage ownership, audit-log immutability, and export/download authorization.

The application should also add step-up authentication for high-risk actions: changing bank account, approving payout, refunding high amounts, changing subscription, creating API keys, revoking devices, and modifying role assignments.

## Observability and operations

Structured observability already exists in several critical paths. It should be standardized around a correlation ID propagated from frontend request to RPC, webhook, queue job, provider request, and audit record.

| Domain | Required minimum signals |
|---|---|
| Payment | Provider event ID, internal payment ID, order ID, state transition, latency, signature result, duplicate/out-of-order decision. |
| Upload/storage | User, object key, bucket, content type, size, validation result, signed URL operation, failure reason. |
| Realtime | Channel, tenant, reconnect count, last event timestamp, dropped event count, fallback state. |
| Webhook | Provider, event ID, signature, status code, processing latency, retry count, dead-letter reason. |
| Offline sync | Device, command ID, client version, entity version, conflict type, resolution, queue age. |
| Worker | Job ID, tenant, merchant, attempt, quota decision, provider result, final state. |

Define alert thresholds before production: payment webhook failure rate, notification dead-letter count, reconciliation mismatch amount, queue age, offline conflict rate, repeated refund pattern, abnormal discount rate, and login/device anomalies.

## Prioritized roadmap

### P0 — release-blocking proof and controls

| Priority | Work item | Acceptance criterion |
|---|---|---|
| P0.1 | Run 187-migration bootstrap on isolated staging and replay it | Initial run, replay, schema smoke test, and RLS smoke test all pass. |
| P0.2 | Enable real JWT integration fixtures | Buyer, merchant owner, cashier, courier, village admin, verifier, and admin tests execute against staging. |
| P0.3 | Add concurrency harness | Parallel tests prove no double spend, oversell, duplicate checkout, duplicate quota, or bypassed approval. |
| P0.4 | Resolve ambiguous tenant–merchant mappings | Every WhatsApp-enabled tenant has exactly one explicit merchant mapping, or is disabled with an actionable admin status. |
| P0.5 | Finalize WhatsApp quota policy and compensation | Ledger behavior is documented and tested for provider acceptance, retry, permanent failure, and duplicate job. |
| P0.6 | Verify deployed secrets | Staging and production environment checks pass without printing secret values. |

### P1 — operational completeness

| Work item | Acceptance criterion |
|---|---|
| Unified order state projection | Buyer, merchant, courier, admin, refund, and support show consistent state. |
| Full refund/return ledger | Amount, fee, restock, loyalty, cashback, and balance effects reconcile atomically. |
| Supervisor control plane | Sensitive operations have no direct bypass and require reason/approval. |
| Backup restore drill | A new staging project is restored and passes row, constraint, RLS, RPC, and storage checks. |
| Merchant daily operations dashboard | Action queues are prioritized by SLA and risk. |
| Supplier/procurement closure | PO, receiving, supplier return, payable, and partial payment reconcile. |
| Courier/COD settlement | Immutable order-level calculation and discrepancy workflow are complete. |
| Offline conflict UI | Operators can review and resolve price/stock/payment conflicts. |

### P2 — growth and scale

| Work item | Acceptance criterion |
|---|---|
| Billing lifecycle | Upgrade, downgrade, prorata, grace, invoice, suspend, refund, and retry are provider-tested. |
| Public API lifecycle | Versioning, scopes, rotation, replay protection, signature verification, rate limits, and audit exist. |
| Advanced owner dashboard | GMV, net revenue, take rate, conversion, retention, SLA, shrinkage, and fraud metrics are trustworthy. |
| Accounting/tax export | Export reconciles to payment, refund, fee, tax, payable, receivable, and settlement ledgers. |
| Accessibility gate | Keyboard, screen reader, contrast, font scaling, and assisted cashier tests pass. |
| Dependency and CI gate | Every merge validates pnpm alignment, dependency risk, migrations, RLS, tests, and build. |

## Recommended next execution sequence

The next implementation sequence should be: first, run the staging bootstrap and create isolated fixtures; second, enable real JWT RLS tests; third, add concurrency tests for checkout, loyalty, reservation, device registration, and WhatsApp quota; fourth, resolve unmapped POS tenants; fifth, perform the backup restore drill; and only then proceed to broader P1 UI and operational enhancements.

This order minimizes the chance of polishing screens while foundational authorization, transaction atomicity, and recovery behavior remain unproven.
