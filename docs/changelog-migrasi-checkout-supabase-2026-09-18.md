# Changelog Migration Supabase — Checkout Hardening

**Tanggal:** 18 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Branch:** `main`  
**Author:** `bopan86 <bopan86@gmail.com>`  
**Migration terkait:** `86_20260918220000_checkout_idempotency_and_payment_guard.sql` dan `87_20260918230000_checkout_p1_hardening.sql`

## Ringkasan

Migration ini memperkuat checkout marketplace pada empat area utama: **idempotensi checkout**, **pembatasan checkout multi-merchant**, **konsistensi reservation stok dengan status pembayaran**, dan **mutasi bukti transfer yang scoped berdasarkan buyer**.

Perubahan dirancang sebagai migration tambahan dan tidak mengubah file migration sebelumnya. Migration `87` melanjutkan dan memperketat kontrak yang diperkenalkan migration `86`.

## Daftar perubahan

### 1. Tabel idempotensi checkout

Migration `86` menambahkan tabel `public.marketplace_checkout_idempotency` dengan kolom berikut:

| Kolom | Tipe | Keterangan |
| --- | --- | --- |
| `user_id` | `uuid` | Buyer pemilik checkout; foreign key ke `auth.users` |
| `checkout_key` | `text` | Key unik untuk satu attempt checkout |
| `result` | `jsonb` | Hasil authoritative checkout yang dikembalikan saat retry |
| `created_at` | `timestamptz` | Waktu penyimpanan hasil |

Primary key tabel adalah `(user_id, checkout_key)`. RLS diaktifkan dan akses langsung untuk `PUBLIC`, `anon`, dan `authenticated` dicabut. Tabel hanya diakses oleh fungsi `SECURITY DEFINER` checkout.

### 2. Checkout authoritative dengan idempotency key

Signature baru yang digunakan buyer adalah:

```sql
public.create_marketplace_checkout(
  jsonb,
  jsonb,
  text,
  text,
  uuid,
  numeric,
  text
)
```

Parameter terakhir adalah `p_checkout_key`. Fungsi melakukan hal berikut:

1. Memastikan request berasal dari user terautentikasi.
2. Memvalidasi panjang key antara 16 dan 128 karakter.
3. Mengunci attempt menggunakan `pg_advisory_xact_lock` berdasarkan user dan key.
4. Mengembalikan hasil tersimpan apabila key sudah pernah berhasil.
5. Menjalankan checkout authoritative hanya untuk key baru.
6. Menyimpan hasil checkout ke `marketplace_checkout_idempotency`.

Dengan mekanisme ini, double-click atau retry request dengan key yang sama tidak membuat order dan reservation baru.

### 3. Penutupan signature checkout lama

Migration `87` mencabut akses role `authenticated` dan `anon` ke signature checkout lama:

```sql
public.create_marketplace_checkout(
  jsonb,
  jsonb,
  text,
  text,
  uuid,
  numeric
)
```

Signature lama hanya dapat dipanggil oleh `service_role`. Buyer wajib menggunakan signature tujuh parameter yang memiliki idempotency key dan guard server-side.

### 4. Pembatasan satu merchant per checkout

Migration `87` menolak checkout apabila payload berisi produk dari lebih dari satu merchant, tanpa membedakan metode pembayaran. Pesan error authoritative adalah:

```text
Checkout hanya tersedia untuk satu toko dalam satu transaksi
```

Perubahan ini mencegah perbedaan antara total preview dan child order server, terutama pada ongkir dan biaya COD yang sebelumnya dapat dihitung per merchant.

Dampaknya adalah cart multi-merchant harus dipisahkan menjadi beberapa checkout terpisah.

### 5. Guard provider pembayaran online

Untuk `p_payment_method = 'ONLINE'`, fungsi checkout membaca:

```text
app_settings.key = 'payment_xendit'
```

Checkout ditolak jika `value.enabled` tidak bernilai `true`. Dengan demikian, order `ONLINE` tidak lagi dapat dibuat ketika provider belum aktif atau sedang dinonaktifkan.

### 6. Konsumsi stok saat pembayaran menjadi PAID

Migration `87` menambahkan trigger:

```text
trg_consume_marketplace_stock_on_payment
```

Trigger menjalankan fungsi `consume_marketplace_stock_reservation(order_id)` saat `orders.payment_status` berubah menjadi `PAID`.

Perubahan ini berlaku untuk jalur pembayaran tepercaya, termasuk:

- Webhook pembayaran online.
- Verifikasi transfer oleh merchant.

Konsumsi reservation bersifat idempotent. Jika reservation sudah berstatus `consumed`, fungsi reservation mengembalikan hasil duplicate tanpa mengurangi stok dua kali.

### 7. Perlindungan dari pembayaran setelah reservation expired

Trigger pembayaran memeriksa status reservation sebelum konsumsi. Jika reservation sudah berstatus `expired` atau `released`, perubahan order menjadi `PAID` ditolak dengan error:

```text
Payment cannot complete after stock reservation expiry
```

Tujuannya adalah mencegah order menjadi paid ketika stok sudah dilepas dan tidak lagi tersedia untuk order tersebut.

### 8. Perbaikan expiry reservation

Migration `87` mengganti fungsi:

```sql
public.expire_marketplace_stock_reservations(integer)
```

Expiry worker sekarang hanya memilih reservation aktif yang order-nya belum berstatus `PAID`. Reservation dari order yang sudah dibayar tidak boleh dilepas oleh cleanup unpaid reservation.

Akses fungsi tetap dibatasi untuk `service_role`.

### 9. RPC scoped untuk bukti transfer

Migration `87` menambahkan fungsi:

```sql
public.buyer_submit_payment_proof(
  p_order_id uuid,
  p_payment_proof_url text
)
```

Fungsi tersebut:

- Memastikan user sudah login.
- Memastikan order dimiliki oleh buyer yang sedang login.
- Memastikan metode pembayaran adalah `TRANSFER`.
- Menolak order yang sudah `PAID`, `REFUNDED`, `EXPIRED`, `CANCELLED`, `CANCELED`, atau `REJECTED`.
- Mengunci order dengan `FOR UPDATE`.
- Menyimpan URL bukti pembayaran secara scoped.

Akses diberikan hanya kepada role `authenticated`. Client tidak lagi melakukan `UPDATE orders` langsung.

### 10. Cleanup file bukti transfer

Frontend sekarang mengunggah file terlebih dahulu, kemudian memanggil `buyer_submit_payment_proof`. Jika RPC gagal, client mencoba menghapus file yang baru diunggah untuk mengurangi orphan object pada bucket `payment-proofs`.

## Dampak kompatibilitas

| Area | Dampak |
| --- | --- |
| RPC checkout buyer | Client wajib mengirim `p_checkout_key` |
| Checkout multi-merchant | Tidak lagi diizinkan; produk harus dipisah per toko |
| Checkout online | Membutuhkan `payment_xendit.value.enabled = true` |
| Reservation | Reservation paid dikonsumsi saat payment status menjadi `PAID` |
| Payment proof | Client harus memakai RPC `buyer_submit_payment_proof` |
| Direct update `orders` | Tetap tidak diizinkan untuk buyer |
| Service worker expiry | Harus berjalan dengan role `service_role` |

## Urutan penerapan

Migration harus diterapkan berurutan setelah migration checkout authoritative dan reservation lifecycle yang menjadi dependensinya:

1. Terapkan `86_20260918220000_checkout_idempotency_and_payment_guard.sql`.
2. Terapkan `87_20260918230000_checkout_p1_hardening.sql`.
3. Reload schema cache PostgREST jika deployment Supabase tidak melakukannya otomatis.
4. Pastikan edge function payment dan webhook telah dideploy bersama source aplikasi.
5. Pastikan worker atau scheduler expiry dijalankan menggunakan `service_role`.

Kedua file tersedia pada source migration dan bootstrap:

```text
supabase/migrations/20260918220000_checkout_idempotency_and_payment_guard.sql
supabase/migrations/20260918230000_checkout_p1_hardening.sql
supabase/bootstrap/86_20260918220000_checkout_idempotency_and_payment_guard.sql
supabase/bootstrap/87_20260918230000_checkout_p1_hardening.sql
```

## Konfigurasi yang perlu diverifikasi

Sebelum mengaktifkan checkout online, pastikan `app_settings` memiliki konfigurasi aktif berikut:

```json
{
  "key": "payment_xendit",
  "value": {
    "enabled": true
  }
}
```

Nilai `enabled` harus konsisten dengan secret provider dan edge function Xendit yang sudah dideploy.

## Verifikasi setelah deployment

Setelah migration diterapkan pada staging, jalankan pemeriksaan berikut:

1. Pastikan signature checkout lama gagal untuk role `authenticated`.
2. Pastikan signature checkout baru dengan key yang sama mengembalikan `primary_order_id` yang sama.
3. Pastikan cart dua merchant ditolak sebelum order dibuat.
4. Pastikan checkout online ditolak ketika `payment_xendit.enabled = false`.
5. Pastikan perubahan payment status menjadi `PAID` mengonsumsi reservation tepat satu kali.
6. Pastikan expiry worker tidak melepas reservation dari order `PAID`.
7. Pastikan pembayaran setelah reservation expired ditolak.
8. Pastikan buyer hanya dapat mengirim bukti transfer untuk order miliknya.
9. Pastikan order `PAID`, `REFUNDED`, dan `CANCELLED` menolak bukti transfer baru.
10. Pastikan upload file yang RPC-nya gagal tidak meninggalkan object tanpa kontrol.

## Verifikasi repository

Pada saat changelog ini dibuat, pemeriksaan repository menghasilkan:

- ESLint file checkout terkait: **lulus**.
- Test suite: **65 test files lulus; 238 test lulus; 20 skipped**.
- Production build: **lulus**.
- Bootstrap bundle validation: **lulus**.
- `git diff --check`: **lulus**.

Pengujian concurrency pada database aktif dan transaksi nyata dengan provider pembayaran tetap harus dilakukan pada staging.

## Referensi

[1]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/supabase/migrations/20260918220000_checkout_idempotency_and_payment_guard.sql "Checkout idempotency and payment guard migration"
[2]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/supabase/migrations/20260918230000_checkout_p1_hardening.sql "Checkout P1 hardening migration"
[3]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/supabase/functions/xendit-webhook/index.ts "Xendit payment webhook"
[4]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/supabase/functions/xendit-payment/index.ts "Xendit invoice edge function"
