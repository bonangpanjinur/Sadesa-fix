# Release Notes Production

## DesaMart / UMKM SaaS — Production Candidate

**Release baseline:** `main` at commit `25445bd`

**Release date:** 25 August 2026

**Release status:** Production candidate; staging verification required before go-live

> Rilis ini membawa platform dari fondasi POS multi-tenant menjadi sistem operasional UMKM yang lebih aman, atomic, offline-aware, dan siap dikelola melalui workflow approval.

## Ringkasan

Rilis production candidate ini menyelesaikan hardening transaksi P0, fitur operasional P1, dan fondasi pertumbuhan serta kesiapan deployment P2. Fokus utama mencakup atomic checkout, payment idempotency, kontrol refund/void/price override, inventory multi-warehouse dan FEFO, supplier payable, fulfillment, CRM/WhatsApp queue, observability, PWA device management, serta audit RLS dan privilege RPC.

## Fitur utama

| Area | Peningkatan |
|---|---|
| POS dan checkout | Checkout atomic server-side, effective price berdasarkan price book, validasi stok, recipe consumption, voucher, loyalty, dan idempotency request. |
| Payment | Payment webhook idempotency, invoice request protection, payment reconciliation ledger, anomaly detection, dan kontrol amount/status. |
| Refund dan approval | Full/partial refund foundation, return/restock workflow, approval center, cashier void, price override approval, serta stock adjustment approval. |
| Inventory | Supplier payable dan termin, batch/expiry, FEFO, multi-warehouse, transfer atomic, stock reservation, stock opname, dan audit mutation. |
| Marketplace dan fulfillment | Partial fulfillment multi-shipment, reservation lifecycle, dispute center, COD reconciliation, dan courier payroll/commission foundation. |
| Pricing dan loyalty | Price book untuk segment/outlet/periode/prioritas serta loyalty rules dan immutable loyalty ledger dengan earn/redeem atomic. |
| CRM dan notification | Customer POS–CRM identity mapping, campaign dispatcher, abandoned-cart recovery, notification retry/dead-letter queue, dan WhatsApp worker adapter. |
| PWA operations | Registrasi device, heartbeat, last sync, cashier status, revoke session, tenant scope, dan admin device management. |
| Security | RLS pada 146 tabel, tenant isolation controls, SECURITY DEFINER privilege hardening, secret redaction, webhook/worker authentication, dan migration audit. |
| Performance | POS cart lazy-load; chunk `POSKasirPage` terukur jauh di bawah target 500 kB. |
| Deployment | Railway Docker/Caddy health check, migration preflight, staging-only deploy wrapper, environment checker, release checklist, dan incident response runbook. |

## Quality evidence

Local validation menunjukkan TypeScript dan ESLint lulus, 17 test files lulus dengan 48 test passed dan 14 skipped, production build lulus, 146/146 database tables terdeteksi memiliki RLS enabled, dan 182 migration files tervalidasi. Dependency audit terakhir tidak menemukan advisory high atau critical; tersisa dua low dan satu moderate untuk review.

## Catatan keamanan dan staging

Staging simulation berhasil menjalankan migration ordering check, RLS static audit, typecheck, lint, unit test, dan integration suite. Namun simulation belum menerapkan SQL ke Supabase server karena Supabase CLI, project staging, dan credential staging tidak tersedia pada sesi release.

Karena itu, status resmi adalah **conditional GO untuk code review dan local deployment candidate**, tetapi **NO-GO untuk production go-live** sampai staging migration, RLS mutation test, RPC locking/concurrency, webhook/API smoke test, dan backup restore drill lulus.

## Upgrade dan deployment

Ikuti dokumentasi berikut sebelum release: [`final-production-release-checklist.md`](./final-production-release-checklist.md), [`production-deploy-runbook.md`](./production-deploy-runbook.md), dan [`production-operations-incident-response.md`](./production-operations-incident-response.md). Jangan mengubah migration yang sudah diterapkan; gunakan migration kompensasi untuk perbaikan setelah deployment.

## Pengakuan perubahan

Rilis ini merupakan hasil rangkaian milestone P0, P1, P2, optimasi POS, observability, PWA management, RLS audit, dan Railway readiness yang tercatat pada commit history branch `main`.
