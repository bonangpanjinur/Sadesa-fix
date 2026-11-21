# Dokumentasi SaDesa

Dokumentasi dikelompokkan berdasarkan topik. Nama dan tanggal pada dokumen historis dipertahankan agar riwayat audit dan keputusan tetap mudah ditelusuri.

> Audit, rencana, laporan pengujian, dan hasil pentest adalah snapshot pada waktu tertentu. Cocokkan dengan kode, migrasi, dan hasil verifikasi lingkungan terbaru sebelum menjadikannya gambaran kondisi produksi.

| Folder | Isi |
|---|---|
| [`api/`](api/) | Kontrak autentikasi, RPC/API, escrow, sengketa, dan wallet komisi. |
| [`auth/`](auth/) | Template dan konfigurasi autentikasi. |
| [`architecture/`](architecture/) | Arsitektur dan kontrak produk lintas fitur. |
| [`audits/`](audits/) | Audit alur, keamanan, UX, performa, dan kesiapan fitur. |
| [`changelogs/`](changelogs/) | Catatan perubahan implementasi dan migrasi. |
| [`database/migrations/`](database/migrations/) | Panduan migrasi dan deployment database. |
| [`database/sql/`](database/sql/) | Skrip SQL operasional yang terdokumentasi. |
| [`implementation/`](implementation/) | Evidence dan ringkasan implementasi per fase. |
| [`migrations/`](migrations/) | Draft migrasi lintas domain yang belum menjadi panduan deployment. |
| [`operations/`](operations/) | Runbook, SOP, onboarding, dan operasi layanan. |
| [`pentest/`](pentest/) | Laporan penetration test. |
| [`plans/`](plans/) | Rencana bisnis, analisis, dan rencana perbaikan. |
| [`reports/`](reports/) | Laporan operasional dan ringkasan eksekutif. |
| [`security/`](security/) | Audit keamanan, pemindaian dependensi, dan mitigasi fraud. |
| [`testing/`](testing/) | Laporan E2E dan checklist kesiapan rilis. |

## Referensi utama

- [API autentikasi](api/api-authentication.md)
- [API marketplace jasa, escrow, dan sengketa](api/api-service-escrow-disputes.md)
- [Wallet komisi — ringkasan fitur dan dokumentasi API](api/wallet-komisi-api.md)
- [Pentest transaksi end-to-end](pentest/pentest-transaksi-e2e-2026-09-11.md)
- [Laporan pengujian E2E](testing/e2e-full-test-report-2026-09-11.md)
- [Audit kesiapan API payment gateway Xendit — 15 Oktober 2026](audits/audit-kesiapan-payment-gateway-xendit-2026-10-15.md)
- [Checklist kesiapan rilis](testing/release-readiness-checklist-2026-09-11.md)
- [Panduan migrasi dan deployment POS](database/migrations/pos-database-migration-deployment.md)
- [Runbook GDC QRIS MPM sandbox](operations/gdc-qris-mpm-sandbox-runbook.md)
- [Audit fitur POS dari sisi merchant — 2 Oktober 2026](audits/audit-fitur-pos-merchant-2026-10-02.md)
- [Audit operasional POS untuk merchant — 2 Oktober 2026](audits/audit-operasional-pos-merchant-2026-10-02.md)
- [Panduan implementasi dan operasional POS untuk merchant](operations/panduan-implementasi-pos-untuk-merchant.md)
- [Analisis area pelanggan teramai di POS](operations/pos-analisis-area-pelanggan.md)
- [Panduan merchant: area pelanggan teramai di POS](operations/panduan-merchant-area-pelanggan-teramai.md)
- [Hasil uji E2E pembayaran POS dan kesiapan print — 2 Oktober 2026](audits/hasil-uji-e2e-pos-payment-print-2026-10-02.md)
- [Rencana perbaikan keseluruhan](plans/rencana-perbaikan-keseluruhan-2026-09-11.md)
- [Rancangan UI/UX laporan dan analitik penjualan merchant](plans/desain-ui-ux-laporan-analitik-penjualan-merchant-2026-10-04.md)

Untuk cara menjalankan aplikasi dan quality gates, lihat [README proyek](../README.md).

## Cara menelusuri

- Mulai dari kategori di atas, lalu gunakan nama berkas untuk mengenali topik dan tanggal dokumen.
- Dokumen audit dan laporan bertanggal merupakan catatan historis; verifikasi temuan terhadap implementasi terbaru.
- Dokumen desain dan rencana menjelaskan usulan atau arah kerja, bukan bukti bahwa fitur sudah diterapkan.
- Pertahankan tanggal serta nama berkas saat menambah dokumen historis agar tautan dan jejak keputusan tetap dapat dilacak.
