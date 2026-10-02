# Tahap 1 — Migration dan RPC Guest Checkout

Migration tahap 1 ditambahkan sebagai bundle forward-only:

- `supabase/bootstrap/65_20261002170000_guest_checkout_phase1.sql`
- Entry dan checksum bundle diperbarui di `supabase/bootstrap/manifest.json`.

## Kontrak database

- `orders.buyer_id` dan `marketplace_stock_reservations.buyer_id` sekarang nullable untuk order guest.
- Order guest wajib memiliki `guest_access_token_hash`; constraint identitas dibuat `NOT VALID` agar migration tidak gagal pada data historis yang perlu dibersihkan/ditinjau terpisah.
- Token guest dibuat dengan `gen_random_bytes(32)`, dikodekan hex, dan hanya hash SHA-256 yang disimpan.
- Token berlaku 30 hari dan memiliki unique index serta index expiry.
- `marketplace_guest_checkout_idempotency` menyimpan hash session guest + checkout key, bukan token mentah.

## RPC

| RPC | Role | Fungsi |
|---|---|---|
| `create_guest_marketplace_checkout(...)` | `anon` | Validasi server-side produk, merchant, stok, satu merchant, metode transfer/online, provider online, ongkir, dan membuat order + reservation. |
| `get_guest_order_status(uuid, text)` | `anon` | Membaca data minimum order/items berdasarkan order ID + token valid dan belum kedaluwarsa. |
| `guest_submit_payment_proof(uuid, text, text)` | `anon` | Mengubah bukti transfer hanya setelah token dan status order diverifikasi. |
| `reserve_marketplace_stock_guest(...)` | internal | Reservation scoped ke order guest + token; tidak diekspos ke role aplikasi. |

Guest tidak mendapat akses langsung ke tabel order, order items, reservation, atau tabel idempotensi.

## Batasan tahap 1

- Frontend belum dialihkan ke RPC guest; perubahan `CartPage`, `CheckoutPage`, route status, dan payment UI masuk tahap 2–3.
- Claim order setelah login belum dibuat.
- Upload proof masih membutuhkan integrasi storage token-scoped pada tahap 3; RPC menerima URL yang sudah dihasilkan oleh flow terproteksi.
- Retry idempotent mengembalikan hasil tersimpan tanpa menyimpan token mentah di database. Client tahap 2 harus mempertahankan token hasil submit pertama di storage/link status.
- Rate limiting RPC berdasarkan session/IP perlu dipasang pada edge/server layer sebelum rollout publik.

## Deployment dan rollback

1. Validasi bundle dan review diff.
2. Terapkan bundle melalui prosedur migration resmi Supabase; jangan replay bundle terhadap production secara manual.
3. Reload schema cache PostgREST bila deployment tidak otomatis melakukannya.
4. Deploy frontend hanya setelah RPC staging lulus.
5. Rollback operasional dilakukan dengan feature flag guest checkout; kolom guest tidak dihapus tanpa prosedur retention/audit.

## Test matrix staging wajib

- Role `anon` dapat memanggil checkout guest valid; direct `SELECT/INSERT/UPDATE` tabel sensitif ditolak.
- Token valid dapat membaca order sendiri; order ID saja, token invalid, token expired, dan token order lain ditolak dengan error generik.
- Guest checkout transfer dan online (provider aktif) berhasil; online saat provider nonaktif ditolak.
- COD, voucher akun, cart kosong, data kontak invalid, merchant tutup, produk tidak aktif, stok kurang, dan cart multi-merchant ditolak.
- Retry dengan session hash + checkout key sama tidak membuat order/reservation kedua.
- Reservation guest direlease/expired sesuai lifecycle; pembayaran setelah reservation expired tidak boleh menjadi paid.
- Bukti transfer hanya dapat ditambahkan untuk order guest TRANSFER yang valid dan belum final.
- User login checkout lama tetap lulus.
