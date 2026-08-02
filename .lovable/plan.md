# Perbaikan Setelah Uji SQL

## Temuan dari inspeksi database

| Temuan | Dampak |
|---|---|
| Tabel `user_roles` kosong (0 baris) padahal ada 2 akun terdaftar | Belum ada admin — panel admin & fitur berbasis role tidak bisa diakses |
| Trigger ganda di `merchants`: `auto_assign_merchant_to_group` terpasang 2x (`auto_assign_merchant_to_group` + `trigger_auto_assign_merchant_group`) | Logika grup dijalankan dobel setiap insert/update merchant |
| Trigger ganda di `saved_addresses`: `set_saved_addresses_updated_at` + `update_saved_addresses_updated_at` | Redundan, dua fungsi menulis kolom yang sama |
| `orders` = 0 dan `reviews` = 0 | Halaman Pesanan, Rating, Pesan Lagi, Chat, dan Lacak Pengiriman belum bisa diuji |

Yang sudah aman (terverifikasi): semua tabel `public` punya RLS aktif, minimal satu policy, dan GRANT untuk `authenticated` + `service_role`; semua fungsi sudah memiliki `search_path`; trigger `on_auth_user_created` terpasang di `auth.users` sehingga akun baru otomatis dapat profil + role buyer. 103 warning linter yang tersisa adalah bucket publik untuk katalog dan fungsi SECURITY DEFINER — sudah didokumentasikan sebagai by design.

## Rencana Perbaikan

### 1. Backfill role akun yang ada (perubahan data)
- `bpanjinur63@gmail.com` → role `admin` + `buyer`
- `desakorup@gmail.com` → role `buyer`

### 2. Bersihkan trigger duplikat (migrasi SQL)
- Hapus `trigger_auto_assign_merchant_group` di `merchants` (sisakan satu)
- Hapus `set_saved_addresses_updated_at` di `saved_addresses` (sisakan `update_saved_addresses_updated_at`)

### 3. Seed data dummy transaksi (perubahan data)
- 4 order milik `bpanjinur63@gmail.com` dengan status berbeda: `DONE`, `SENT`, `PROCESSED`, `CANCELED`, masing-masing lengkap dengan `order_items` dari produk yang ada
- 1 order `DONE` milik `desakorup@gmail.com`
- 3 review bintang 4–5 pada order `DONE` agar `rating_avg`/`rating_count` merchant terisi lewat trigger yang sudah ada
- Nilai total dihitung konsisten: subtotal produk + ongkir, sesuai aturan bahwa pendapatan merchant hanya subtotal produk

### Catatan teknis
Langkah 2 dijalankan sebagai satu migrasi SQL (`DROP TRIGGER IF EXISTS`, idempotent). Langkah 1 dan 3 adalah operasi data murni, bukan perubahan skema. Setelah seed, halaman Pesanan/Rating/Pesan Lagi diverifikasi lewat query ulang untuk memastikan trigger rating benar-benar mengisi kolom rating merchant.
