# Dokumentasi SaDesa

Dokumentasi dikelompokkan berdasarkan topik. Nama dan tanggal pada dokumen historis dipertahankan agar riwayat audit dan keputusan tetap mudah ditelusuri.

> Audit, rencana, laporan pengujian, dan hasil pentest adalah snapshot pada waktu tertentu. Cocokkan dengan kode, migrasi, dan hasil verifikasi lingkungan terbaru sebelum menjadikannya gambaran kondisi produksi.

| Folder | Isi |
|---|---|
| [`api/`](api/) | Kontrak autentikasi, RPC/API, escrow, dan sengketa. |
| [`architecture/`](architecture/) | Arsitektur dan kontrak produk lintas fitur. |
| [`audits/`](audits/) | Audit alur, keamanan, UX, performa, dan kesiapan fitur. |
| [`changelogs/`](changelogs/) | Catatan perubahan implementasi dan migrasi. |
| [`database/migrations/`](database/migrations/) | Panduan migrasi dan deployment database. |
| [`database/sql/`](database/sql/) | Skrip SQL operasional yang terdokumentasi. |
| [`implementation/`](implementation/) | Evidence dan ringkasan implementasi per fase. |
| [`operations/`](operations/) | Runbook, SOP, onboarding, dan operasi layanan. |
| [`pentest/`](pentest/) | Laporan penetration test. |
| [`plans/`](plans/) | Rencana bisnis, analisis, dan rencana perbaikan. |
| [`reports/`](reports/) | Laporan operasional dan ringkasan eksekutif. |
| [`security/`](security/) | Audit keamanan, pemindaian dependensi, dan mitigasi fraud. |
| [`testing/`](testing/) | Laporan E2E dan checklist kesiapan rilis. |

## Referensi utama

- [API autentikasi](api/api-authentication.md)
- [API marketplace jasa, escrow, dan sengketa](api/api-service-escrow-disputes.md)
- [Pentest transaksi end-to-end](pentest/pentest-transaksi-e2e-2026-09-11.md)
- [Laporan pengujian E2E](testing/e2e-full-test-report-2026-09-11.md)
- [Checklist kesiapan rilis](testing/release-readiness-checklist-2026-09-11.md)
- [Panduan migrasi dan deployment POS](database/migrations/pos-database-migration-deployment.md)
- [Audit fitur POS dari sisi merchant — 2 Oktober 2026](audits/audit-fitur-pos-merchant-2026-10-02.md)
- [Audit operasional POS untuk merchant — 2 Oktober 2026](audits/audit-operasional-pos-merchant-2026-10-02.md)
- [Panduan implementasi dan operasional POS untuk merchant](operations/panduan-implementasi-pos-untuk-merchant.md)
- [Hasil uji E2E pembayaran POS dan kesiapan print — 2 Oktober 2026](audits/hasil-uji-e2e-pos-payment-print-2026-10-02.md)
- [Rencana perbaikan keseluruhan](plans/rencana-perbaikan-keseluruhan-2026-09-11.md)

Untuk cara menjalankan aplikasi dan quality gates, lihat [README proyek](../README.md).
