# Rencana peralihan kuota tier harga ke saldo rupiah + komisi

**Status:** fase 1–4 telah diimplementasikan pada branch ini, termasuk pengajuan top-up, verifikasi admin, dan UI saldo/ledger. Belum deploy ke Supabase production. Kebijakan legacy sudah dipilih: saldo tidak dikonversi otomatis; saldo pembuka hanya dari top-up/pembayaran yang diverifikasi. Migrasi data/rollout dan pengujian staging tetap diperlukan.

## Sasaran produk

- Pedagang dan ojek membeli saldo rupiah di muka.
- Setiap transaksi selesai memotong fee = `round(basis_transaksi × tarif_persen / 100)`.
- Admin mengatur tarif pedagang dan ojek secara independen.
- Saldo, transaksi, dan snapshot tarif dapat direkonsiliasi.
- Tidak ada tarif yang dipercaya dari browser; penentuan nilai transaksi, tarif aktif, dan saldo terjadi di database.

## Keputusan aman yang dipakai untuk implementasi ini

1. Basis pedagang = `orders.subtotal`, tidak termasuk ongkir. Basis ojek penumpang = `ride_requests.final_fare`.
2. Fee dihitung saat order menjadi `DONE`/`DELIVERED`/`COMPLETED` atau ride menjadi `COMPLETED`; transaksi belum selesai tidak dipotong.
3. Saldo tidak boleh negatif. Jika tarif aktif tetapi saldo kurang, perubahan status selesai ditolak dan seluruh transaksi database di-rollback.
4. Tarif awal kedua segmen 0% dan nonaktif. Admin harus mengisi dan mengaktifkan tarif secara eksplisit.
5. **Keputusan pemilik (2026-10-09): kuota lama tidak dikonversi otomatis.** Saldo wallet baru Rp0 sampai menerima top-up terverifikasi; tidak ada kredit pembuka dari nilai kuota.
6. Kuota lama dan tier tetap disimpan untuk audit/transisi. Penghentian lama dilakukan pada fase cutover terpisah; fitur fee tetap nonaktif sampai top-up tersedia dan tarif diaktifkan admin.

## Rencana fase

### Fase 0 — Inventarisasi dan kontrol risiko
- Catat tabel, RPC, UI, RLS, dan titik penyelesaian transaksi yang sudah ada.
- Jangan hapus `quota_tiers`, `merchant_subscriptions`, atau data pemakaian.
- Gunakan tarif 0%/nonaktif sebagai default agar migration tidak memungut fee tanpa konfigurasi.

### Fase 1 — Model wallet dan ledger (implementasi)
- Buat satu wallet rupiah per pedagang dan per courier.
- Buat pengaturan tarif terpisah `MERCHANT`/`COURIER`.
- Ledger mencatat top-up, komisi, refund, dan adjustment dengan idempotency key dan snapshot persentase.
- RLS mengizinkan pemilik membaca saldo/riwayat; mutasi hanya melalui backend/RPC tepercaya.

### Fase 2 — Aturan fee dan konsistensi transaksi (implementasi)
- Potong berdasarkan nilai tersimpan server-side, lock row transaksi dan wallet.
- Tolak saldo tidak cukup secara atomik saat fee sudah aktif; tidak ada kondisi saldo minus.
- Pasang hook database hanya pada transisi status final, bukan saat order dibuat.
- Retry terhadap source transaksi yang sama tidak boleh memotong ulang.

### Fase 3 — Admin dan top-up (implementasi alur inti)
- Halaman `/admin/wallet-commissions` mengatur tarif terpisah, validasi 0–100%, dan toggle aktif.
- Pedagang/ojek mengajukan top-up Rp10.000–Rp1.000.000.000 dengan bukti privat; satu permintaan pending per akun.
- Admin dapat melihat bukti melalui signed URL dan menyetujui/menolak. Persetujuan mengubah status request, saldo, dan ledger secara atomik serta idempoten.
- **Belum selesai:** dashboard agregat saldo/rekonsiliasi menyeluruh dan alert saldo rendah.
- Jangan menyamakan setoran courier yang ada dengan saldo komisi tanpa audit; setoran dan wallet komisi memiliki tujuan berbeda.

### Fase 4 — UX merchant/ojek (implementasi wallet, cutover masih bertahap)
- Halaman saldo terpisah untuk pedagang dan ojek menampilkan saldo, tarif aktif, permintaan top-up, status review, dan 25 mutasi terbaru.
- Bukti transfer disimpan privat; halaman memberi instruksi rekening/QRIS dari `admin_payment_info`.
- Courier wallet komisi dibedakan jelas dari `courier_deposits`/saldo operasional yang lama.
- Saat tarif merchant aktif, listing/detail produk beralih dari pemeriksaan subscription/free-tier ke wallet aktif dengan saldo positif; RPC publik hanya mengembalikan eligibility merchant tanpa mengekspos nominal saldo. RLS menghentikan pembelian paket kuota baru di server. Mode tarif nonaktif mempertahankan alur legacy.
- **Belum selesai:** alert saldo rendah, estimasi potongan pada checkout/ride, dan perubahan availability gate lama.

### Fase 5 — Cutover tanpa konversi legacy otomatis
- Tidak ada saldo pembuka yang dihasilkan dari kuota lama. Pengguna mengisi wallet melalui top-up baru yang diverifikasi.
- Buat laporan kuota historis/free/expired/outstanding untuk keperluan audit; pertahankan tabel lama selama masa transisi.
- Hanya jika ada kasus koreksi tersendiri, admin keuangan dapat mengkredit adjustment dengan alasan dan ledger auditable; bukan konversi batch.
- Uji parallel checkout, retries, status payment/refund, concurrency, RLS, dan rekonsiliasi saldo.
- Aktifkan tarif per segmen dalam jadwal rollout; pantau saldo dan dispute.

### Fase 6 — Penghentian tier
- Setelah masa observasi dan rekonsiliasi, hentikan penjualan paket kuota dan pemotongan tier.
- Pertahankan tabel lama untuk laporan/audit; hapus hanya pada keputusan migrasi terpisah dan setelah backup.

## Kriteria penerimaan

- Rp10.000 dengan 5% membebankan Rp500; Rp20.000 membebankan Rp1.000.
- Dua penyelesaian bersamaan pada wallet yang sama tidak dapat membelanjakan saldo yang sama dua kali.
- Retry RPC atas order/ride yang sama tidak membuat debit kedua.
- Status selesai gagal/rollback jika saldo kurang, kecuali tarif dimatikan.
- Perubahan tarif admin tidak mengubah ledger masa lalu.
- Pengguna hanya membaca wallet miliknya; pengguna biasa tidak bisa menulis saldo, ledger, atau tarif.
- Top-up hanya dikreditkan setelah bukti pembayaran disetujui melalui jalur tepercaya.

## Deploy / rollout

- Migration baru ada di `archive/supabase/migrations/20261009090000_commission_wallet_system.sql` dan `archive/supabase/migrations/20261009091000_commission_wallet_topups.sql`; bootstrap bundle dan manifest juga diperbarui.
- Terapkan keduanya lebih dulu di staging. Uji pengajuan bukti private, RLS owner/admin, approval/penolakan, retry approval, saldo kurang, dan dua charge bersamaan.
- Jangan aktifkan tarif admin sampai saldo, pembayaran, dan komunikasi kebijakan merchant/ojek siap. Kuota lama tetap dibaca/dipertahankan selama masa transisi; tidak ada konversi atau pemindahan data oleh migration ini.
- Deployment ke Supabase production belum dilakukan dari sesi ini.

## Hal yang masih perlu keputusan pemilik sebelum production

- Apakah subtotal pedagang harus dihitung setelah diskon/voucher atau sebelum diskon; migration saat ini memakai `orders.subtotal`.
- Apakah ada minimum fee, batas maksimum fee, atau pengecualian transaksi gratis.
- Kebijakan refund bila fee sudah terpotong: pengembalian penuh, proporsional, atau hanya jika order dibatalkan karena kesalahan platform.
- Tidak ada konversi otomatis saldo legacy (sudah diputuskan). Nilai adjustment/manual untuk kasus khusus tetap harus disertai kebijakan dan alasan keuangan.
- Apakah courier barang juga membayar fee, atau hanya ride penumpang.
