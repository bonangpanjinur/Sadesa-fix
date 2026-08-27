# Audit Teknis dan UI/UX Panel Admin SaDesa

**Tanggal audit:** 27 Agustus 2026  
**Scope:** frontend React/Vite, Supabase/RLS/RPC, bootstrap database, POS, subscription, worker, PWA, dan seluruh panel admin.

## Ringkasan Eksekutif

Repository memiliki cakupan domain yang luas: marketplace, merchant, POS, inventory, delivery, desa wisata, verifikasi, cashback, subscription, notification, backup, dan administrasi platform. Fondasi engineering sudah cukup baik karena TypeScript, production build, unit test, bootstrap validator, dan static RLS audit tersedia. Namun, status sistem masih **release candidate**, bukan production-certified, karena integration test dengan database staging nyata dan JWT per role masih banyak yang dilewati.

Ditemukan juga ketidakkonsistenan operasional yang penting. Panel admin memiliki banyak halaman dan menu pada satu daftar panjang tanpa pengelompokan domain, sehingga operator sulit menemukan tugas prioritas. Badge approval tersebar pada menu berbeda, sebagian statistik dimuat sekali ketika layout dipasang, dan banyak halaman perlu diaudit untuk memastikan query error, empty state, mutation loading state, dan permission failure ditampilkan secara konsisten.

## Baseline yang Terverifikasi

| Area | Kondisi |
|---|---|
| TypeScript | Lulus pada baseline terakhir |
| Production build | Lulus pada baseline terakhir |
| Unit test | 53 passed, 14 skipped pada baseline terakhir |
| Integration/RLS test | Sebagian besar skipped karena fixture dan Supabase staging belum tersedia |
| Bootstrap database | 188 migration dalam 8 bundle, validator tersedia |
| Static RLS audit | Tersedia dan lulus pada baseline terakhir |
| ESLint | 0 error; tersisa 3 warning Fast Refresh |
| Working tree | Memiliki artifact lokal yang sengaja tidak dilacak; tidak boleh masuk commit |

## Temuan Prioritas P0

| Temuan | Risiko | Rekomendasi |
|---|---|---|
| Integration test staging belum berjalan | RLS, locking, trigger, dan RPC atomic belum terbukti pada database nyata | Jalankan bootstrap staging, buat fixture JWT per role, dan aktifkan integration suite |
| State machine transaksi lintas payment, fulfillment, refund, dan settlement perlu diuji end-to-end | Status dapat tidak sinkron atau menghasilkan saldo/stock yang salah | Tetapkan state transition table dan test setiap transition termasuk retry serta webhook out-of-order |
| Operasi sensitif harus selalu melalui approval/atomic RPC | Bypass UI atau mutation langsung dapat memicu fraud atau perubahan saldo tanpa otorisasi | Audit refund, void, price override, stock adjustment, payout, dan perubahan rekening |
| Worker quota WhatsApp perlu kebijakan kompensasi provider failure | Quota bisa terpotong ketika provider gagal permanen | Gunakan ledger reversal/compensation dan dead-letter queue yang dapat direview |
| Backup restore belum diuji | Backup yang berhasil dibuat belum membuktikan pemulihan | Jalankan restore drill ke project staging disposable dan bandingkan row count, constraint, policy, serta function |

## Temuan P1

| Area | Perbaikan |
|---|---|
| Admin navigation | Kelompokkan menu menjadi Overview, Operasi, Keuangan, Growth, Compliance, dan System; sediakan pencarian menu dan quick action untuk approval tertunda |
| Admin data states | Standarkan skeleton, empty state, error state dengan retry, mutation disabled state, toast, dan timestamp data terakhir |
| Merchant/POS | Uji onboarding usaha, outlet isolation, inventory approval, price book, loyalty, printer, offline queue, dan checkout atomic |
| Observability | Tambahkan correlation ID yang konsisten pada payment, upload, realtime, webhook, offline sync, serta alert untuk error rate dan dead-letter |
| Subscription | Uji upgrade/downgrade, prorata, grace period, expiry, duplicate event, dan entitlement enforcement pada device serta WhatsApp |
| Data export | Validasi CSV/Excel preview, schema validation, rollback, audit trail, dan batas ukuran file |

## Temuan P2

| Area | Perbaikan |
|---|---|
| Accessibility | Keyboard navigation, focus ring, screen reader label, kontras, font scaling, dan assisted cashier mode menjadi release gate |
| Public API | Versioning, scopes, key rotation, replay protection, signature verification, quota, dan audit log |
| Accounting/tax | Rekonsiliasi jurnal, fee, pajak inclusive/exclusive, refund, settlement, payable, dan receivable |
| CRM | Segmentasi customer, consent WhatsApp, abandoned-cart recovery, retry, opt-out, dan dead-letter review |

## Roadmap Implementasi Bertahap

### Tahap 1 — Fondasi keselamatan

Jalankan staging bootstrap nyata, integration JWT/RLS per role, concurrency test RPC, dan state transition test untuk checkout/payment/refund. Tidak ada hasil yang dianggap lulus hanya berdasarkan dry-run.

### Tahap 2 — Admin operator experience

Refactor AdminSidebar menjadi navigasi berkelompok dengan pencarian, quick actions, badge approval terpusat, mobile drawer yang stabil, dan branding dinamis SaDesa. Tambahkan komponen reusable untuk page header, filter bar, state panel, dan destructive confirmation.

### Tahap 3 — Admin data integrity

Audit semua mutation admin agar memeriksa error response, tidak melakukan optimistic update pada operasi finansial tanpa rollback, mengirim audit event, dan menampilkan permission failure secara jelas.

### Tahap 4 — Operational completeness

Selesaikan restore drill, webhook replay protection, notification dead-letter handling, subscription lifecycle, COD reconciliation, dan monitoring alert.

## Release Gate

Release production hanya boleh dilanjutkan bila bootstrap dan replay staging lulus, integration JWT/RLS per role lulus, concurrency test kritikal lulus, build dan test CI hijau, restore drill berhasil, secret tervalidasi tanpa output sensitif, serta operator dapat menyelesaikan approval/refund/settlement melalui panel admin tanpa bypass.
