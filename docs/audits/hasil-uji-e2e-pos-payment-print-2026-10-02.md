# Hasil Uji E2E Pembayaran POS dan Kesiapan Print — 2 Oktober 2026

## Ringkasan status

| Area | Hasil | Batas verifikasi |
|---|---|---|
| Alur kasir → pembayaran → RPC checkout → status tersinkron → kontrak struk | **Lulus, 2/2 skenario simulasi** | RPC Supabase dan outbox printer dimock; bukan transaksi di staging/live. |
| Regresi pembayaran dan print | **Lulus, 21/21 tes terarah** | Unit/component tests; tidak mengirim pembayaran atau pekerjaan ke printer nyata. |
| Suite lengkap | **Lulus: 392 passed; 20 skipped (412 total)** | 101 file tes. Skip merupakan skenario integrasi yang membutuhkan konfigurasi eksternal. |
| Suite integrasi POS/staging | **4 passed; 20 skipped** | Kredensial/fixture staging tidak tersedia, jadi backend Supabase nyata tidak disentuh. |
| TypeScript, ESLint, sintaks Print Bridge | **Lulus** | `tsc --noEmit`, lint berkas yang diubah, dan `node --check` server bridge. |
| Bridge/printer fisik | **Belum siap diverifikasi di sandbox** | `http://127.0.0.1:18181/health` menolak koneksi; tidak ada printer fisik yang terhubung. |

## Cakupan E2E lokal yang dijalankan

Tes baru `src/test/pos-payment-e2e.test.tsx` merender halaman kasir POS dan memakai UI aslinya untuk memilih produk, membuka dialog pembayaran, serta menyelesaikan pembayaran tunai. Alur yang dilalui:

1. Kasir menambahkan satu produk Rp10.000 ke keranjang dan memulai pembayaran.
2. Halaman membuat checkpoint checkout lokal sebelum RPC.
3. Fungsi checkout yang sebenarnya memanggil RPC `process_pos_sale` dengan tenant, outlet, kasir, satu item, nominal bayar, dan kembalian yang diharapkan.
4. Respons simulasi menandai penjualan tersinkron dan membersihkan checkpoint.
5. Tombol **Cetak Struk** memanggil hook/kontrak struk sebenarnya; outbox dibuat dan flush disimulasikan berhasil.
6. Skenario kedua mensimulasikan timeout RPC lalu retry; `p_request_key` yang sama dipakai kembali agar tidak membuat transaksi duplikat.

**Batas penting:** ini adalah E2E UI/client dengan RPC dan perangkat cetak tersimulasi. Tes tidak menghubungi Supabase, payment gateway QRIS/transfer, bridge lokal, atau printer fisik. Jangan mengartikan hasil simulasi sebagai bukti settlement dana atau kesiapan hardware.

## Audit fitur print

- Pengaturan merchant menyediakan **Simpan & Test Print** dan opsi **Cetak Otomatis Setelah Transaksi**.
- Kode kasir mengirim cetak otomatis saat pengaturan aktif; kontrak struk menyimpan job ke outbox sebelum mencoba printer, sehingga job dapat diantrikan/retry tanpa membuat penjualan baru.
- Jalur Print Bridge memakai loopback `127.0.0.1:18181` secara default dan memeriksa health serta printer default. Server bridge juga membatasi CORS; jangan mengekspos service lokal tersebut ke internet.
- Tes yang lulus mencakup client bridge, kontrak receipt/outbox, Android print service, QR print, dan jalur UI pembayaran. Seluruh keluaran printer dalam tes diisolasi/mock.
- Pemeriksaan aktual health endpoint gagal tersambung (tidak ada service yang berjalan di sandbox). Karena itu koneksi ke printer, konfigurasi printer default, pemotongan kertas, ukuran 58/80 mm, jumlah salinan, header/footer, dan kualitas cetak **belum diuji secara fisik**.

## Perbaikan dari temuan pengujian

E2E pertama kali menemukan bahwa dialog sukses pembayaran belum memiliki title/description yang dikenali screen reader. `POSKasirPage` kini menggunakan `DialogTitle` dan `DialogDescription` untuk status sukses/offline. E2E diulang sesudah perubahan; 2/2 skenario lulus tanpa warning aksesibilitas dialog.

## Pemeriksaan backend statis

Migrasi checkout memvalidasi identitas kasir/outlet, request key dengan panjang minimum, item nonkosong, metode bayar yang diizinkan, serta mengembalikan respons lama sebagai `duplicate` saat request key yang sama dikirim ulang. Trigger pembayaran memeriksa uang tunai (`payment_amount ≥ total`, kembalian sama dengan selisih) dan metode non-tunai/split (nominal tepat sama dengan total, kembalian nol). Pemeriksaan ini berasal dari pembacaan migrasi yang ada; migrasi tidak dieksekusi pada database staging dalam tugas ini.

## Langkah UAT sebelum menyatakan printer siap merchant

1. Pada komputer kasir, jalankan Print Bridge dan pastikan `/health` menjawab `ok: true` serta printer default terdaftar.
2. Dari pengaturan POS, simpan konfigurasi dan lakukan **Test Print** pada printer yang benar-benar dipakai.
3. Uji struk transaksi pada lebar 58 mm dan/atau 80 mm yang dipilih, salinan, header/footer, reprint, auto-print, popup/browser fallback, serta job gagal yang masuk antrean dan bisa dicoba ulang.
4. Pada database staging terisolasi, ulangi pembayaran tunai, split, pembayaran non-tunai dengan konfirmasi eksternal yang sesuai, kegagalan/timeout RPC dan retry, dan pastikan hanya satu penjualan tercatat.
5. Cocokkan total/kembalian dengan transaksi dan laporan kasir, lalu pastikan status print tidak keliru menandai job yang hanya queued sebagai printed.

**Kesimpulan:** jalur client POS dan kontrak print lulus pengujian otomatis lokal. Kesiapan produksi untuk backend nyata dan printer fisik **belum dapat dinyatakan lulus** sampai UAT staging dan tes cetak hardware di atas dijalankan.