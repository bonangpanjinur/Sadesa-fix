# Audit Fitur POS dari Sisi Merchant — 2 Oktober 2026

## Ringkasan eksekutif

Cakupan POS di repository sudah luas: kasir dan checkout atomic, stok per outlet, manajemen shift/kas, pelanggan/loyalty/promosi, laporan, retur, transaksi offline/recovery, serta kontrak struk dan reprint. Temuan audit ini bukan kekurangan menu baru, melainkan tiga celah yang dapat membuat merchant salah memahami kesiapan atau kelengkapan operasinya:

1. Riwayat transaksi merchant hanya membaca tabel POS modern walaupun repository sudah menyediakan view histori modern + legacy.
2. Setup printer yang bersifat opsional ikut menahan checklist onboarding agar tidak pernah selesai.
3. Kegagalan membaca jumlah transaksi pertama ditampilkan seperti belum ada transaksi.

Ketiganya sudah diperbaiki pada sisi UI/query dengan perubahan kompatibel. **Belum ada perubahan skema dan tidak ada migration yang dijalankan ke database staging/production.**

## Ruang lingkup dan batas audit

Audit menelusuri halaman kasir, riwayat transaksi, checklist onboarding, kontrak laporan/riwayat, sumber migration POS, dan test yang relevan pada repository `bonangpanjinur/Sadesa-fix`. Status di bawah adalah status kode lokal, bukan bukti bahwa seluruh SQL telah diterapkan atau alur sudah lulus UAT perangkat nyata.

## Inventaris fitur merchant yang sudah tersedia di kode

| Area | Dukungan yang ditemukan | Catatan kesiapan |
|---|---|---|
| Kasir dan checkout | Pencarian/barcode, varian, keranjang, held bills, tunai/non-tunai/split, promo/voucher, loyalty, checkout atomic dan idempotency | Ada di kode; integritas runtime tetap bergantung pada RPC dan migration yang diterapkan |
| Katalog dan stok | Kategori, varian, stok outlet, gudang, pembelian/retur/transfer, bahan baku/resep | Cakupan operasional sudah luas |
| Keuangan toko | Shift kasir, kas masuk/keluar, rekonsiliasi kas, hutang/piutang, akuntansi, laporan stok/laba-rugi/cashflow | Ada di kode; rekonsiliasi wajib diuji pada staging |
| Pelanggan dan pertumbuhan | Customer, loyalty, promosi, harga, target omzet, analitik | Ada di kode |
| Restoran | Meja, QR menu/order, KDS | Ada di kode; QR/order table memiliki boundary backend tersendiri |
| Offline dan printer | Queue offline, retry/conflict, recovery, print bridge/struk/reprint | Ada di kode; offline/printer belum boleh dianggap terbukti lintas perangkat tanpa UAT fisik |
| Akses dan outlet | Workspace, outlet, kasir/role, permission, audit | Ada di kode; scope tenant/outlet harus tetap diverifikasi runtime |

## Temuan dan perbaikan

### P1 — Riwayat transaksi tidak memakai histori gabungan

**Sebelum:** `POSTransaksiPage` hanya mengambil `pos_sales`, sehingga transaksi lama pada `pos_transactions` tidak muncul pada daftar, ringkasan periode, ekspor, detail, atau opsi cetak ulang. Ini tidak konsisten dengan kontrak repository: view `pos_unified_transaction_history` di migration POS menggabungkan penjualan modern dan transaksi legacy yang belum dipasangkan; transaksi baru tetap hanya ditulis ke tabel modern.

**Perbaikan:** halaman riwayat sekarang membaca view gabungan dan mempertahankan penanda sumber modern/legacy serta item yang dinormalisasi. Jika view belum tersedia, UI mengambil kembali `pos_sales` agar histori modern tetap dapat dipakai dan menampilkan peringatan bahwa data lama mungkin tidak lengkap. Fallback hanya berjalan untuk error spesifik view tidak ada/schema cache; error izin, koneksi, atau query lain tetap menjadi error dan tidak disamarkan sebagai data kosong.

**Batas:** transaksi legacy yang belum dapat dipetakan ke tenant/outlet secara aman tidak otomatis dimasukkan ke outlet aktif. Mapping ambigu perlu ditangani melalui proses rekonsiliasi yang telah disediakan; aplikasi tidak menebak outlet.

### P2 — Langkah printer opsional menahan onboarding

**Sebelum:** checklist menyebut browser print tersedia sebagai fallback, tetapi konfigurasi printer tetap dihitung sebagai langkah yang wajib. Merchant tanpa printer fisik tidak dapat mencapai status semua langkah selesai.

**Perbaikan:** progress sekarang menghitung hanya empat langkah inti. Printer tetap tampil sebagai langkah opsional dengan keterangan browser print tersedia, dan tidak memblokir CTA/status onboarding selesai.

### P2 — Error pemeriksaan transaksi pertama ditampilkan sebagai “belum ada transaksi”

**Sebelum:** error pada query hitung penjualan disamakan dengan hasil nol. Merchant dapat mengira transaksi belum tersimpan ketika masalah sebenarnya adalah koneksi/akses/database.

**Perbaikan:** error query atau rejection kini ditampilkan sebagai “Status transaksi belum dapat diverifikasi”, bukan sebagai nol transaksi. Langkah tersebut tetap belum selesai sampai status yang benar diketahui.

## Tindak lanjut yang belum dikerjakan

1. **Pagination riwayat transaksi:** halaman saat ini belum memakai cursor/range pagination. Pada outlet dengan volume tinggi, hasil yang mencapai row cap PostgREST yang dikonfigurasi bisa terpotong tanpa tombol “muat lagi”; pencarian dan ekspor hanya mencakup data yang dimuat. Rekomendasi berikutnya: pagination server-side dengan total/indikator hasil dan ekspor per rentang yang jelas.
2. **Verifikasi database:** pastikan migration unified history dan mapping legacy telah diterapkan pada staging. Uji tenant satu-outlet, multi-outlet, exception tanpa mapping, dan pasangan transaksi agar legacy tidak hilang atau tampil ganda.
3. **UAT offline/printer:** lanjutkan uji pada perangkat, browser, printer, restart bridge, recovery queue, reprint, dan koneksi terputus sesuai [audit PWA/printer 2 Oktober](audit-kesiapan-pos-pwa-printer-2026-10-02.md). Source test bukan pengganti bukti operasional fisik.
4. **Rekonsiliasi kas/stok:** validasi satu hari operasional penuh pada staging untuk checkout, retur, stok outlet, shift close, laporan, dan jurnal. Jangan menjalankan migration atau repair terhadap production tanpa prosedur deployment yang disetujui.

## File implementasi dan regresi

- `src/pages/pos/POSTransaksiPage.tsx` — pembacaan histori gabungan dan fallback modern-only dengan peringatan.
- `src/lib/posTransactionHistory.ts` — klasifikasi error view hilang yang sengaja sempit.
- `src/lib/posTransactionHistory.test.ts` — tes agar hanya missing-view yang memicu fallback.
- `src/components/pos/POSOnboardingChecklist.tsx` — printer opsional dan status error pemeriksaan transaksi yang jujur.
- `src/components/pos/POSOnboardingChecklist.test.tsx` — regresi onboarding opsional dan query error.

## Verifikasi

- Tes terarah riwayat/onboarding: **4 lulus**.
- TypeScript (`pnpm exec tsc --noEmit`): **lulus**.
- ESLint untuk file yang berubah: **lulus**.
- Suite penuh (`pnpm test`): **100 file lulus; 390 tes lulus dan 20 dilewati**.
- Production build (`pnpm build`): **lulus**, termasuk build service worker PWA.

> Temuan readiness produksi harus selalu dicocokkan dengan status migration dan hasil UAT pada environment target. Audit repository ini sendiri tidak membuktikan kondisi database production.
