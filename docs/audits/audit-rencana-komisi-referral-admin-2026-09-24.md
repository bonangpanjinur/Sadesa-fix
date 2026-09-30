# Audit dan Rencana Implementasi Komisi Referral Admin

## Kesimpulan

Fondasi komisi verifikator untuk pembayaran subscription merchant sudah tersedia. Namun, mekanismenya masih melekat pada `group_commission_percent` di paket transaksi. Fondasi tersebut belum mencakup produk yang dijual langsung oleh admin kepada driver dan merchant, belum memiliki aturan komisi terpusat per sumber pendapatan, dan belum memiliki order penjualan yang mengikat pembeli dengan referral verifikator secara konsisten.

Perubahan ini memperluas sistem dengan empat komponen. Admin memiliki aturan komisi dinamis untuk transaksi layanan, penjualan kuota, penjualan produk kepada driver, dan penjualan produk kepada merchant. Admin memiliki katalog produk dengan target role, harga, dan stok. Driver dan merchant membuat order melalui RPC server-side. Setelah pembayaran dikonfirmasi admin, sistem mencatat earning verifikator yang memiliki referral pembeli. Nilai persentase disimpan sebagai snapshot sehingga histori tidak berubah ketika aturan berikutnya diedit.

## Temuan Audit

| Area | Temuan | Dampak |
|---|---|---|
| Komisi | Komisi subscription sebelumnya bergantung pada field paket transaksi. | Admin belum memiliki satu tempat untuk mengatur seluruh sumber komisi. |
| Penjualan admin | Belum ada katalog dan order khusus untuk jaket, box, atau barang operasional admin. | Driver dan merchant tidak memiliki alur pembelian terintegrasi. |
| Referral driver | Courier dapat menyimpan kode referral, tetapi atribusi earning produk belum tersedia. | Penjualan kepada driver belum menghasilkan earning verifikator. |
| Referral merchant | Merchant memiliki `verifikator_id` dan `verifikator_code`. | Data dapat dipakai untuk order produk admin setelah komisi dipusatkan. |
| Keamanan | Perhitungan komisi belum boleh dipercayakan kepada client. | Nilai earning harus dihitung dalam fungsi database dan dibatasi RLS. |
| Idempotensi | Konfirmasi pembayaran dapat dipanggil lebih dari sekali. | Earning ganda harus dicegah dengan unique index pada order penjualan. |

## Alur yang Diimplementasikan

1. Admin membuka **Toko & Komisi Referral**. Admin mengatur persentase untuk setiap sumber dan membuat katalog produk. Produk dapat ditujukan kepada semua role, driver saja, atau merchant saja.
2. Driver atau merchant membuka **Toko Perlengkapan** dari sidebar masing-masing. Client hanya meminta pembuatan order melalui `create_admin_store_order`.
3. RPC mengidentifikasi akun melalui `auth.uid()`, mengambil data courier atau merchant, mencari `verifikator_id` atau menyelesaikan `verifikator_code`, memeriksa role produk, memeriksa stok, lalu mengurangi stok secara atomik.
4. Order dibuat dengan status `WAITING_PAYMENT`. Admin melakukan verifikasi pembayaran secara operasional melalui tombol **Konfirmasi lunas**.
5. RPC `admin_mark_store_order_paid` mengubah order menjadi `READY_FOR_PICKUP`. RPC membaca aturan komisi aktif sesuai role pembeli dan membuat satu earning `PENDING` untuk referral verifikator.
6. Driver mengambil barang pada verifikator yang dipilih atau melalui prosedur pickup yang ditetapkan admin. Merchant dapat menggunakan alur yang sama untuk barang operasional.
7. Verifikator melihat earning berdasarkan sumber, nominal dasar, persentase snapshot, dan status payout. Earning tetap mengikuti lifecycle withdrawal yang telah ada.

## Kontrol Database

Tabel katalog, order, item order, dan aturan komisi menggunakan Row Level Security. Admin memiliki akses pengelolaan. Pembeli hanya dapat melihat order miliknya. Verifikator hanya dapat melihat order yang terkait sebagai referral atau pickup. Client tidak dapat memasukkan nominal komisi ke earning.

Fungsi database membatasi pembuatan order pada akun driver atau merchant yang terautentikasi. Fungsi pembayaran hanya dapat dipanggil oleh admin. Unique index pada `verifikator_earnings.sale_order_id` mencegah earning produk ganda jika konfirmasi diulang. Kolom identitas merchant, subscription, dan package pada earning dibuat nullable agar earning penjualan admin tidak dipaksa memiliki relasi subscription.

Komisi kuota tetap kompatibel dengan histori lama. Untuk pembayaran baru, trigger membaca aturan `QUOTA_SALE` terlebih dahulu dan menggunakan persentase paket sebagai fallback bila aturan tersebut belum tersedia. Dengan demikian, konfigurasi admin dapat mengendalikan penjualan kuota tanpa mengubah earning lama.

## Kriteria Penerimaan

- Admin dapat mengatur persentase dari 0 sampai 100 untuk setiap sumber komisi.
- Admin dapat membuat, mengaktifkan, menonaktifkan, dan mengisi stok produk.
- Produk dengan target `DRIVER` tidak dapat dibeli oleh merchant, dan sebaliknya.
- Driver atau merchant tanpa referral tidak membuat earning verifikator.
- Pembeli dengan referral membuat earning hanya setelah pembayaran ditandai lunas.
- Konfirmasi pembayaran berulang tidak membuat earning kedua.
- Verifikator melihat komisi produk driver, komisi produk merchant, komisi kuota, dan komisi transaksi pada halaman earning.
- Perubahan persentase baru tidak mengubah snapshot earning sebelumnya.
- Migrasi bersifat idempotent dan seluruh tabel baru memiliki RLS.

## Catatan Operasional

Implementasi ini menempatkan konfirmasi pembayaran pada admin karena integrasi payment gateway untuk katalog admin belum menjadi bagian dari alur yang tersedia. Status `READY_FOR_PICKUP` berarti pembayaran telah dicatat dan order siap diproses untuk pengambilan. Bukti pembayaran, serah terima barang, dan rekonsiliasi fisik tetap perlu mengikuti SOP admin.

Titik lanjutan yang disarankan adalah menambahkan pilihan daftar verifikator aktif pada checkout, notifikasi order ke verifikator pickup, serta integrasi payment gateway khusus katalog admin. Ketiga hal tersebut tidak diperlukan untuk perhitungan komisi inti dan dapat dikembangkan tanpa mengubah kontrak tabel earning.

## File Implementasi

- `archive/supabase/migrations/20260924150000_verifikator_admin_sales_commission.sql`
- `supabase/bootstrap/30_20260924150000_verifikator_admin_sales_commission.sql`
- `src/pages/admin/AdminVerifierCommercePage.tsx`
- `src/pages/StorePage.tsx`
- `src/pages/verifikator/VerifikatorEarningsPage.tsx`

## Referensi Repository

[1]: ../../src/pages/admin/AdminVerifierCommercePage.tsx "Dashboard toko dan komisi admin"
[2]: ../../src/pages/StorePage.tsx "Toko driver dan merchant"
[3]: ../../archive/supabase/migrations/20260924150000_verifikator_admin_sales_commission.sql "Migrasi komisi referral dan penjualan admin"
[4]: audit-penghasilan-verifikator-2026-09-24.md "Audit earning verifikator sebelumnya"
