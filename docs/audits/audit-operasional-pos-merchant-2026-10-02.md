# Audit Operasional POS untuk Merchant — 2 Oktober 2026

**Ruang lingkup:** audit source code dan alur merchant POS di repository SaDesa, bukan audit atas data produksi, kontrak pembayaran, atau perangkat fisik.
**Kesimpulan:** fungsi inti POS tersedia pada kode, tetapi ada satu risiko ekspor laporan yang dapat menampilkan data agregat seolah-olah transaksi individual. Validasi staging, settlement pembayaran, dan printer fisik juga masih memerlukan bukti UAT tersendiri.

## Ringkasan eksekutif

POS mencakup aktivasi workspace/outlet, katalog bersama merchant, kasir, pembayaran, riwayat transaksi, retur, stok/pembelian, kas harian, laporan, pengguna/akses, mode offline terbatas, serta koneksi printer. Navigasi fitur mengikuti modul yang diaktifkan dan hak akses pengguna.

**Jangan menganggap keberadaan menu atau test otomatis sebagai bukti bahwa konfigurasi merchant, database staging/production, payment provider, dan perangkat sudah siap.** Sebelum perluasan penggunaan, jalankan checklist implementasi/UAT pada [panduan merchant](../operations/panduan-implementasi-pos-untuk-merchant.md) dan SOP pilot.

### Temuan paling penting

1. **P1 — Ekspor Excel dari Laporan Penjualan bukan ekspor transaksi.** Tombol `Excel` memanggil ekspor CSV yang mengubah baris *produk terlaris* menjadi baris seolah-olah invoice: nomor invoice buatan `1..n`, tanggal waktu ekspor, kasir/pelanggan `-`, dan total per produk. File ini **jangan** digunakan untuk rekonsiliasi transaksi atau pembukuan per invoice. Gunakan ekspor CSV pada **Transaksi Toko** untuk detail transaksi, dengan keterbatasan yang dijelaskan di bawah.
2. **P1 — Kesiapan deployment belum dibuktikan oleh audit source.** Aktivasi membutuhkan profil merchant disetujui/aktif dan entitlement trial/langganan POS aktif. Deployment database, RLS, data tenant/outlet dan rekonsiliasi harus lulus di environment sasaran.
3. **P1 — Kesiapan printer fisik belum diverifikasi.** Kode menyediakan beberapa jalur cetak dan test print, namun hasil test di kode/bridge tidak membuktikan kertas benar-benar tercetak pada model printer dan perangkat merchant.
4. **P2 — Riwayat dan ekspor transaksi tidak memiliki pagination server yang tampak pada halaman.** Pastikan jumlah/baris yang diekspor sesuai rentang dan filter. Untuk rentang besar, jangan menganggap file berisi semua transaksi tanpa mencocokkan jumlah dengan laporan.
5. **P2 — Pilihan metode pembayaran tidak dengan sendirinya membuktikan settlement.** Petunjuk UI sendiri meminta kasir memastikan QRIS berhasil, transfer masuk, atau transaksi terkonfirmasi pada EDC. Verifikasi dengan kanal pembayaran/acquirer merchant.

## Peta fitur merchant

| Area | Menu/route merchant | Hasil audit source | Catatan penggunaan |
|---|---|---|---|
| Aktivasi POS | `/merchant/pos/setup` | Wizard jenis usaha, pemilihan modul, katalog bersama, dan outlet pertama tersedia. Modul Kasir diwajibkan. | Diperlukan profil merchant yang disetujui/aktif dan entitlement trial/langganan aktif. Pilihan `Hanya online` mengarahkan kembali ke workspace merchant, bukan mengaktifkan POS fisik. |
| Katalog dan stok | `/merchant/products`, `/merchant/pos/kategori`, `/merchant/pos/stok` | Katalog merchant dipakai bersama; kasir membaca produk/varian dan stok outlet. Ada jalur inventori, pembelian, supplier, transfer, gudang, bahan baku, dan resep sesuai modul. | Sebelum buka kasir, pastikan produk aktif, harga/varian benar, serta stok ditempatkan pada outlet yang dipilih. |
| Checkout | `/merchant/pos/kasir` | Keranjang, pencarian/barcode, varian, pelanggan, promo/voucher/poin, bill tertahan, kalkulasi pembayaran dan pemanggilan checkout atomik tersedia. | Uji harga, diskon, jumlah bayar, kembalian, dan outlet pada transaksi uji. Jangan mengulang pembayaran yang statusnya belum jelas tanpa memeriksa riwayat/request terlebih dahulu. |
| Pembayaran | Dialog di `/merchant/pos/kasir` | UI menampilkan tunai, QRIS, transfer, debit dan split. Pembayaran tunai memvalidasi jumlah cukup; split harus sama dengan total. Pembayaran non-tunai tidak dapat diproses offline. | Pilihan metode mencatat metode transaksi; kasir tetap wajib mengonfirmasi dana/otorisasi pada kanal sebenarnya sebelum menyelesaikan penjualan. |
| Riwayat & struk | `/merchant/pos/transaksi` | Riwayat memakai view gabungan transaksi modern/legacy dan menyediakan detail, pencarian/filter, ekspor CSV serta cetak ulang. Ada fallback terbatas bila view laporan belum tersedia. | Tidak tampak pagination server atau indikator kelengkapan hasil. Ekspor hanya dari hasil yang telah dimuat dan difilter. Cek jumlah baris dan tanggal sebelum dipakai. |
| Retur | `/merchant/pos/retur` | Cari transaksi selesai, pilih item/jumlah, alasan, metode refund dan opsi restock. UI menyebut retur diajukan untuk approval. | Jangan menghapus/mengubah transaksi asal untuk “membatalkan” penjualan. Ikuti approval dan rekonsiliasi refund/restock. |
| Kas harian | `/merchant/pos/kas` | Buka/tutup sesi kas, catat kas masuk/keluar, tampilkan saldo ekspektasi dan rekonsiliasi harian. | Hitung uang fisik, masukkan saldo aktual dan catat alasan selisih. Jangan tandai rekonsiliasi selesai sebelum status/selisih ditinjau. |
| Staf dan akses | `/merchant/pos/pengguna`, `/merchant/pos/akses` | Form pengguna menyediakan role owner, manager, kasir, gudang, purchasing, finance, auditor; pengguna dapat dikaitkan ke outlet dan PIN kasir. | Terapkan hak minimum dan akun/PIN individual. Jangan berbagi PIN. Periksa role aplikasi dan entitlement jika rute tidak dapat dibuka. |
| Offline | `/merchant/pos/offline-conflicts` | Cache katalog, antrean lokal, status sync/conflict dan retry tersedia. Policy membatasi operasi offline. | Membutuhkan HTTPS, IndexedDB, dan service worker pada perangkat yang dipakai. Offline: penjualan tunai, katalog yang sudah dicache, struk lokal. Online wajib: pembayaran non-tunai, order marketplace, laporan final, settlement. Jangan hapus data lokal saat antrean masih ada. |
| Printer | `/merchant/pos/pengaturan` | Pengaturan koneksi USB/Bluetooth/Wi-Fi-LAN/Android service dan Print Bridge, test print, antrean/retry struk tersedia. Browser print menjadi fallback. | Test print/health check perlu dilengkapi pemeriksaan fisik: lebar kertas, encoding, potong kertas, duplikasi, outlet/header struk, dan reprint. |
| Promosi/pelanggan | `/merchant/pos/customer`, `/merchant/pos/promosi`, `/merchant/pos/loyalty` | Menu pelanggan, voucher/promosi, loyalty, analitik pelanggan tersedia sesuai akses/modul. | Uji aturan masa berlaku, minimum belanja, kombinasi diskon, dan hak redeem sebelum dipakai di toko. |
| Operasi F&B | `/merchant/pos/meja`, `/merchant/pos/menu-qr`, `/merchant/pos/kds`, `/merchant/pos/bahan-baku`, `/merchant/pos/resep` | Menu meja, QR, KDS, bahan baku dan resep tersedia untuk modul yang sesuai. | Memerlukan konfigurasi outlet/meja/menu dan UAT alur pesanan penuh; audit source tidak membuktikan QR publik atau perangkat dapur merchant sudah siap. |
| Laporan | `/merchant/pos/laporan` dan sub-rute laporan | Laporan rentang hari/minggu/bulan/tahun, omzet, transaksi, rata-rata, diskon, produk teratas dan ekspor PDF/CSV tersedia pada source. | Lihat temuan P1: tombol Excel pada halaman ini menyusun baris dari agregat produk dan bukan ledger transaksi. PDF berisi daftar produk teratas serta ringkasan. Bukan laporan pajak/akuntansi resmi. |

## Temuan dan tindakan yang disarankan

### P1 — Perbaiki ekspor Excel pada Laporan Penjualan

**Dampak:** file dapat disalahartikan sebagai daftar invoice, padahal baris bersumber dari `topProducts`. Nomor invoice, tanggal, kasir, pelanggan, metode bayar dan status diisi placeholder. Nilai total per baris adalah omzet produk agregat, bukan transaksi.

**Mitigasi merchant sementara:**

- Jangan gunakan tombol **Excel** di `Laporan Penjualan` sebagai data transaksi, bukti settlement, rekonsiliasi, atau pembukuan per invoice.
- Untuk daftar penjualan, gunakan **Transaksi Toko → filter tanggal/status → Ekspor CSV**. Cocokkan periode, outlet, jumlah transaksi dan total dengan laporan kas.
- Ingat bahwa halaman riwayat tidak menampilkan pagination server/indikator “seluruh data”; pada rentang besar, validasi kelengkapan ekspor sebelum dipakai sebagai dasar keputusan.
- PDF laporan saat ini merupakan ringkasan dan daftar produk teratas, bukan ekspor detail transaksi.

**Tindakan engineering:** pisahkan ekspor agregat produk dari ekspor transaksi, ganti label yang menyesatkan, gunakan nilai ringkasan kanonis langsung (bukan menghitung omzet dari daftar produk teratas), dan tambahkan regression test yang memastikan ekspor tidak membuat invoice/tanggal/kasir palsu.

### P1 — Bukti readiness environment dan settlement

**Risiko:** kode berjalan tidak membuktikan migrasi/backend, RLS runtime, entitlement, akun role, saldo/kas, integrasi acquirer atau settlement sudah benar pada environment merchant.

**Tindakan:** jalankan smoke/E2E terisolasi pada staging dengan tenant dan outlet uji; verifikasi pembayaran, stok, retur/refund, idempotensi, jurnal/rekonsiliasi, ekspor dan isolasi tenant/outlet. Jangan menguji dengan transaksi atau data produksi tanpa prosedur yang disetujui merchant.

### P1 — UAT printer di perangkat target

**Risiko:** status bridge/job “berhasil” bukan sensor kertas yang membuktikan struk benar-benar keluar atau terbaca.

**Tindakan:** uji minimal satu printer/perangkat per kombinasi yang didukung merchant: test print, transaksi sukses, reprint, antrean/offline bila didukung, kertas habis/disconnect, ukuran 58/80 mm, format rupiah/karakter, duplicate prevention, serta prosedur fallback browser. Catat model, versi OS/browser/PWA, jenis koneksi dan hasil.

### P2 — Pagination dan ekspor riwayat

**Risiko:** halaman mengambil hasil pada rentang waktu dan melakukan pencarian/ekspor dari data yang dimuat; tidak tampak pagination/range count. Pada volume besar, merchant tidak mendapat sinyal eksplisit bahwa ekspor lengkap.

**Tindakan:** implementasikan pagination server-side, total row count, pemrosesan rentang ekspor server-side dan filter yang disertakan dalam file. Sampai tersedia, gunakan rentang kecil dan cocokkan jumlah baris dengan sumber ringkasan.

### P2 — Kebijakan operasi dan bukti UAT offline

**Risiko:** hanya perangkat dengan HTTPS + IndexedDB + service worker dinyatakan mendukung; pembayaran non-tunai, laporan final dan settlement memerlukan koneksi. Status antrean lokal tidak sama dengan transaksi yang sudah tercatat di server.

**Tindakan:** lakukan latihan terputus/sambung kembali pada perangkat merchant; setelah koneksi pulih, cek antrean dan Offline Conflict Center. Jangan reset browser/perangkat, uninstall PWA, atau menghapus cache/site data selama antrean masih ada. Jika konflik, simpan ID/waktu/total, tahan retry berulang, dan eskalasi untuk rekonsiliasi.

## Prioritas implementasi

| Prioritas | Implementasi | Kriteria selesai |
|---|---|---|
| P1 | Koreksi ekspor laporan penjualan dan label tombol | Ekspor agregat memberi judul/kolom agregat yang benar; tidak membuat nomor invoice atau field transaksi palsu; test otomatis membuktikannya. |
| P1 | Staging E2E payment + stok + return + close/reconcile | Lulus pada tenant/outlet uji; bukti tersimpan; tidak memproses pembayaran riil. |
| P1 | Printer UAT perangkat merchant | Checklist fisik lulus untuk kombinasi perangkat-printer yang akan digunakan; fallback dan eskalasi terdokumentasi. |
| P2 | Pagination/kelengkapan export transaksi | Total hasil, filter, rentang, dan cakupan ekspor dapat diperiksa merchant. |
| P2 | UAT offline dan recovery | Policy device lulus; antrean terkonfirmasi masuk satu kali setelah sync; konflik diselesaikan tanpa kehilangan data. |

## Bukti dan referensi

- [Audit POS merchant sebelumnya](audit-fitur-pos-merchant-2026-10-02.md)
- [Hasil uji E2E pembayaran POS dan kesiapan print](hasil-uji-e2e-pos-payment-print-2026-10-02.md)
- [Audit kesiapan POS/PWA/printer](audit-kesiapan-pos-pwa-printer-2026-10-02.md)
- [SOP onboarding merchant pilot](../operations/sop-onboarding-merchant-pilot.md)
- [Panduan implementasi dan operasional POS untuk merchant](../operations/panduan-implementasi-pos-untuk-merchant.md)
- Source utama yang ditinjau: `src/components/pos/posNavigation.tsx`, `src/pages/pos/POSSetupPage.tsx`, `POSKasirPage.tsx`, `POSTransaksiPage.tsx`, `POSLaporanPage.tsx`, `POSReturPage.tsx`, `POSKasPage.tsx`, `POSPenggunaPage.tsx`, `POSPengaturanPage.tsx`, `POSOfflineConflictPage.tsx`, `src/lib/posPaymentValidation.ts`, `posDevicePolicy.ts`, `posDailyReconciliation.ts`, dan `exportReport.ts`.

---

**Catatan status:** dokumen ini adalah audit source dan panduan mitigasi, bukan persetujuan peluncuran. Keputusan GO tetap memerlukan bukti environment, perangkat, rekonsiliasi, support, dan owner sebagaimana SOP pilot.
