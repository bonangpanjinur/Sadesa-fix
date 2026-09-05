# Runbook UAT Konsolidasi Kasir POS

Dokumen ini adalah lembar eksekusi untuk memvalidasi cutover kasir setelah migrasi database diterapkan pada environment staging atau production. Runbook ini tidak menggantikan backup, approval perubahan, atau kontrol akses environment.

## Prasyarat

Sebelum UAT dimulai, operator harus menyimpan baseline menggunakan `scripts/run-pos-baseline-report.sh`, memastikan bootstrap staging selesai tanpa error, dan mencatat commit aplikasi yang sedang diuji. Gunakan merchant uji yang datanya boleh berubah dan jangan menggunakan transaksi pelanggan nyata untuk skenario destructive seperti void atau retur.

Catat informasi eksekusi berikut:

| Field | Nilai |
|---|---|
| Environment | staging / production |
| Commit aplikasi |  |
| Database/project reference |  |
| Operator |  |
| Waktu mulai UTC |  |
| Baseline report |  |
| Backup/reference change ticket |  |

## Skenario UAT

| ID | Skenario | Langkah minimum | Bukti yang wajib dicatat | Hasil |
|---|---|---|---|---|
| UAT-01 | Merchant satu outlet | Login sebagai owner merchant, buka `/merchant/pos/kasir`, pastikan outlet aktif terpilih otomatis | Screenshot outlet, tenant ID tersamar, timestamp | PASS / FAIL |
| UAT-02 | Merchant multi-outlet | Login sebagai user yang memiliki akses ke dua outlet, pastikan hanya outlet yang diizinkan muncul dan pergantian outlet mengubah katalog/stok | Screenshot daftar outlet dan stok | PASS / FAIL |
| UAT-03 | Kasir non-owner | Login sebagai role `kasir`, lakukan checkout tunai nominal kecil | Nomor `pos_sales`, total, kembalian, status stok sebelum/sesudah | PASS / FAIL |
| UAT-04 | Split payment | Checkout dengan dua metode pembayaran yang jumlahnya tepat sama dengan total | Nomor transaksi dan rincian metode pembayaran | PASS / FAIL |
| UAT-05 | Voucher dan loyalty | Terapkan voucher valid dan/atau penukaran poin pada produk uji | Nomor transaksi, diskon, poin sebelum/sesudah | PASS / FAIL |
| UAT-06 | Idempotency | Kirim ulang request dengan request key yang sama atau ulangi retry jaringan | Satu `sale_id`, event `pos_checkout_duplicate`, tidak ada pengurangan stok kedua | PASS / FAIL |
| UAT-07 | Stok tidak cukup | Coba menjual kuantitas melebihi stok pada produk uji | Error transaksi, tidak ada row sale baru dan stok tidak berubah | PASS / FAIL |
| UAT-08 | Offline sale | Putuskan koneksi, simpan satu transaksi offline, pulihkan koneksi, tunggu sinkronisasi | Queue sebelum/sesudah, satu nomor transaksi, log sinkronisasi | PASS / FAIL |
| UAT-09 | Void/retur | Jalankan void atau retur menggunakan role yang diizinkan; ulangi dengan role kasir bila operasi dibatasi | Audit log, permission result, perubahan stok dan refund | PASS / FAIL |
| UAT-10 | Cetak dan reprint | Cetak struk, buka histori, lalu reprint transaksi yang sama | Nomor job receipt, screenshot struk, nomor transaksi | PASS / FAIL |
| UAT-11 | Histori legacy | Buka `/merchant/pos/transaksi` dan cari transaksi modern serta legacy yang sudah dipetakan | Nomor transaksi dan sumber histori | PASS / FAIL |
| UAT-12 | Redirect compatibility | Buka `/pos/kasir` dan `/merchant/pos`; pastikan keduanya berakhir di `/merchant/pos/kasir` tanpa checkout legacy | URL akhir dan event `legacy_pos_redirect` | PASS / FAIL |

## Pemeriksaan telemetry

Filter event observability berdasarkan `traceId`, lalu pastikan checkout memiliki urutan `pos_checkout_started` dan salah satu dari `pos_checkout_succeeded`, `pos_checkout_duplicate`, atau `pos_checkout_failed`. Untuk transaksi offline, `transactionSource` harus bernilai `offline_queue`. Untuk route lama, event `legacy_pos_redirect` harus memuat `sourcePath` dan `targetPath`.

Telemetry browser adalah sinyal diagnostik, bukan pengganti query database. Rekonsiliasi harus membandingkan request key, `pos_sales`, `pos_sale_items`, `pos_stock_mutations`, pembayaran, dan receipt job pada database target.

## Kriteria lulus dan rollback

UAT lulus apabila seluruh skenario P0 (UAT-01 sampai UAT-08 dan UAT-12) lulus, tidak ada transaksi duplikat, tidak ada perubahan stok parsial, dan tidak ada error RLS kritis. Jika satu skenario P0 gagal, hentikan rollout merchant terdampak dan arahkan ke halaman setup atau feature flag yang tidak memproses checkout baru. Jangan mengaktifkan kembali checkout legacy untuk membuat transaksi.

Setelah perbaikan, ulangi baseline dan hanya ulangi skenario yang terdampak beserta UAT-06, UAT-07, dan UAT-08 untuk memastikan idempotency, atomicity, dan sinkronisasi tetap aman.

## Ringkasan hasil

| Kategori | Jumlah |
|---|---:|
| PASS |  |
| FAIL |  |
| BLOCKED karena environment |  |
| Exception terbuka |  |

Tautan screenshot, nomor transaksi uji, baseline sebelum/sesudah, dan keputusan rollout harus dilampirkan pada tiket perubahan. Jangan menandai UAT production selesai hanya berdasarkan test suite lokal.
