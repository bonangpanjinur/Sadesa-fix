# Dokumentasi Teknis QRIS Dinamis GDC

**Repository:** Sadesa-fix
**Branch implementasi:** `qr_app2`
**Provider:** GDC
**Status:** Source implementation Fase 1–5 selesai; staging/production deployment menunggu konfigurasi dan verifikasi kontrak API GDC.

## 1. Ringkasan

Fitur ini menyediakan pembayaran QRIS dinamis per order melalui provider GDC. QR yang ditampilkan kepada buyer dibuat khusus untuk satu transaksi, memiliki nominal order, reference number unik, serta status pembayaran yang dapat dipantau melalui polling atau callback provider.

Implementasi dirancang agar tetap kompatibel dengan flow payment existing:

- `payment_method` order tetap menggunakan nilai `ONLINE` yang sudah didukung repository;
- provider GDC dipilih hanya jika profil GDC merchant berstatus `ACTIVE`;
- jika profil GDC tidak aktif atau tidak tersedia, flow online existing Xendit tetap menjadi fallback;
- QRIS statis merchant pada `merchants.qris_image_url` tetap dipisahkan dari QR dinamis per order.

## 2. Ruang lingkup fase

### Fase 1 — Profil merchant GDC

Fase ini menyediakan data identifier GDC per merchant dan UI admin untuk mengelolanya.

Data yang disimpan pada `gdc_payment_profiles`:

| Field | Keterangan |
|---|---|
| `provider_merchant_id` | Identifier merchant yang dikirim sebagai `merchantId` ke GDC. |
| `provider_account_number` | Account number yang dikirim pada `additionalInfo.accountNumber`. |
| `nmid` | NMID, disimpan terpisah dan tidak otomatis dipakai sebagai `merchantId`. |
| `store_id` | Store identifier opsional. |
| `terminal_id` | Terminal identifier opsional. |
| `service_code` | Service code opsional sesuai kontrak GDC. |
| `status` | `PENDING_VALIDATION`, `ACTIVE`, atau `SUSPENDED`. |

Admin mengubah profile melalui halaman **Admin → Pengajuan QRIS**. Credential API tidak disimpan di tabel dan tidak ditampilkan pada UI.

### Fase 2 — Generate QR dinamis

Fase ini menyediakan payment attempt dan generate QR:

1. Buyer menyelesaikan checkout.
2. Server membuat order melalui RPC checkout existing.
3. Checkout memeriksa apakah merchant memiliki profile GDC aktif.
4. Edge Function melakukan reservation payment attempt secara idempotent.
5. Edge Function membuat `partner_reference_no` unik.
6. Edge Function mengirim request generate ke GDC.
7. QR response disimpan pada payment attempt.
8. Buyer diarahkan ke halaman QRIS dinamis.

### Fase 3 — Query, callback, dan fulfillment

Status transaksi diproses melalui dua jalur:

- polling/query dari halaman buyer;
- callback dari provider GDC.

RPC `process_gdc_qris_status` memastikan:

- attempt ditemukan dan dikunci saat diproses;
- nominal provider sama dengan nominal attempt;
- status terminal tidak diturunkan kembali;
- order hanya menjadi `PAID` setelah status `SUCCEEDED` tervalidasi;
- transaksi duplicate tidak menggandakan fulfillment.

### Fase 4 — Checkout dan UX

Checkout menggunakan route:

```text
/payment/gdc/:orderId/:attemptId
```

Halaman QRIS GDC menampilkan:

- QR image jika GDC mengembalikan `qr_image`;
- QR SVG dari `qr_content` jika image tidak tersedia;
- nominal pembayaran;
- batas waktu QR;
- partner reference;
- status pembayaran;
- tombol refresh manual;
- polling otomatis setiap 5 detik;
- status sukses, gagal, kedaluwarsa, atau masih diverifikasi.

QR dan provider payload tidak dimasukkan ke URL browser. URL hanya membawa UUID order dan UUID attempt.

### Fase 5 — Pilot rollout dan observability

Telemetry disimpan pada `gdc_qris_observability_events` dengan data terbatas:

- jenis event;
- internal status;
- HTTP status provider;
- durasi request;
- error code;
- payment attempt ID.

Request payload, response payload, QR content, token, secret, dan credential provider tidak dicatat pada tabel telemetry.

## 3. Komponen source

| Komponen | Lokasi |
|---|---|
| Migration profil dan payment attempt | `supabase/bootstrap/134_20261031220000_gdc_qris_dynamic_payment.sql` |
| Migration telemetry rollout | `supabase/bootstrap/135_20261031230000_gdc_qris_rollout_observability.sql` |
| Edge Function GDC | `supabase/functions/gdc-qris-payment/index.ts` |
| Konfigurasi Edge Function | `supabase/config.toml` |
| Client API frontend | `src/lib/gdcQrisApi.ts` |
| Halaman QRIS buyer | `src/pages/GdcQrisPaymentPage.tsx` |
| Integrasi checkout | `src/pages/CheckoutPage.tsx` |
| Konfigurasi profile admin | `src/pages/admin/AdminQrisApplicationsPage.tsx` |
| Acceptance tests | `src/lib/gdcQrisAcceptance.test.ts` |
| Runbook operasi | `docs/operations/gdc-qris-dynamic-payment.md` |

## 4. Arsitektur alur pembayaran

```text
Buyer
  |
  | Checkout
  v
create_marketplace_checkout()
  |
  | payment_method = ONLINE
  v
CheckoutPage
  |
  | Profile GDC merchant ACTIVE?
  |-----------------------------|
  | Ya                          | Tidak
  v                             v
GDC generate QR                Xendit invoice existing
  |
  v
GdcQrisPaymentPage
  |
  | query setiap 5 detik
  v
GDC query / callback
  |
  v
process_gdc_qris_status()
  |
  v
orders.payment_status = PAID
```

## 5. Database dan state machine

### `gdc_payment_profiles`

Satu merchant hanya memiliki maksimal satu profile GDC aktif/pending karena constraint:

```text
UNIQUE (merchant_id, provider)
```

Admin dapat mengubah status profile menjadi `SUSPENDED` untuk rollback tanpa menghapus data historis.

### `gdc_qris_payment_attempts`

State internal:

```text
CREATING → PENDING → SUCCEEDED
                    ├→ FAILED
                    ├→ EXPIRED
                    └→ UNKNOWN
```

Terdapat partial unique index untuk mencegah lebih dari satu attempt live pada order yang sama:

```text
order_id unik selama status CREATING, PENDING, atau UNKNOWN
```

### Idempotency

Generate menggunakan:

- `Idempotency-Key` dari frontend;
- reservation RPC `reserve_gdc_qris_attempt`;
- unique `partner_reference_no`;
- partial unique index per order.

Retry dari client tidak boleh membuat QR payment aktif kedua untuk order yang sama.

## 6. API Edge Function

Base URL:

```text
https://<project-ref>.supabase.co/functions/v1/gdc-qris-payment
```

### Generate

```http
POST /generate
Authorization: Bearer <supabase-access-token>
Idempotency-Key: gdc-qris:<order-id>
Content-Type: application/json
```

Request:

```json
{
  "order_id": "<order-uuid>"
}
```

Response sukses:

```json
{
  "success": true,
  "attempt": {
    "id": "<attempt-uuid>",
    "order_id": "<order-uuid>",
    "amount": 125000,
    "currency": "IDR",
    "partner_reference_no": "SADESA-...",
    "status": "PENDING",
    "qr_content": "...",
    "qr_url": null,
    "qr_image": null,
    "expires_at": "2026-10-31T23:00:00Z"
  }
}
```

### Query

```http
POST /query
Authorization: Bearer <supabase-access-token>
Content-Type: application/json
```

Request:

```json
{
  "attempt_id": "<attempt-uuid>"
}
```

Query hanya dapat dilakukan oleh buyer yang memiliki order tersebut. Attempt milik order lain tidak dibocorkan.

### Callback

```http
POST /callback
X-Callback-Token: <configured-token>
Content-Type: application/json
```

Callback tidak memakai JWT buyer. Validasi dilakukan menggunakan `GDC_CALLBACK_TOKEN`, lalu attempt dicari melalui `partnerReferenceNo`.

Payload callback dapat berupa payload langsung atau payload yang dibungkus pada field `data`.

## 7. Konfigurasi Edge Function Secrets

Set secret pada environment Supabase Edge Function, bukan pada frontend:

```text
GDC_API_BASE_URL
GDC_PARTNER_ID
GDC_ACCESS_TOKEN
GDC_SIGNATURE_SECRET
GDC_SIGNATURE_MODE
GDC_GENERATE_PATH
GDC_QUERY_PATH
GDC_SERVICE_CODE
GDC_CALLBACK_TOKEN
GDC_TIMEOUT_MS
```

Default value/path:

```text
GDC_SIGNATURE_MODE = hmac_sha256
GDC_GENERATE_PATH = /v1.0/qr/qr-mpm-generate
GDC_QUERY_PATH = /v1.0/qr/qr-mpm-query
GDC_TIMEOUT_MS = 15000
```

Adapter saat ini membentuk signature HMAC-SHA256 atas:

```text
<ISO timestamp>.<raw JSON body>
```

Hasilnya dikirim pada header:

```text
X-Signature
```

Formula signature, nama header, format access token, serta path endpoint harus diverifikasi dengan dokumentasi resmi GDC sebelum production. Jika kontraknya berbeda, perubahan cukup dilakukan di fungsi `gdcRequest` tanpa mengubah flow database.

## 8. Deployment sequence

### Staging

1. Pastikan branch `qr_app2` telah direview.
2. Terapkan bootstrap migration sampai bundle 135.
3. Deploy Edge Function:

```sh
supabase functions deploy gdc-qris-payment --project-ref "$SUPABASE_PROJECT_REF"
```

4. Set semua secret GDC pada project staging.
5. Buat satu profile GDC merchant dengan status `PENDING_VALIDATION`.
6. Validasi identifier merchant terhadap data sandbox GDC.
7. Ubah status profile menjadi `ACTIVE`.
8. Daftarkan callback staging bila endpoint callback GDC tersedia.
9. Jalankan acceptance test end-to-end.

### Production pilot

1. Pilih satu merchant pilot.
2. Pastikan finance reconciliation dan support readiness disetujui.
3. Aktifkan profile GDC hanya untuk merchant tersebut.
4. Pantau metrik minimal 24 jam.
5. Jangan memperluas merchant bila terdapat duplicate payment, reconciliation gap, atau critical incident.
6. Perluas rollout secara bertahap setelah gate terpenuhi.

## 9. Metrik rollout

Ambil agregat metrik 24 jam terakhir sebagai admin:

```sql
select public.get_gdc_qris_rollout_metrics(
  now() - interval '24 hours'
);
```

Metrik yang tersedia:

- jumlah generate dimulai;
- generate sukses/gagal;
- query sukses/gagal;
- callback diproses/ditolak;
- jumlah attempt unik;
- rata-rata durasi request.

Kondisi yang memerlukan HOLD atau rollback:

- ada transaksi duplicate;
- nominal provider berbeda dengan nominal order;
- callback ditolak tanpa penjelasan;
- generate/query error meningkat;
- payment status tidak sinkron dengan settlement provider;
- buyer berhasil membayar tetapi order tidak menjadi `PAID`;
- ada critical incident keamanan atau credential.

## 10. Rollback

Rollback normal dilakukan tanpa menghapus profile atau payment attempt:

1. Buka halaman admin QRIS.
2. Pilih merchant pilot.
3. Ubah status profil GDC menjadi `SUSPENDED`.
4. Simpan perubahan.
5. Pastikan checkout merchant tersebut tidak lagi menawarkan/memilih GDC.
6. Biarkan payment attempt existing tetap dapat dipantau sampai status akhirnya diketahui.
7. Rekonsiliasikan transaksi provider sebelum melakukan koreksi manual.

Untuk insiden credential:

1. nonaktifkan profile GDC;
2. rotate `GDC_ACCESS_TOKEN` dan `GDC_SIGNATURE_SECRET`;
3. periksa callback log dan observability event;
4. blokir callback token lama;
5. aktifkan kembali hanya setelah security review.

## 11. Test matrix

| Skenario | Expected result |
|---|---|
| Profile GDC `PENDING_VALIDATION` | Checkout tidak memakai GDC. |
| Profile GDC `ACTIVE` | Checkout memilih flow QRIS GDC. |
| Profile GDC `SUSPENDED` | Checkout fallback ke provider online existing/transfer. |
| Generate sukses | Attempt `PENDING`, QR tersedia. |
| Generate timeout | Attempt `UNKNOWN`, retry tidak membuat attempt live kedua. |
| Duplicate generate | Attempt existing dikembalikan. |
| Query pending | Buyer tetap melihat QR dan polling berlanjut. |
| Query sukses | Attempt `SUCCEEDED`, order `PAID`. |
| Callback sukses | Attempt `SUCCEEDED`, order `PAID`. |
| Callback tanpa token | HTTP 401, event callback rejected. |
| Attempt order buyer lain | HTTP 404, data tidak bocor. |
| Amount mismatch | RPC menolak fulfillment. |
| QR expired | Attempt `EXPIRED`, buyer tidak dapat melanjutkan QR. |
| GDC provider unavailable | UI menampilkan retry, order tetap tersimpan. |

## 12. Quality gate terakhir

Implementasi pada branch `qr_app2` telah diverifikasi dengan:

- migration validation: 136 bundle berhasil divalidasi;
- TypeScript check: lulus;
- ESLint file terkait: lulus;
- production build: berhasil;
- acceptance/payment tests: 19 test berhasil.

Quality gate source tidak menggantikan UAT sandbox GDC. Production readiness tetap memerlukan verifikasi kontrak provider, secret, callback, settlement, dan rekonsiliasi finansial.

## 13. Troubleshooting

### Profile GDC tidak terlihat pada checkout

Periksa:

- migration 134 sudah diterapkan;
- `merchant_id` profile sesuai merchant order;
- `provider = 'GDC'`;
- `status = 'ACTIVE'`;
- order hanya berisi satu merchant;
- browser session buyer masih valid.

### Generate mengembalikan `GDC payment provider unavailable`

Periksa:

- `GDC_API_BASE_URL`;
- path generate;
- access token dan partner ID;
- signature secret dan signature mode;
- timeout provider;
- log Edge Function;
- apakah kontrak body GDC memerlukan field tambahan.

### QR terlihat tetapi order belum `PAID`

Periksa:

- polling query GDC;
- callback provider;
- `partner_reference_no`;
- status provider dan response code;
- nominal `paidAmount`;
- observability event untuk attempt tersebut;
- settlement/rekonsiliasi GDC.

### Callback ditolak

Periksa:

- `GDC_CALLBACK_TOKEN` sama dengan token yang dikonfigurasi di GDC;
- header callback diterima sebagai `x-callback-token`;
- field `partnerReferenceNo` berada di root atau `data`;
- reference provider sama dengan `partner_reference_no` pada attempt.
