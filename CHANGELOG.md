# Changelog

Seluruh perubahan penting pada DesaMart / UMKM SaaS dicatat di dokumen ini.

## [Production Candidate] — 2026-08-25

**Baseline:** `25445bd` (`main`)

### Added

- Atomic POS checkout melalui `process_pos_sale` dengan server-authoritative price, total, stock locking, recipe consumption, voucher, loyalty, dan idempotency request key.
- Payment invoice idempotency, atomic payment webhook processing, reconciliation ledger, manual verification hardening, dan anomaly detection.
- Refund/return approval, cashier void approval, price override approval, stock adjustment approval, serta Admin Approval Center.
- Supplier payable, purchase receiving, purchase return, payment terms, partial supplier payment, dan supplier management UI.
- Stock batch, expiry tracking, FEFO selection, stock opname, multi-warehouse, atomic transfer, stock reservation, dan reservation lifecycle.
- Courier payroll/commission foundation, courier COD submission, admin COD reconciliation review, partial fulfillment, multi-shipment, dan dispute center.
- Structured product import/export dengan preview, validation, atomic commit, rollback, dan import job tracking.
- Price book berdasarkan tenant, outlet, customer segment, periode, status, dan priority; termasuk atomic price-book creation RPC dan merchant configuration UI.
- Loyalty rules engine dan immutable `pos_loyalty_ledger` dengan atomic earn/redeem dan idempotency.
- CRM segments/campaigns, POS customer–CRM identity mapping, abandoned-cart recovery, campaign dispatcher, dan notification delivery queue dengan retry/dead-letter.
- WhatsApp worker adapter, notification provider status handling, subscription billing controls, tax profiles, dan immutable accounting journal.
- Structured observability dengan domain, event, level, trace ID, duration, redaction, dan local ring buffer untuk payment, upload, realtime, webhook, offline sync, dan device.
- PWA device sessions dengan registration, heartbeat, last sync, cashier status, revoke session, audit actor, tenant scope, dan Admin PWA Devices page.
- Deployment tooling: migration validator, staging-only Supabase deploy wrapper, staging simulation, production environment checker, release checklist, dan incident response runbook.

### Changed

- POS cart diubah menjadi lazy-loaded component untuk mengurangi beban chunk awal `POSKasirPage`.
- Offline sale synchronization dialihkan ke atomic Supabase RPC dan tidak lagi mengandalkan bridge POS yang tidak aktif.
- Offline price changes menghasilkan conflict eksplisit dan tidak di-retry otomatis.
- Admin Approval Center tidak lagi melakukan direct browser update untuk marketplace refund atau stock adjustment sensitif.
- Stock transfer tidak lagi melakukan loop mutasi client-side; create/decide/complete diproses atomic di database.
- CRM delivery mendukung `pos_customer_id` sehingga customer POS tanpa akun login dapat masuk ke notification workflow.

### Security

- RLS enabled pada 146/146 tabel yang terdeteksi migration audit.
- Tenant/outlet checks ditambahkan pada RPC financial dan inventory.
- `SECURITY DEFINER` functions menggunakan `SET search_path = public` pada migration modern.
- EXECUTE privilege untuk public/anon direvoke pada checkout, payment webhook, loyalty, CRM dispatcher, trigger recovery, dan approval RPC sensitif.
- Upload/storage ownership, MIME/size validation, webhook/worker authentication, secret redaction, dan API security smoke-test tooling diperkuat.
- Environment policy memisahkan public `VITE_*` variables dari service-role key, payment secret, WhatsApp token, cron secret, database password, dan private signing key.

### Performance

- Lazy-load `POSCart` mengurangi chunk `POSKasirPage` dari 53.06 kB menjadi 42.86 kB, pengurangan sekitar 19.2%.
- Production build berhasil tanpa chunk warning POSKasir.

### Fixed

- Price book function yang memakai `priority` tanpa kolom diperbaiki.
- Perhitungan subtotal/discount server-side diperbaiki agar diskon item tetap dihormati saat effective price diterapkan.
- Storage upload failure tidak lagi tercatat sebagai success.
- PWA heartbeat dapat membedakan device revoked dari network failure.
- Migration audit parser mendukung legacy 8-digit dan modern 14-digit timestamp serta UUID migration names.

### Validation

- TypeScript: passed.
- ESLint: passed.
- Unit test: 17 files passed; 48 tests passed; 14 skipped.
- Integration suite lokal: 2 files passed; 2 tests passed; 14 staging-dependent tests skipped.
- Production build: passed.
- Migration validator: 182 migration files validated.
- RLS static audit: 146/146 tables RLS enabled.
- Dependency audit: no high/critical advisory; 2 low dan 1 moderate masih perlu review.

### Known Limitations

- Supabase staging migration apply belum dieksekusi karena project ref, credential staging, dan Supabase CLI belum tersedia pada release session.
- RLS mutation lintas tenant, PostgreSQL locking/concurrency, trigger behavior, provider webhook signature, API rate limiting, dan backup restore drill masih wajib dijalankan pada environment staging nyata.
- Package version masih `0.0.0`; gunakan commit SHA `25445bd` sebagai release baseline sampai organisasi menetapkan semantic version/tag resmi.

## [P1 Operational Foundation]

### Added

- Supplier payable, FEFO, multi-warehouse, reservation, courier COD, partial fulfillment, dispute center, approval workflow, structured import/export, price book, dan loyalty rules.

## [P0 Transaction Hardening]

### Added

- Atomic checkout/POS, payment webhook idempotency, refund/return controls, payment reconciliation, cashier controls, stock opname, purchase order/supplier foundation, offline queue hardening, backup/restore documentation, dan anomaly detection.
