# Peralihan kuota tier ke saldo rupiah dan komisi persentase

**Status implementasi:** fase inti telah ditambahkan ke repository: wallet pedagang/ojek, pemotongan komisi atomik, ledger dan pencatatan tagihan, dashboard admin, pengajuan top-up manual dan invoice Xendit, refund komisi prorata, peringatan saldo rendah, guard transaksi baru saat ada tagihan, serta penghentian UI tier lama. **Belum diterapkan ke database Supabase production.** Terapkan dan uji di staging terlebih dahulu.

## Sasaran

- Pedagang dan ojek mengisi wallet rupiah sebelum bertransaksi.
- Tarif admin dipisah untuk pedagang dan ojek, dapat diubah tanpa migration.
- Komisi dihitung dari basis transaksi tersimpan di server, bukan nominal atau tarif yang dikirim browser.
- Mutasi saldo/debt disimpan di ledger append-only dan idempoten.
- Riwayat paket/kuota lama dipertahankan untuk audit, tetapi **tidak dikonversi dan paketnya dihentikan**.

## Keputusan bisnis yang telah diterapkan

1. **Kuota lama hangus/tidak dikonversi otomatis.** Migration mengakhiri langganan legacy aktif, menonaktifkan semua paket/tier, dan mempertahankan data lama untuk audit. Saldo wallet dimulai nol.
2. Basis komisi pedagang adalah `orders.subtotal` (ongkir tidak termasuk). Basis ride ojek adalah `ride_requests.final_fare`. Komisi courier pengiriman barang menggunakan `courier_earning_estimate` dengan fallback ke `shipping_cost`; toggle tersebut terpisah di pengaturan ojek dan default aktif.
3. Tarif pedagang dan courier disimpan independen. Default masing-masing **0% dan nonaktif**, tidak ada charge sampai admin secara eksplisit mengatur lalu mengaktifkan tarif.
4. Fee rupiah dihitung `round(basis × fee_percent / 100)`; rupiah dibulatkan ke nilai terdekat. Nilai batas yang diizinkan saat ini 0–100%; belum ada minimum fee atau cap selain batas persentase.
5. Jika saldo tersedia tidak cukup saat transaksi selesai, sistem menarik saldo yang ada, mencatat sisanya sebagai tagihan (debt), dan **tidak membuat saldo negatif**. Setelah itu transaksi baru ditahan sampai tagihan lunas. Top-up melunasi debt terlebih dahulu, kemudian sisanya menjadi saldo tersedia. Saat tarif ojek aktif, courier juga harus memiliki saldo positif dan tidak punya debt sebelum dapat online atau menerima pekerjaan.
6. Jendela permintaan refund default **7 hari**, dapat diubah admin (1–365 hari). Setelah refund benar-benar berhasil disettle, fee dibalik secara proporsional (`nilai refund ÷ orders.total`), dibulatkan ke rupiah, dan pembalikan membayar debt terlebih dahulu sebelum menambah saldo tersedia.
7. Ambang peringatan saldo rendah default **Rp10.000**, dapat diatur admin.
8. Top-up manual memakai bukti privat dan persetujuan admin. Pembayaran Xendit membuat invoice otomatis; wallet hanya dikreditkan setelah webhook provider terverifikasi. Permintaan pending per owner dibatasi satu.

## Perubahan yang sudah diimplementasikan

### Database dan transaksi

- `commission_wallets`, `commission_fee_settings`, dan `commission_wallet_ledger` menyediakan wallet per pemilik, tarif terpisah, serta ledger saldo/debt.
- Fungsi komisi database mengunci transaksi dan wallet, memakai basis server-side, menyimpan snapshot tarif, dan idempoten terhadap retry.
- Hook completion untuk order, ride, dan delivery mencatat komisi pada status final.
- Trigger server memblokir order baru merchant serta penerimaan ride/delivery oleh courier jika terdapat tagihan.
- Eligibility listing merchant hanya mengembalikan informasi tersedia/tidak tersedia, bukan nominal saldo atau debt.
- Refund memakai jendela yang dapat diatur; komisi hanya dibalik setelah provider settlement sukses.
- Legacy packages/tiers dinonaktifkan; subscription aktif ditandai expired; UI admin/merchant legacy menjadi histori read-only.
- Migration cutover **berhenti dengan error** jika masih ada subscription/pembayaran kuota legacy yang pending. Pending tersebut harus direkonsiliasi sebelum cutover agar invoice lama tidak membuat transaksi tak tertangani.

### Top-up dan antarmuka

- Merchant dan courier mendapat halaman wallet dengan saldo, debt, tarif, mutasi, peringatan saldo rendah, simulator potongan transaksi, status top-up, dan pengajuan manual/Xendit.
- Dashboard admin mengelola tarif pedagang/ojek, tarif courier delivery, ambang saldo, jendela refund, ringkasan total saldo/debt, wallet berisiko, permintaan top-up, dan ekspor hingga 1.000 mutasi ledger ke CSV.
- Invoice Xendit memakai reservasi database/idempotency; webhook memverifikasi nominal, invoice, pemilik, dan status sebelum mengkreditkan wallet. Ini tidak mengubah pembelian checkout order yang telah ada.
- Saldo courier wallet tetap terpisah dari `courier_deposits`/deposit operasional.

## Prasyarat sebelum cutover/production

1. Pastikan backup database dan deploy seluruh fungsi Edge Function/payment webhook terkait.
2. Di database produksi, audit `merchant_subscriptions` yang status atau payment status-nya pending. Selesaikan/reconcile dahulu; jika masih tersisa, migration cutover memang akan gagal aman.
3. Terapkan migration berurutan di staging: wallet, manual top-up, operasi/cutover, Xendit top-up, refund policy. Bootstrap bundle untuk instalasi database baru harus dihasilkan ulang dari arsip migration.
4. Siapkan credential Xendit aktif, webhook/callback URL, konfigurasi `admin_payment_info` sebagai jalur manual cadangan, dan uji callback signature menggunakan lingkungan staging.
5. Uji fee contoh: Rp10.000 × 5% = Rp500; Rp20.000 × 5% = Rp1.000. Uji pula order komisi lebih besar dari saldo, debt ditahan, pelunasan debt oleh top-up, retry/double webhook, invoice creation yang diulang, refund penuh/parsial, penguncian order baru, RLS, dan ekspor ledger.
6. Komunikasikan bahwa tier/kuota lama tidak bisa dipakai dan tidak bernilai saldo baru. Aktifkan setiap tarif secara eksplisit setelah pembayaran/top-up dan rekonsiliasi siap.

## Batasan yang belum dilakukan

- Migration **tidak dijalankan** pada Supabase production dan tidak ada perubahan saldo production yang dilakukan.
- Belum ada sandbox/staging Xendit live transaction atau uji concurrency terhadap database Postgres aktual dari sesi ini.
- Angka dasar merchant tetap `orders.subtotal`; sebelum production, konfirmasi dengan sampel order bahwa kolom tersebut merupakan basis komisi yang dikehendaki terhadap voucher/diskon. Sistem juga belum menerapkan tarif minimum atau batas rupiah maksimum.
- Refund prorata diterapkan atas `orders.total`; kebijakan ini perlu ditinjau untuk kombinasi refund produk, ongkir, dan subsidi/voucher.
- CSV admin membatasi query pada 1.000 ledger terbaru per pemuatan; ekspor laporan historis lebih besar memerlukan pagination/server-side reporting.

## Berkas SQL deployment utama

- `supabase/bootstrap/86_20261009090000_commission_wallet_system.sql`
- `supabase/bootstrap/87_20261009091000_commission_wallet_topups.sql`
- `supabase/bootstrap/88_20261009092000_commission_wallet_operations.sql`
- `supabase/bootstrap/89_20261009093000_xendit_commission_wallet_topups.sql`
- `supabase/bootstrap/90_20261009094000_commission_refund_policy.sql`
