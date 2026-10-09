# Rencana peralihan kuota tier harga ke saldo rupiah + komisi

**Status:** fase 1–2 telah diimplementasikan pada branch ini, termasuk migration, trigger penyelesaian, dan UI tarif admin. Belum deploy ke Supabase production. Alur permintaan/top-up ber-bukti, UI saldo pedagang/ojek, konversi saldo legacy, dan cutover masih menjadi pekerjaan lanjutan.

## Sasaran produk

- Pedagang dan ojek membeli saldo rupiah di muka.
- Setiap transaksi selesai memotong fee = `round(basis_transaksi × tarif_persen / 100)`.
- Admin mengatur tarif pedagang dan ojek secara independen.
- Saldo, transaksi, dan snapshot tarif dapat direkonsiliasi.
- Tidak ada tarif yang dipercaya dari browser; penentuan nilai transaksi, tarif aktif, dan saldo terjadi di database.

## Keputusan aman yang dipakai untuk implementasi ini

1. Basis pedagang = `orders.subtotal`, tidak termasuk ongkir. Basis ojek penumpang = `ride_requests.final_fare`.
2. Fee dihitung saat order menjadi `DONE`/`COMPLETED` atau ride menjadi `COMPLETED`; transaksi belum selesai tidak dipotong.
3. Saldo tidak boleh negatif. Jika tarif aktif tetapi saldo kurang, perubahan status selesai ditolak dan seluruh transaksi database di-rollback.
4. Tarif awal kedua segmen 0% dan nonaktif. Admin harus mengisi dan mengaktifkan tarif secara eksplisit.
5. Kuota lama tidak otomatis dinilai ulang menjadi uang. `transaction_quota` tidak mempunyai padanan rupiah historis yang andal, karena subscription lama pernah mengakumulasi quota dan tidak semua quota berasal dari top-up berbayar. Saldo pembuka perlu aturan finansial dan rekonsiliasi tersendiri.
6. Kuota lama tetap disimpan untuk audit/rollback. Cutover perilaku merchant baru boleh dilakukan setelah saldo legacy ditentukan dan alur top-up aktif.

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

### Fase 3 — Admin dan top-up (sebagian implementasi)
- **Selesai di branch ini:** halaman `/admin/wallet-commissions` untuk input tarif terpisah, validasi 0–100%, dan toggle aktif; RPC admin-only untuk kredit saldo yang sudah diverifikasi dan dicatat ke ledger.
- **Belum selesai:** layar monitoring saldo/ledger untuk admin.
- Alur top-up perlu request pembayaran, verifikasi admin/server, dan kredit wallet + ledger dalam satu transaksi.
- Jangan menyamakan setoran courier yang ada dengan saldo komisi tanpa audit; setoran dan wallet komisi memiliki tujuan berbeda.

### Fase 4 — UX merchant/ojek
- Ganti label kuota dengan saldo komisi/biaya layanan.
- Tampilkan saldo, tarif yang berlaku, estimasi potongan, notifikasi saldo rendah, dan riwayat ledger.
- Selaraskan kanal pembelian/top-up pedagang dan courier.
- Ubah product availability gate yang saat ini menutup toko saat kuota habis hanya setelah ada saldo top-up yang sah dan kebijakan saat saldo rendah sudah final.

### Fase 5 — Migrasi saldo pembuka dan cutover
- Buat laporan simulasi saldo pembuka, sumber dana, outstanding payment request, free quota, expiry, dan saldo yang pernah diakumulasi.
- Admin keuangan menyetujui aturan konversi; setiap saldo pembuka dicatat sebagai ledger adjustment auditable.
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

## Hal yang masih perlu keputusan pemilik sebelum production

- Apakah subtotal pedagang harus dihitung setelah diskon/voucher atau sebelum diskon; migration saat ini memakai `orders.subtotal`.
- Apakah ada minimum fee, batas maksimum fee, atau pengecualian transaksi gratis.
- Kebijakan refund bila fee sudah terpotong: pengembalian penuh, proporsional, atau hanya jika order dibatalkan karena kesalahan platform.
- Nilai konversi saldo pembuka legacy; jangan mengasumsikan satu kredit sama dengan Rp1.
- Apakah courier barang juga membayar fee, atau hanya ride penumpang.
