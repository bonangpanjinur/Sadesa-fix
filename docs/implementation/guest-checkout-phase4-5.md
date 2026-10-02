# Guest Checkout — Tahap 4 dan 5

## Tahap 4 — Testing dan hardening

### Test yang ditambahkan

| Area | Skenario | Coverage |
|---|---|---|
| Guest form/rollout | Flag malformed, off, pilot allowlist, persentase deterministik | `src/lib/guestCheckoutFeature.test.ts` |
| Token/session | Refresh, expiry, token salah, order lain, storage isolation | `src/lib/guestCheckout.test.ts` |
| RPC/security | Token hash, expiry, generic error, anon grant hanya ke RPC, proof path scoped | `src/test/guestCheckoutSecurity.test.ts` |
| Checkout regression | CTA guest, status/payment route, cart shipping i18n | `src/pages/CartPage.i18n.test.tsx` dan contract tests |
| Mobile | Layout memakai `mobile-shell`, action bar memakai safe-area class | `CartPage`, `CheckoutPage`, `GuestOrderStatusPage`, `PaymentConfirmationPage` |

### Validasi lokal

```bash
pnpm exec tsc --noEmit
pnpm test
pnpm exec eslint src/App.tsx src/lib/guestCheckout.ts src/lib/guestCheckoutFeature.ts src/hooks/useGuestCheckoutEnabled.ts src/pages/CartPage.tsx src/pages/CheckoutPage.tsx src/pages/GuestOrderStatusPage.tsx src/pages/PaymentConfirmationPage.tsx src/test/guestCheckoutSecurity.test.ts
pnpm build
pnpm validate:migrations
pnpm validate:db-bootstrap
pnpm audit:rls
```

Integration test terhadap database staging dijalankan hanya bila `SUPABASE_TEST_URL` dan key test tersedia. Tanpa environment tersebut test staging harus skip, bukan menggunakan database production.

### Security hardening

- Flag gagal dibaca atau formatnya tidak dikenal berarti guest checkout **off**.
- Token order tetap hanya dikembalikan RPC saat order dibuat; database hanya menyimpan hash.
- Status dan bukti transfer harus membawa kombinasi `order_id + token`.
- Role `anon` tidak mendapat SELECT/UPDATE langsung pada `orders` atau `order_items`.
- Storage proof mensyaratkan path `orders/<order-id>/<sha256-token>/...` dan token belum expired.
- Session key dan cache access guest disimpan di `sessionStorage`, tidak di `localStorage`.
- Pesan invalid/expired/cross-order bersifat generik.

## Tahap 5 — Rollout bertahap

Migration `67_20261002200000_guest_checkout_rollout_flag.sql` membuat setting berikut jika belum ada:

```json
{
  "enabled": false,
  "rollout_percent": 0,
  "pilot_user_ids": []
}
```

`pilot_user_ids` berisi guest session key yang diizinkan untuk pilot. Untuk rollout persentase, assignment memakai bucket deterministik dari session key sehingga refresh tidak memindahkan user ke cohort lain.

### Urutan deployment

1. Terapkan bootstrap/migration database **65, 66, lalu 67**.
2. Deploy frontend dengan flag tetap `enabled=false`.
3. Jalankan test staging untuk guest checkout, retry, stok berubah, toko tutup, token invalid/expired, cross-order, refresh, dan mobile viewport.
4. Masukkan session pilot ke `pilot_user_ids`, atau set `rollout_percent` kecil seperti `1`–`5`.
5. Pantau minimal satu siklus operasional penuh.
6. Naikkan persentase bertahap ke `10`, `25`, `50`, lalu `100` setelah metrik stabil.
7. Aktifkan penuh dengan `{"enabled":true,"rollout_percent":100,"pilot_user_ids":[]}`.

### Operasional dan alert

Pantau per cohort guest dan authenticated:

- checkout success/error rate;
- duplicate order atau retry idempotency conflict;
- stock reservation failure dan mismatch stok;
- payment/proof upload failure;
- status lookup invalid/expired rate;
- rate-limit rejection dan token abuse;
- waktu dari checkout ke payment proof/paid;
- error frontend pada `/checkout`, `/guest-order(s)`, dan `/payment/:orderId`.

Jangan mencatat token mentah, nama, nomor telepon, atau alamat lengkap pada log/telemetry.

### Rollback

Rollback normal dilakukan tanpa menghapus data:

```sql
UPDATE public.app_settings
SET value = '{"enabled":false,"rollout_percent":0,"pilot_user_ids":[]}'::jsonb,
    updated_at = now()
WHERE key = 'guest_checkout_enabled';
```

Frontend kemudian mengarahkan guest baru ke `/auth`, sementara user login tetap dapat checkout. Link/order guest yang sudah dibuat tidak dihapus; status dan retention mengikuti kebijakan data. Jangan rollback migration schema atau menghapus hash token sebagai langkah pertama.

## Gate rilis

Tahap 5 dinyatakan siap hanya jika:

- seluruh unit test, TypeScript, lint, build, migration validator, dan RLS audit lulus;
- migration 65–67 diterapkan di staging;
- tidak ada akses tabel langsung untuk role `anon`;
- retry checkout tidak membuat order ganda;
- cohort pilot stabil sebelum persentase dinaikkan;
- rollback flag diuji dan mengembalikan guest ke login.
