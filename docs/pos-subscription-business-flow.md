# Flow Bisnis Subscription POS

## Prinsip utama

`pos_subscriptions` menjadi sumber kebenaran untuk **akses fitur POS**. Tabel `merchant_subscriptions` tetap digunakan untuk **quota transaksi marketplace** dan tidak boleh dipakai sebagai pengganti status akses POS. Dengan pemisahan ini, pemilik bisnis dapat memahami bahwa langganan POS mengaktifkan sistem kasir, sedangkan quota transaksi adalah produk billing yang berbeda.

## Aktor

| Aktor | Tanggung jawab |
|---|---|
| Pemilik bisnis | Melihat status POS, memilih paket, mengaktifkan trial jika tersedia, membayar, mengunggah bukti, memantau approval, memperpanjang, dan mengelola setup POS setelah aktif. |
| Admin/verifikator | Mengelola katalog paket, mengatur trial, memverifikasi pembayaran, menyetujui/menolak permintaan, memperpanjang atau mencabut akses sesuai prosedur, dan melihat audit trail. |
| Sistem | Menghitung expiry, mencegah trial ganda, menegakkan status aktif saat route/RPC dipanggil, mengirim status perubahan, dan menyediakan grace period/expired behavior yang konsisten. |

## Lifecycle subscription POS

`NO_SUBSCRIPTION → TRIAL_ACTIVE → ACTIVE → EXPIRING_SOON → EXPIRED`

Permintaan pembayaran menggunakan status terpisah: `PENDING_PAYMENT → PENDING_REVIEW → ACTIVE` atau `REJECTED`. Status `CANCELLED` dan `SUSPENDED` digunakan untuk penghentian administratif atau risiko pembayaran.

## Flow pemilik bisnis

1. Pemilik membuka **POS → Langganan POS**. Halaman selalu menampilkan status saat ini, paket aktif, tanggal berakhir, penggunaan fitur, dan tindakan yang tersedia.
2. Jika belum pernah trial, pemilik melihat kartu **Coba Gratis** dengan durasi dan syarat yang jelas. Trial hanya dapat diaktifkan satu kali dan harus ditetapkan oleh database, bukan hanya client.
3. Pemilik memilih paket. Kartu paket menampilkan harga total, durasi, fitur, jumlah outlet/user yang termasuk, dan kebijakan perpanjangan.
4. Untuk paket berbayar, pemilik membuat permintaan, menerima nomor invoice/request, melihat instruksi pembayaran, lalu mengunggah bukti pembayaran. Permintaan masuk ke `PENDING_REVIEW`.
5. Pemilik dapat melihat timeline: dibuat, bukti diunggah, sedang diverifikasi, disetujui/ditolak. Jika ditolak, alasan wajib tampil dan tersedia aksi ajukan ulang.
6. Setelah disetujui, sistem mengaktifkan entitlement POS secara server-side dan pemilik diarahkan ke checklist setup: outlet, produk, pajak, printer, user kasir, dan saldo awal.
7. Saat mendekati expiry, sistem menampilkan banner perpanjangan. Perpanjangan tidak menghapus histori dan tidak membuat dua subscription aktif yang tumpang tindih tanpa aturan yang jelas.
8. Setelah expired, halaman POS tidak boleh melakukan transaksi baru. Data histori dan export tetap read-only selama kebijakan retention berlaku; pemilik diarahkan ke halaman perpanjangan.

## Flow admin panel

Admin membuka **Admin → POS → Subscription** dan melihat tiga area utama: `Permintaan Review`, `Subscription Aktif`, dan `Katalog Paket & Konfigurasi`.

| Area | Kontrol wajib |
|---|---|
| Permintaan Review | Filter status/tanggal, detail merchant, paket, jumlah, bukti pembayaran, timeline, approve, reject dengan alasan wajib, dan audit actor. |
| Subscription Aktif | Status, expiry, trial/paid, merchant, outlet, perpanjang, suspend, reactivate, dan riwayat perubahan. |
| Katalog Paket | Nama, deskripsi fitur, harga, durasi, batas outlet/user, urutan tampil, status aktif, dan pencegahan menghapus paket yang masih dipakai. |
| Konfigurasi | Trial days, grace period, payment instructions, email/notification copy, dan kill switch POS. |

## Aturan entitlement

Route POS, menu POS, RPC checkout, dan operasi mutasi penting harus memeriksa entitlement yang sama. Record `ACTIVE` hanya dianggap aktif jika `expired_at` masih di masa depan, atau status berada pada trial/grace policy yang didefinisikan. Penyembunyian menu tidak dianggap sebagai enforcement keamanan.

## Temuan implementasi yang perlu ditutup

Repository saat ini memiliki dua model billing: `pos_subscriptions` untuk POS dan `merchant_subscriptions` untuk quota transaksi. Halaman `MerchantSubscriptionPage` masih memakai model quota lama, sedangkan `MerchantPOSSubscribePage`, `MerchantPOSPage`, dan `AdminPOSPage` memakai model POS. Label menu merchant masih `Kuota`, sehingga pemilik bisnis dapat salah memahami produk yang dibeli. Selain itu, approval admin langsung mengubah row subscription dari client tanpa lifecycle RPC, trial dan request pembayaran belum dilindungi oleh constraint/unique policy yang kuat, serta expiry belum memiliki grace/read-only behavior yang terdokumentasi pada UI.
