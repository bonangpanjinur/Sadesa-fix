# Rencana Komisi Referral Pedagang untuk Verifikator dan Admin Desa

**Status:** audit selesai; implementasi transaksi/payout menunggu konfirmasi basis pembagian komisi karena berdampak langsung pada uang yang dibebankan/dibayarkan.

## Temuan audit repository

1. **Referral pedagang saat ini hanya beratribusi ke verifikator.** Form pendaftaran menyimpan `merchants.verifikator_code`, lalu trigger menyimpan `merchants.verifikator_id` dan/atau kelompok dagang. Tidak ada model referral umum yang dapat mengidentifikasi admin desa sebagai pemilik kode.
2. **Komisi verifikator lama memang ada**, tetapi sumbernya berbeda dari sistem wallet pedagang baru:
   - `verifikator_earnings` mencatat komisi saat pembayaran subscription/paket kuota lama menjadi `PAID`, memakai `transaction_packages.group_commission_percent`;
   - migration `verifikator_admin_sales_commission` menambah aturan dinamis untuk paket kuota dan penjualan produk admin;
   - migration unified referral mencatat komisi verifikator dari `courier_earnings` (`TRANSACTION`), bukan dari potongan wallet merchant.
3. **Wallet komisi baru hanya untuk `MERCHANT` dan `COURIER`.** Trigger penyelesaian order/ride menagih wallet pedagang/ojek. Tidak ada posting pendapatan referral dari fee merchant ke verifikator/admin desa.
4. **Admin desa belum memiliki referral commission/payout.** Hubungan admin desa ke desa ada di `user_villages`; toko memiliki `village_id`, tetapi hubungan satu desa saja tidak membuktikan bahwa pemilik toko memakai referral admin desa.
5. **UI admin saat ini tidak mengatur tarif referral transaksi merchant wallet.** `AdminVerifierCommercePage` mengatur komisi toko produk admin, sedangkan `AdminVerifikatorCommissionsPage` masih mengatur `group_commission_percent` paket lama dan withdrawal verifikator. Keduanya tidak sama dengan referral dari fee wallet merchant.
6. **Pencatatan dan penarikan perlu disatukan untuk kedua jenis referrer.** Skema lama memakai `verifikator_earnings`/`verifikator_withdrawals`; admin desa belum tercakup. Tidak ada ledger payout bersama yang merekam snapshot rate, transaksi dasar, perubahan/refund, dan relasi withdrawal secara idempoten.
7. **Refund perlu ditautkan ke pendapatan referral.** Sistem wallet membalik komisi pedagang secara proporsional setelah settlement refund sukses; belum ada reversal referral sehingga saldo referral dapat salah bila refund terjadi.
8. **Belum ada perlindungan atribusi yang memadai untuk skema dua role.** Kode/referrer harus dicatat pada merchant sebagai snapshot dan tidak boleh dapat diganti setelah ada transaksi yang sudah menghasilkan komisi.

## Rekomendasi aturan bisnis

Untuk menghindari komisi referral menjadi biaya baru di atas fee yang sudah ditetapkan kepada pedagang:

- Tarif referral masing-masing role dihitung sebagai **persentase dari komisi platform merchant yang benar-benar terkumpul**, bukan persentase dari total penjualan pedagang.
- Contoh: order Rp20.000, fee pedagang 5% = Rp1.000; jika tarif referral verifikator 20%, pendapatan referral = Rp200. Total biaya pedagang tetap Rp1.000.
- Hanya komisi yang benar-benar telah tertagih dari saldo/top-up yang menjadi basis pendapatan referral. Bagian fee yang masih berupa debt belum menjadi kas dan belum menghasilkan referral payable.
- Referrer ditetapkan **satu pemilik kode referral per pedagang**. Kode verifikator yang sudah terhubung tetap berlaku untuk transaksi baru setelah fitur diaktifkan. Admin desa memperoleh atribusi ketika pedagang secara eksplisit mendaftar memakai kode referral admin desa; tidak otomatis menggunakan kesamaan `village_id`.
- Tidak ada komisi retroaktif untuk transaksi sebelum tanggal aktivasi. Tarif dan referrer disimpan sebagai snapshot per baris ledger untuk menjaga riwayat saat konfigurasi berubah.
- Pendapatan ditahan sebagai `PENDING` selama jendela refund yang aktif; jika refund sukses, reversal referral dicatat proporsional. Setelah masa tahan, nilai masuk ke `AVAILABLE` untuk pengajuan withdrawal manual, dengan pencatatan persetujuan/pembayaran admin. Jika reversal datang setelah dibayar, selisih dicatat sebagai carry-forward negatif untuk mengimbangi earning berikutnya—bukan mengubah histori transaksi.
- Tarif default 0% dan nonaktif sampai admin menyimpan konfigurasi. Admin dapat mengatur tarif verifikator dan admin desa secara independen.

## Rencana implementasi setelah kebijakan disetujui

### Fase 1 — Konfigurasi dan referral attribution

- Tambahkan tabel pengaturan tarif referral dengan role `VERIFIKATOR` dan `ADMIN_DESA`, persentase, status aktif, basis yang eksplisit, pembuat, dan timestamp.
- Tambahkan kode referral generic yang dapat dimiliki verifikator/admin desa. Validasi owner-role, status akun, desa/penempatan admin desa, keunikan kode lintas jenis, dan lifecycle kode.
- Integrasikan validasi/penyimpanan referral code ke RPC pendaftaran merchant yang ada. Simpan attribution immutable/snapshot (`referral_owner_user_id`, `referral_owner_role`, `referral_code_id`) di merchant atau tabel attribution tersendiri.
- Backfill hanya verifikator yang sudah memiliki `merchants.verifikator_id` yang sah; tidak mengasumsikan seluruh pedagang sebuah desa direferensikan admin desa.

### Fase 2 — Accrual aman dari fee wallet

- Perluas proses komisi merchant di database agar mencatat fee yang terkumpul vs debt secara terpisah.
- Posting ledger referral dalam transaksi database yang sama ketika fee merchant tertagih; kunci row wallet/ledger dan gunakan unique idempotency key per fee source/referrer.
- Simpan snapshot basis, fee merchant aktual, rate referral, amount referral, code, owner, source order, dan status masa tahan.
- Jika fee dilunasi belakangan melalui top-up, alokasikan pendapatan referral hanya atas debt fee yang benar-benar dilunasi. Hindari komisi ganda saat retry/top-up/webhook.
- Tambahkan reversal proporsional yang idempoten mengikuti settlement refund; jika earning sudah dibayarkan, rekam carry-forward untuk kompensasi earning masa depan.

### Fase 3 — Dashboard/payout per role

- Admin mengelola dua rate independen, toggle aktif, dan melihat total pending/available/paid, merchant referral, transaksi sumber, refunds, dan ekspor/audit.
- Verifikator melihat tautan/kode, daftar merchant yang direferensikan, pendapatan pending/available, ledger, serta status withdrawal.
- Admin desa memperoleh halaman referral/komisi dengan fungsi serupa, dibatasi ke atribusi dan kode miliknya; tidak boleh melihat merchant desa lain atau data identitas yang tak diperlukan.
- Buat request withdrawal bersama untuk kedua role (atau refactor withdrawal lama tanpa menghapus histori). Request, saldo available, approval, payout reference, dan debit ledger harus atomik/idempoten.
- Pengiriman uang tetap manual melalui admin dan baru ditandai paid setelah transfer di luar aplikasi berhasil; tidak mengklaim transfer bank otomatis.

### Fase 4 — Migrasi, keamanan, dan rollout

- Semua SQL baru ditempatkan **hanya di `supabase/bootstrap`** sesuai aturan repository, dengan urutan/hash manifest benar; tidak menambah SQL fitur ke `archive`.
- Default rate nonaktif 0%. Uji SQL parser, validator manifest, RLS, role boundaries, race condition, repeat webhook, double status transition, partial debt payment, partial/full refund, duplicate withdrawal, dan rollback.
- Tampilkan aturan basis/rate sebelum enablement. Deploy staging dahulu; bandingkan perhitungan dengan sampel order/ledger sebelum admin mengaktifkan tarif di production.

## Keputusan kebijakan
Pengguna menyetujui basis **persentase dari fee platform merchant yang benar-benar tertagih**, bukan omzet bruto. Tarif awal kedua role tetap 0% dan nonaktif; admin harus mengatur dan mengaktifkan tiap role secara eksplisit.

## Status implementasi (9 Oktober 2026)
### Selesai di repository
- Bundle `92_20261009110000_merchant_referral_commissions.sql` menambahkan pengaturan independen `VERIFIKATOR`/`ADMIN_DESA`, tabel kode referral generik, snapshot atribusi merchant, ledger fee-source/collection allocation, ledger komisi referral, serta permintaan payout.
- Kode verifier lama dimirror ke registri referral generik; kode admin desa dibuat melalui RPC yang membatasi akun pada desa aktif/disetujui. Validasi pendaftaran memakai RPC aman yang tidak mengungkap user ID pemilik kode.
- Atribusi kode dicatat ke merchant saat pendaftaran; perubahan kode setelah tersimpan ditolak agar attribution tidak bergeser diam-diam.
- Trigger wallet merekam fee per transaksi merchant, membedakan fee tertagih dari debt. Pembayaran debt lewat top-up dialokasikan FIFO; debt lama saat rollout menjadi sumber legacy non-referral sehingga tidak menghasilkan komisi retroaktif.
- Earning referral diposting idempoten dalam transaksi database yang sama hanya atas fee yang tertagih. Waktu rilis memakai `commission_wallet_policy_settings.refund_window_days`.
- `reverse_commission_for_refund` diperluas untuk reversal fee/referral secara proporsional dan idempoten setelah settlement refund berhasil. Pengaruh refund terhadap fee debt tercatat tanpa mengkreditkan komisi referral yang belum tertagih.
- Disediakan RPC ringkasan, daftar pedagang referral tanpa data kontak, pengajuan payout, dan pemrosesan admin (approve/reject/paid). Status paid wajib mencatat referensi transfer; transfer bank tetap proses manual di luar aplikasi.
- UI admin mengatur tarif per role dan memproses payout. Verifikator dan admin desa memiliki panel kode, merchant referral, saldo pending/tersedia, ledger, dan payout. Laporan keuangan desa yang lama memberi label 3% omzet sebagai **estimasi non-payout**, bukan earning referral.
- Notifikasi in-app idempoten dikirim saat ledger komisi referral baru tercatat dan saat status payout berubah menjadi disetujui/ditolak/dibayar. Notifikasi payout hanya untuk pemilik payout; admin tetap memantau request baru dari dashboard. Tautan mengarah ke panel referral, termasuk tab referral verifikator.
- Semua SQL baru ada di `supabase/bootstrap`; manifest mendaftarkan bundle 92 sebagai bundle standalone, tidak ditambahkan ke arsip migrasi.

### Masih perlu sebelum mengaktifkan tarif di production
1. Terapkan bundle 92 pada staging setelah 86–91, lalu uji terhadap skema project Supabase aktual. Validasi repository tidak membuktikan SQL sudah diterapkan ke project.
2. Uji dua role/RLS, kode aktif/nonaktif/batas pakai, attribution registration, transaksi normal, saldo kurang → debt → top-up, refund parsial/penuh sebelum/sesudah waktu rilis, retry settlement/top-up, dan permintaan payout concurrent.
3. Rekonsiliasi hasil ledger terhadap beberapa transaksi staging secara manual sebelum admin mengaktifkan tarif production.

### Sisa peningkatan (di luar cutover awal)
- Ekspor CSV dan pagination tanggal untuk ledger referral berskala besar.
- Koreksi attribution merchant melalui workflow admin yang ter-audit; untuk saat ini kode yang sudah terpasang sengaja immutable.
- Otomatisasi transfer bank/API payout (tidak tersedia pada implementasi ini; payout saat ini dicatat manual oleh admin).
