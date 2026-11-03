# GDC QRIS Dynamic Payment

Implementasi Fase 1–3 QRIS dinamis Sadesa menggunakan provider **GDC**.

## Komponen

- Migration: `supabase/bootstrap/134_20261031220000_gdc_qris_dynamic_payment.sql`
- Edge Function: `supabase/functions/gdc-qris-payment/index.ts`
- Konfigurasi function: `supabase/config.toml`
- Client contract: `src/lib/gdcQrisApi.ts`
- Admin profile UI: `src/pages/admin/AdminQrisApplicationsPage.tsx`

## Model data

`gdc_payment_profiles` menyimpan identifier per merchant:

- `provider_merchant_id`: nilai yang dikirim sebagai `merchantId`.
- `provider_account_number`: nilai yang dikirim sebagai `additionalInfo.accountNumber`.
- `nmid`: identifier operasional terpisah; tidak otomatis dipakai sebagai `merchantId`.
- `store_id`, `terminal_id`, `service_code`: optional sampai diwajibkan oleh kontrak GDC.
- `status`: `PENDING_VALIDATION`, `ACTIVE`, atau `SUSPENDED`.

`gdc_qris_payment_attempts` menyimpan transaksi per order, termasuk `partner_reference_no`, reference provider, QR response, expiry, provider status, dan state internal:

`CREATING`, `PENDING`, `SUCCEEDED`, `FAILED`, `EXPIRED`, `UNKNOWN`.

`qris_applications` tetap khusus untuk onboarding/KYC dan penerbitan QRIS merchant. `merchants.qris_image_url` tetap merupakan aset QRIS merchant, bukan QR dinamis per order.

## Edge Function actions

### Generate

```text
POST /functions/v1/gdc-qris-payment/generate
Authorization: Bearer <Supabase access token>
Idempotency-Key: gdc-qris:<order-id>

{"order_id":"<order-id>"}
```

Backend mengambil amount dan merchant dari order, mencari profile GDC aktif, melakukan reservation idempotent, lalu mengirim request generate ke GDC.

Default path provider:

```text
/v1.0/qr/qr-mpm-generate
```

### Query

```text
POST /functions/v1/gdc-qris-payment/query
Authorization: Bearer <Supabase access token>

{"attempt_id":"<attempt-id>"}
```

Backend memvalidasi bahwa attempt milik order user yang sedang login, memanggil query GDC, lalu memproses status ke RPC atomic.

Default path provider:

```text
/v1.0/qr/qr-mpm-query
```

### Callback

```text
POST /functions/v1/gdc-qris-payment/callback
X-Callback-Token: <configured token>
```

Callback tidak memerlukan JWT user. Handler mencari attempt menggunakan `partnerReferenceNo`, lalu memproses status dan mengubah order hanya setelah amount cocok. Daftarkan callback hanya jika GDC mengonfirmasi bahwa callback tersebut memang berlaku untuk QRIS MPM.

## Function secrets

Nilai berikut harus disimpan sebagai Supabase Edge Function Secrets, bukan `VITE_*`, database settings yang terbaca admin, atau file repository:

```text
GDC_API_BASE_URL
GDC_PARTNER_ID                  # optional, jika diwajibkan GDC
GDC_ACCESS_TOKEN                # optional, jika diwajibkan GDC
GDC_SIGNATURE_SECRET            # required bila mode signature bukan none
GDC_SIGNATURE_MODE              # default: hmac_sha256; gunakan none hanya untuk sandbox yang memang tidak memakai signature
GDC_GENERATE_PATH               # optional override
GDC_QUERY_PATH                  # optional override
GDC_SERVICE_CODE                # optional default service code
GDC_CALLBACK_TOKEN              # required untuk callback
GDC_TIMEOUT_MS                  # optional, default 15000
```

Implementasi saat ini menggunakan signature HMAC-SHA256 atas string `<ISO timestamp>.<raw JSON body>` dan mengirimkannya pada `X-Signature`. Header dan formula ini **harus dikonfirmasi terhadap profil API GDC** sebelum production. Jika GDC memakai formula SNAP/HTTP signature lain, ubah adapter `gdcRequest` tanpa mengubah database atau handler lifecycle.

## Deployment order

1. Terapkan migration bundle melalui workflow staging repository. Jangan menganggap merge SQL otomatis menerapkan schema.
2. Set Function Secrets pada project Supabase staging.
3. Deploy function:

```sh
supabase functions deploy gdc-qris-payment --project-ref "$SUPABASE_PROJECT_REF"
```

4. Masukkan profile GDC melalui halaman admin QRIS dengan status `PENDING_VALIDATION`.
5. Setelah identifier diverifikasi terhadap merchant sandbox, ubah status menjadi `ACTIVE`.
6. Jalankan generate, query, callback, duplicate, timeout, amount mismatch, dan cross-merchant tests.
7. Baru setelah UAT, daftarkan callback production dan aktifkan merchant pilot.

## Batas kesiapan

Fase 1–3 sudah memiliki implementasi source dan guard dasar, tetapi belum boleh dianggap production-ready sebelum GDC mengonfirmasi:

- mapping `merchantId` dan `accountNumber`;
- formula signature dan header authentication;
- status final serta kode sukses/gagal/pending;
- callback QRIS MPM atau kewajiban polling;
- masa berlaku QR dan aturan retry/duplicate reference;
- sandbox merchant serta contoh response resmi.

## Fase 4 — checkout dan UX pembayaran

Checkout menggunakan `payment_method = ONLINE` yang sudah didukung schema existing, sedangkan provider dipilih di server flow berdasarkan profil GDC aktif merchant. Jika profil GDC aktif, checkout mengarahkan buyer ke `/payment/gdc/:orderId/:attemptId`. Jika tidak aktif, flow online existing Xendit tetap digunakan.

Halaman QRIS GDC menampilkan QR image/provider URL atau merender `qr_content` menjadi QR SVG. Status di-query setiap 5 detik sampai `SUCCEEDED`, `FAILED`, atau `EXPIRED`. QR dan provider reference tidak dimasukkan ke URL; URL hanya membawa order dan attempt UUID.

## Fase 5 — pilot rollout dan observability

Migration `135_20261031230000_gdc_qris_rollout_observability.sql` menyediakan event telemetry tanpa menyimpan request/response payload provider:

- generate started/succeeded/failed;
- query succeeded/failed;
- callback processed/rejected;
- HTTP status provider, duration, internal status, dan error code terbatas.

Admin dapat mengambil agregat 24 jam melalui:

```sql
select public.get_gdc_qris_rollout_metrics(now() - interval '24 hours');
```

Gate pilot yang disarankan:

1. mulai dari 1 merchant dengan profile `ACTIVE` dan sandbox credential;
2. verifikasi generate success, QR scan, query, callback, duplicate request, amount mismatch, timeout, dan expired;
3. lanjut hanya bila tidak ada duplicate payment, reconciliation gap, callback rejection yang tidak terjelaskan, atau critical incident;
4. perluas merchant secara bertahap setelah finance reconciliation dan support readiness disetujui;
5. rollback dengan mengubah profile GDC menjadi `SUSPENDED`; checkout otomatis kembali ke provider online existing atau transfer sesuai konfigurasi merchant.

Acceptance contract tersedia di `src/lib/gdcQrisAcceptance.test.ts`.
