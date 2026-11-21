# Rencana Perbaikan dan Pengembangan
## Integrasi QRIS MPM Dinamis per Toko pada Sadesa-fix

**Repository:** `bonangpanjinur/Sadesa-fix`  
**Frontend:** Vite + React + TypeScript, deployment melalui Vercel  
**Backend:** Supabase Auth, Database, RPC, dan Edge Functions  
**Provider:** GDC/Neo QRIS MPM Dynamic  
**Status dokumen:** Diperbarui setelah pull ke `5af54468` dan implementasi QRIS GDC lanjutan pada 2026-11-21; source dan validasi repository sudah selesai, tetapi deployment serta pengujian provider nyata belum dilakukan.


---

## Status implementasi aktual dan persentase

Bagian ini adalah status terbaru terhadap repository pada commit `69d03525` (`fix: close remaining checkout and contract gaps`). Persentase dihitung dari **24 item pekerjaan yang dinilai satu per satu** di bawah ini: 12 item selesai dan 12 item belum selesai. Item yang sudah lulus pada level source/repository tidak dianggap sebagai deployment atau acceptance end-to-end.

### Ringkasan progres

| Status | Jumlah item | Persentase | Arti |
|---|---:|---:|---|
| **Sudah selesai** | 12 dari 24 | **50%** | Sudah diimplementasikan atau divalidasi di source/repository dan sudah di-push ke `main`. |
| **Belum selesai** | 12 dari 24 | **50%** | Belum dilakukan, belum tersedia di environment, atau belum dibuktikan melalui provider nyata/end-to-end. |
| **Total** | **24 item** | **100%** | Perhitungan transparan berdasarkan daftar di bawah. |

### Sudah selesai — 12 item (50%)

1. Checkout user login satu toko menampilkan QRIS Dinamis GDC hanya jika capability merchant aktif.
2. Guest checkout dan cart multi-merchant tidak menampilkan atau menggunakan QRIS Dinamis.
3. Checkout memakai authoritative checkout RPC; browser tidak menentukan nominal, MID, account number, atau reference provider.
4. Capability QRIS memakai RPC boolean `merchant_has_active_gdc_qris` tanpa membocorkan MID/account number ke frontend.
5. Edge Function memilih mapping memakai `orders.merchant_id`, menyimpan merchant yang sama pada payment record, dan menolak mismatch merchant/payment.
6. Client QRIS memvalidasi status, nominal, currency, QR content, reference, dan paid timestamp dari response provider.
7. Halaman konfirmasi memakai marker `QRIS_MPM_GDC`, merender QR dinamis, menyembunyikan upload bukti manual untuk provider dinamis, dan melakukan polling hingga `PAID` atau `FAILED`.
8. Guest payment dinormalisasi menjadi `TRANSFER` secara eksplisit sehingga state payment online tidak dapat dipakai oleh guest.
9. Migration hardening mapping merchant sudah dibuat, termasuk satu mapping aktif per merchant, validasi mapping, RPC capability, dan RLS payment service-role-only.
10. Seluruh suite test sudah lulus: **852 test lulus, 20 skipped, 0 gagal**.
11. Production build, validasi migration, dan validasi bootstrap sudah lulus.
12. Lint lulus tanpa error; empat warning yang tersisa hanya berasal dari artifact lama `artifacts/mockup-sandbox` dan bukan source QRIS yang diperbaiki.

### Belum selesai — 12 item (50%)

1. Migration database belum diterapkan ke Supabase staging.
2. Migration database belum diterapkan ke Supabase production.
3. Edge Function `gdc-qris-mpm` belum di-deploy ke staging/production.
4. Secret GDC belum diverifikasi atau dipasang pada environment Supabase Edge Function.
5. Belum ada sandbox end-to-end dengan minimal dua toko dan dua mapping MID/account GDC yang berbeda.
6. Belum ada bukti request nyata ke endpoint generate GDC pada environment staging.
7. Belum ada bukti query status, kecocokan nominal provider, dan settlement nyata pada environment staging.
8. Belum ada deployment preview/staging frontend ke Vercel dengan pemisahan secret sandbox-production.
9. Webhook GDC belum dikonfirmasi signature-nya dan belum diaktifkan sebagai jalur settlement utama.
10. Refund otomatis melalui GDC belum diimplementasikan.
11. Guest QRIS Dinamis dan checkout multi-merchant satu QR belum diimplementasikan.
12. Sinkronisasi atau scraping dashboard GDC belum diimplementasikan.

### Catatan status

Item “sudah selesai” di atas berarti source code dan pemeriksaan repository sudah dilakukan, bukan berarti fitur sudah aktif di production. Item “belum selesai” tetap menjadi pekerjaan lanjutan sebelum menyatakan integrasi siap production. Perubahan source dan dokumen sudah di-commit ke `bonangpanjinur/Sadesa-fix:main` setelah validasi sesi ini.

Perbaikan rekonsiliasi terbaru menambahkan worker `gdc-qris-reconcile` yang mengambil maksimal 20 payment `PENDING`, melakukan query GDC, memvalidasi reference dan nominal, lalu memanggil settlement canonical. Expiry memakai grace period 15 menit dan dijadwalkan melalui `pg_cron` + `pg_net` menggunakan `CRON_SECRET` khusus dari Vault. Deployment function, migration, secret, dan uji provider nyata tetap belum dilakukan.

### Keputusan keamanan saat ini

Jangan mengisi MID, account number, private key, client secret, access token, atau signature di frontend, Vercel, GitHub, dokumen publik, maupun log. Sebelum production, admin harus mencocokkan nama merchant GDC dengan toko Sadesa yang dipilih dan mengaktifkan mapping melalui database/RPC yang sudah di-hardening.

---

## 1. Ringkasan eksekutif

Sadesa-fix adalah marketplace yang dapat memiliki banyak toko. Setiap toko dapat mempunyai identitas QRIS GDC sendiri. Karena itu, QR dinamis tidak boleh dibuat menggunakan satu MID atau satu account number global untuk seluruh marketplace.

Desain yang benar adalah:

```text
Produk
  → merchant_id toko
  → order menyimpan merchant_id
  → backend mengambil mapping QRIS toko tersebut
  → request qr-mpm-generate memakai MID toko tersebut
  → QR disimpan sebagai transaksi order
  → status pembayaran diverifikasi
  → order menjadi PAID
```

Sadesa tidak perlu menyalin seluruh database dari website GDC. Sadesa hanya perlu menyimpan mapping yang diperlukan untuk menghubungkan toko Sadesa dengan identitas GDC-nya, serta menyimpan transaksi QR dinamis untuk setiap order.

---

## 2. Tujuan pengembangan

Pengembangan ini bertujuan untuk:

1. Menyediakan pilihan QRIS Dinamis GDC di halaman checkout.
2. Menghasilkan QR berbeda untuk setiap order.
3. Menggunakan MID dan account number sesuai toko yang menjual produk.
4. Memastikan pembayaran toko A tidak pernah masuk menggunakan konfigurasi toko B.
5. Memvalidasi nominal, reference, dan status pembayaran di backend.
6. Mengubah order menjadi `PAID` secara aman dan idempotent.
7. Mempertahankan transfer bank dan QRIS manual sebagai metode pembayaran lain.
8. Menyediakan dasar yang dapat dikembangkan untuk banyak toko tanpa menggunakan konfigurasi GDC global.

---

## 3. Batasan fase pertama

Fase pertama difokuskan pada checkout satu toko untuk pembeli yang sudah login.

Guest checkout belum memakai QRIS Dinamis karena Edge Function saat ini memvalidasi kepemilikan order melalui session user. Guest checkout tetap menggunakan alur pembayaran manual sampai mekanisme guest access token yang aman dirancang dan diuji.

Checkout multi-merchant juga belum memakai satu QR. Satu request `qr-mpm-generate` hanya boleh mewakili satu identitas merchant GDC. Jika ingin mendukung multi-merchant, cart harus dipecah menjadi beberapa order dan setiap order mendapatkan QR sendiri, atau GDC harus menyediakan skema split settlement.

Hal berikut tidak termasuk fase pertama:

- Refund otomatis melalui GDC.
- Scraping dashboard GDC.
- Menjadikan webhook sebagai sumber settlement sebelum signature callback dikonfirmasi.
- Menghapus seluruh kode Xendit yang mungkin masih digunakan oleh fitur lain.
- Menempatkan credential GDC di frontend, Vercel, atau source code.

---

## 4. Model bisnis dan data per toko

### 4.1 Data dari dashboard GDC

Dashboard GDC dapat menampilkan beberapa merchant dengan status seperti `Issued`, misalnya toko MomToast dan toko Sadesa. Setiap baris merchant tersebut harus diperlakukan sebagai identitas berbeda.

Untuk setiap toko Sadesa, admin harus mengetahui pasangan:

```text
Nama toko Sadesa
merchant_id internal Sadesa
MID / gdc_merchant_id dari GDC
Account number / gdc_account_number dari GDC
Status aktivasi
```

MID milik MomToast tidak boleh digunakan untuk order Sadesa. Account number juga harus berasal dari pasangan merchant yang sama.

### 4.2 Tabel konfigurasi QRIS per toko

Repository sudah memiliki fondasi tabel `qris_applications`. Kolom yang relevan adalah:

| Kolom | Fungsi |
|---|---|
| `merchant_id` | Menghubungkan aplikasi QRIS dengan toko Sadesa |
| `gdc_merchant_id` | MID GDC milik toko tersebut |
| `gdc_account_number` | Account number/default account GDC milik toko tersebut |
| `status` | Menentukan apakah mapping boleh dipakai |
| `activated_at` | Waktu aktivasi mapping |
| `updated_at` | Waktu perubahan konfigurasi |

Aturan wajib:

- Hanya mapping dengan `status = 'ACTIVE'` yang boleh digunakan.
- Satu toko tidak boleh memiliki dua konfigurasi aktif yang ambigu.
- Perubahan MID/account hanya boleh dilakukan admin.
- Nilai credential tidak ditulis di source code atau frontend.
- Jika mapping tidak ada atau tidak lengkap, request QR ditolak sebelum request dikirim ke GDC.

### 4.3 Tabel transaksi QR dinamis

Tabel `gdc_qris_mpm_payments` menyimpan transaksi QR per order. Satu toko dapat memiliki banyak transaksi:

```text
Toko Sadesa
├── Order 001 → QR transaksi 001
├── Order 002 → QR transaksi 002
└── Order 003 → QR transaksi 003
```

Field penting:

| Field | Fungsi |
|---|---|
| `order_id` | Satu payment record untuk satu order |
| `merchant_id` | Toko penerima dana; harus sama dengan `orders.merchant_id` |
| `partner_reference_no` | Reference internal yang dikirim ke GDC |
| `external_id` | ID transaksi eksternal/request |
| `reference_no` | Reference transaksi dari GDC |
| `amount` | Nominal server-side order |
| `currency` | Harus `IDR` |
| `qr_content` | Payload QR dinamis untuk ditampilkan |
| `status` | `CREATING`, `PENDING`, `PAID`, atau `FAILED` |
| `paid_at` | Waktu pembayaran tervalidasi |

Constraint penting:

- `order_id` unique.
- `partner_reference_no` unique.
- `external_id` unique.
- `currency = 'IDR'`.
- Payment `PENDING` harus memiliki `reference_no` dan `qr_content`.
- Payment `PAID` harus memiliki `paid_at`.

---

## 5. Arsitektur target

```text
[Vercel - Browser]
CheckoutPage
  │ hanya mengirim order_id
  ▼
[Supabase Edge Function]
gdc-qris-mpm
  │ membaca order dan merchant_id
  ▼
[Supabase Database]
orders
  │ merchant_id
  ▼
qris_applications
  │ MID + account number toko
  ▼
[GDC/Neo API]
POST /v1.0/qr/qr-mpm-generate
  │ qrContent + referenceNo
  ▼
[Supabase Database]
gdc_qris_mpm_payments
  │
  ▼
[Halaman pembayaran]
Tampilkan QR dan nominal order
  │
  ▼
[Edge Function query]
POST /v1.0/qr/qr-mpm-query
  │
  ▼
[Settlement RPC]
settle_gdc_qris_mpm_payment
  │
  ▼
orders.payment_status = PAID
```

Browser tidak boleh menentukan toko penerima, MID, account number, nominal final, reference provider, atau hasil settlement.

---

## 6. Alur lengkap pembayaran

### Tahap A — Pemilihan metode di checkout

1. Pembeli login.
2. Cart diperiksa.
3. Sistem memastikan seluruh produk berasal dari satu merchant.
4. `QRIS Dinamis GDC` ditampilkan jika toko memiliki konfigurasi QRIS aktif atau capability yang sesuai.
5. Untuk guest atau multi-merchant, pilihan dinonaktifkan dengan penjelasan yang jelas.
6. Ketika dipilih, checkout menjelaskan bahwa QR dibuat setelah order tersimpan dan nominalnya berasal dari server.

### Tahap B — Pembuatan order

1. Checkout memanggil RPC authoritative yang sudah ada.
2. RPC memvalidasi harga, stok, voucher, ongkir, merchant, dan total.
3. Order dibuat dengan `orders.merchant_id` sebagai toko pemilik order.
4. Untuk kompatibilitas dengan kontrak saat ini, `payment_method` dapat tetap menggunakan `TRANSFER`; provider aktual ditandai oleh `payment_channel = 'QRIS_MPM_GDC'` setelah QR berhasil dibuat.
5. Browser diarahkan ke:

```text
/payment/<orderId>?provider=gdc-mpm
```

Order belum boleh dianggap lunas pada tahap ini.

### Tahap C — Pemilihan konfigurasi toko

Edge Function `gdc-qris-mpm` menerima `order_id` dan melakukan:

```sql
SELECT id, buyer_id, merchant_id, total, payment_status, status
FROM orders
WHERE id = :order_id
  AND buyer_id = :authenticated_user;
```

Kemudian:

```sql
SELECT gdc_merchant_id, gdc_account_number
FROM qris_applications
WHERE merchant_id = :orders.merchant_id
  AND status = 'ACTIVE'
ORDER BY activated_at DESC
LIMIT 1;
```

Jika tidak ditemukan mapping yang valid, function mengembalikan error dan tidak memanggil GDC.

### Tahap D — Generate QR ke GDC

Backend membuat `partner_reference_no` dan `external_id` untuk order tersebut, lalu mengirim:

```json
{
  "partnerReferenceNo": "reference-internal-order",
  "amount": {
    "value": "TOTAL_DARI_DATABASE.00",
    "currency": "IDR"
  },
  "merchantId": "MID_MILIK_TOKO",
  "additionalInfo": {
    "accountNumber": "ACCOUNT_MILIK_TOKO"
  }
}
```

Endpoint:

```text
POST /v1.0/qr/qr-mpm-generate
```

Request harus memakai:

- Access token GDC dengan signature RSA-SHA256.
- Transaction signature HMAC-SHA512.
- `merchantId` dari `qris_applications` toko yang sesuai.
- `accountNumber` dari mapping toko yang sama.
- Total order yang dibaca dari database.

Jika berhasil dengan response code `2004700`, sistem menyimpan `qrContent` dan reference GDC ke `gdc_qris_mpm_payments`.

### Tahap E — Menampilkan QR

`PaymentConfirmationPage` mengambil data dari Edge Function, bukan langsung dari GDC. Halaman menampilkan:

- QR dinamis.
- Total order.
- Nama toko.
- Status menunggu pembayaran.
- Tombol cek status.
- Pesan bahwa QR hanya untuk order tersebut.

QRIS statis dan transfer manual tetap ditampilkan hanya pada alur masing-masing, tidak dicampur dengan QR dinamis.

### Tahap F — Query dan settlement

Browser memanggil Edge Function secara berkala. Edge Function memanggil:

```text
POST /v1.0/qr/qr-mpm-query
```

Query harus memvalidasi:

- `referenceNo` sesuai record internal.
- `originalPartnerReferenceNo` sesuai reference internal.
- `originalExternalId` sesuai transaksi.
- `serviceCode = '47'`.
- Response code query `2005100`.
- Status transaksi `00` untuk sukses.
- Currency `IDR`.
- Nominal GDC sama dengan total order.

Jika seluruh validasi benar, backend memanggil RPC:

```text
settle_gdc_qris_mpm_payment(...)
```

RPC mengunci payment dan order, mengecek reference serta nominal, lalu mengubah order menjadi `PAID`. Pemanggilan ulang harus menghasilkan respons duplicate yang aman, bukan settlement kedua.

---

## 7. Pengajuan data toko dan konfigurasi QRIS

Prosesnya terdiri dari **dua tahap yang berbeda**. Merchant/toko mengisi data usaha dan mengunggah dokumen pendukung. Setelah itu admin memeriksa pengajuan, meneruskannya ke proses penerbitan GDC/QRIS, lalu memasukkan hasil penerbitan seperti MID dan nomor akun default ke konfigurasi toko di Sadesa.

Merchant tidak mengisi MID GDC secara bebas. Pembeli juga tidak pernah melihat atau mengirim data konfigurasi GDC tersebut.

Repository sudah memiliki komponen pengajuan QRIS merchant, area admin `/admin/qris-applications`, serta fungsi database `admin_issue_qris_mpm(...)` dan `admin_configure_qris_mpm(...)`. Fondasi ini dapat dikembangkan menjadi alur pengajuan dan konfigurasi QRIS MPM per toko tanpa membuat konfigurasi global.

### 7.1 Form pengajuan yang diisi merchant

Merchant mengisi data toko melalui halaman pengajuan QRIS. Field yang perlu dipertahankan atau disesuaikan dengan formulir pada screenshot adalah:

| Field pengajuan | Isi |
|---|---|
| Pemohon/merchant | Toko yang mengajukan; terhubung ke `merchant_id` internal |
| Kriteria bisnis | Pilihan seperti `UMI / Usaha Mikro` sesuai klasifikasi provider |
| Lama usaha | Pilihan lama usaha sesuai daftar kategori provider |
| Nama Merchant QRIS (25) | Nama singkat dengan batas maksimal provider |
| Nama Merchant QRIS (50) | Nama merchant lebih lengkap dengan batas maksimal provider |
| Foto KTP | Foto identitas pemilik |
| Foto selfie | Selfie pemilik untuk verifikasi identitas |
| Foto lokasi usaha | Foto tempat/lokasi usaha |
| Foto produk | Foto produk yang dijual toko |

Validasi form dilakukan di frontend dan backend. File memakai bucket/path privat berdasarkan `merchant_id`, dengan validasi ukuran, MIME type, dan ekstensi. KTP dan selfie tidak boleh menjadi public URL.

Merchant dapat memperbaiki pengajuan jika ditolak atau diminta revisi. Merchant tidak boleh mengubah data pengajuan yang sudah `ACTIVE` tanpa melalui review admin kembali.

### 7.2 Status pengajuan merchant

```text
DRAFT → SUBMITTED → UNDER_REVIEW
                     ├→ NEEDS_CORRECTION → SUBMITTED
                     ├→ REJECTED
                     └→ APPROVED_PENDING_ISSUANCE
                                      → ISSUED_PENDING_ACTIVATION
                                      → ACTIVE
```

`ACTIVE` hanya diberikan setelah data usaha, hasil penerbitan, dan mapping GDC selesai diverifikasi admin. Mapping aktif dapat menjadi `SUSPENDED` atau `REVOKED` tanpa menghapus riwayat transaksi.

### 7.3 Dashboard admin untuk review pengajuan

Admin dapat memilih toko/pemohon, melihat kriteria bisnis dan lama usaha, membuka dokumen KTP/selfie/lokasi/produk melalui akses privat, memberi catatan koreksi, menyetujui atau menolak pengajuan, lalu memasukkan hasil penerbitan GDC.

Dokumen identitas hanya boleh dibuka oleh role admin yang berwenang. Akses dokumen, perubahan status, dan keputusan review perlu dicatat untuk audit.

### 7.4 Konfigurasi hasil penerbitan GDC oleh admin

Setelah GDC menerbitkan merchant QRIS, admin mengisi hasil penerbitan pada pengajuan toko yang benar:

| Data hasil GDC | Keterangan |
|---|---|
| MID / `gdc_merchant_id` | Identitas merchant GDC milik toko tersebut |
| Nomor akun default / `gdc_account_number` | Account number yang berpasangan dengan MID |
| Nama merchant GDC | Untuk mencocokkan dashboard GDC |
| Status penerbitan | Issued, pending activation, active, atau suspended |
| Catatan admin | Referensi verifikasi atau alasan perubahan |

Admin harus memilih toko Sadesa terlebih dahulu, mencocokkan nama merchant GDC, lalu menyimpan pasangan MID dan account number. Sistem menampilkan nama toko Sadesa dan nama merchant GDC sebelum aktivasi agar MomToast, Sadesa, atau merchant lain tidak tertukar.

Hanya setelah pasangan tersebut diverifikasi, admin mengaktifkan `qris_applications.status = 'ACTIVE'`. `gdc-qris-mpm` hanya memakai mapping aktif.

### 7.5 Tampilan dashboard admin yang dibutuhkan

Halaman admin menampilkan daftar toko dan status pengajuan/mapping QRIS:

| Informasi | Keterangan |
|---|---|
| Nama toko/pemohon | Nama merchant Sadesa yang dipilih |
| `merchant_id` internal | ID toko di database; read-only |
| Status pengajuan | Draft, diajukan, review, koreksi, disetujui, atau ditolak |
| Dokumen pengajuan | KTP, selfie, lokasi, dan produk melalui viewer privat |
| Nama merchant GDC | Untuk pencocokan dashboard GDC |
| MID GDC | Diinput admin; tidak ditampilkan ke pembeli |
| Account number GDC | Diinput admin; tidak ditampilkan ke pembeli |
| Status mapping | Belum dikonfigurasi, menunggu verifikasi, aktif, atau dinonaktifkan |
| Admin dan waktu perubahan | Untuk audit konfigurasi |

Nilai MID dan account number tidak boleh ditulis ke frontend build, Vercel environment, source code, log, atau dokumen publik. Nilai tersebut hanya dikirim dari form admin ke RPC terlindungi dan disimpan di Supabase.

### 7.6 Aturan keamanan dan alur operasional

- Hanya role admin yang boleh memverifikasi dokumen, menyetujui pengajuan, mengubah mapping, atau mengaktifkan QRIS.
- `merchant_id` dari form tidak boleh dipercaya tanpa validasi server.
- Perubahan MID/account dicatat dengan admin, waktu, toko, dan nilai status sebelum/sesudah; nilai sensitif tidak masuk log.
- Saat MID/account berubah, mapping lama dinonaktifkan lebih dahulu.
- Tabel `gdc_qris_mpm_payments` tetap tertutup dari browser.
- Tombol aktivasi menampilkan konfirmasi nama toko Sadesa dan nama merchant GDC.

```text
Merchant mengisi data usaha + upload dokumen
  → Admin review dan minta koreksi bila perlu
  → Admin menyetujui pengajuan
  → GDC menerbitkan QRIS/MID
  → Admin memasukkan MID + account number
  → Admin mencocokkan nama merchant
  → Admin mengaktifkan mapping
  → Backend memakai mapping saat checkout
```

Setelah toko aktif, pembeli tidak perlu mengetahui MID. Backend otomatis memilih mapping berdasarkan `orders.merchant_id`.

### 7.7 Cara memasukkan data dari website GDC ke Sadesa

### Opsi yang direkomendasikan: konfigurasi admin manual

Jika GDC tidak menyediakan API sinkronisasi merchant, admin Sadesa memasukkan mapping secara manual melalui dashboard admin yang dijelaskan pada bagian sebelumnya:

```text
Admin memilih toko Sadesa
  → memasukkan MID GDC toko
  → memasukkan account number toko
  → memeriksa nama merchant di dashboard GDC
  → menyimpan konfigurasi
  → mengaktifkan mapping
```

Fungsi yang sudah tersedia di bootstrap dan dapat dijadikan dasar untuk aksi dashboard:

```text
admin_issue_qris_mpm(...)
admin_configure_qris_mpm(...)
```

Validasi admin harus memastikan application memang milik toko yang dipilih dan tidak menimpa mapping toko lain.

### Opsi lanjutan: sinkronisasi melalui API atau export resmi

Jika GDC menyediakan API atau export resmi, alur dapat dikembangkan menjadi:

```text
GDC API/export resmi
  → Edge Function sinkronisasi
  → validasi admin
  → qris_applications
```

Sadesa tidak boleh melakukan scraping dashboard GDC karena rawan perubahan tampilan, masalah autentikasi, dan risiko keamanan.

---

## 8. Diagram visual proses

### 8.1 User flow merchant

Diagram ini menunjukkan data dan dokumen yang diisi merchant sampai pengajuan QRIS menjadi aktif.

![User flow merchant](https://private-us-east-1.manuscdn.com/sessionFile/uoVytNCPM3MzWHrcE5xNo2/sandbox/CpZheBS4lR3ulkb1BUCYq1-images_1795178780164_na1fn_L2hvbWUvdWJ1bnR1L0dEQy1TYWRlc2EtZml4LXJlbmNhbmEtYXNzZXRzLzAxLXVzZXItZmxvdy1tZXJjaGFudA.png?Policy=eyJTdGF0ZW1lbnQiOlt7IlJlc291cmNlIjoiaHR0cHM6Ly9wcml2YXRlLXVzLWVhc3QtMS5tYW51c2Nkbi5jb20vc2Vzc2lvbkZpbGUvdW9WeXROQ1BNM016V0hyY0U1eE5vMi9zYW5kYm94L0NwWmhlQlM0bFIzdWxrYjFCVUNZcTEtaW1hZ2VzXzE3OTUxNzg3ODAxNjRfbmExZm5fTDJodmJXVXZkV0oxYm5SMUwwZEVReTFUWVdSbGMyRXRabWw0TFhKbGJtTmhibUV0WVhOelpYUnpMekF4TFhWelpYSXRabXh2ZHkxdFpYSmphR0Z1ZEEucG5nIiwiQ29uZGl0aW9uIjp7IkRhdGVMZXNzVGhhbiI6eyJBV1M6RXBvY2hUaW1lIjoxNzk3MjkyODAwfX19XX0_&Key-Pair-Id=K2QY5QTL8JSY6C&Signature=MEQCIERgHbQmJnbmxQZdmhWgtdN9xwF87kSw2kBUrnEYn4yUAiA1XszVYQqm-ev6T8KQkKwlKIk5dVSpRR1u3XKy40~jgA__)

### 8.2 Admin review flow

Diagram ini menunjukkan proses admin memeriksa data usaha, dokumen, hasil penerbitan GDC, dan aktivasi mapping per toko.

![Admin review flow](https://private-us-east-1.manuscdn.com/sessionFile/uoVytNCPM3MzWHrcE5xNo2/sandbox/CpZheBS4lR3ulkb1BUCYq1-images_1795178780164_na1fn_L2hvbWUvdWJ1bnR1L0dEQy1TYWRlc2EtZml4LXJlbmNhbmEtYXNzZXRzLzAyLWFkbWluLXJldmlldy1mbG93.png?Policy=eyJTdGF0ZW1lbnQiOlt7IlJlc291cmNlIjoiaHR0cHM6Ly9wcml2YXRlLXVzLWVhc3QtMS5tYW51c2Nkbi5jb20vc2Vzc2lvbkZpbGUvdW9WeXROQ1BNM016V0hyY0U1eE5vMi9zYW5kYm94L0NwWmhlQlM0bFIzdWxrYjFCVUNZcTEtaW1hZ2VzXzE3OTUxNzg3ODAxNjRfbmExZm5fTDJodmJXVXZkV0oxYm5SMUwwZEVReTFUWVdSbGMyRXRabWw0TFhKbGJtTmhibUV0WVhOelpYUnpMekF5TFdGa2JXbHVMWEpsZG1sbGR5MW1iRzkzLnBuZyIsIkNvbmRpdGlvbiI6eyJEYXRlTGVzc1RoYW4iOnsiQVdTOkVwb2NoVGltZSI6MTc5NzI5MjgwMH19fV19&Key-Pair-Id=K2QY5QTL8JSY6C&Signature=MEQCIGP-2bTie8RretLz~bkQziuRqFPjrq5d9aXrLR~t3Ul0AiBVIGm-fj2pu~Oyax2DTaTiw8cQvl67jD~QIKnlgQxcNg__)

### 8.3 Checkout QRIS dinamis per toko

Diagram ini menegaskan bahwa checkout hanya mengirim `order_id`. Backend memilih MID dan account number berdasarkan `orders.merchant_id`.

![Checkout QRIS dinamis](https://private-us-east-1.manuscdn.com/sessionFile/uoVytNCPM3MzWHrcE5xNo2/sandbox/CpZheBS4lR3ulkb1BUCYq1-images_1795178780164_na1fn_L2hvbWUvdWJ1bnR1L0dEQy1TYWRlc2EtZml4LXJlbmNhbmEtYXNzZXRzLzAzLWNoZWNrb3V0LXFyaXMtZmxvdw.png?Policy=eyJTdGF0ZW1lbnQiOlt7IlJlc291cmNlIjoiaHR0cHM6Ly9wcml2YXRlLXVzLWVhc3QtMS5tYW51c2Nkbi5jb20vc2Vzc2lvbkZpbGUvdW9WeXROQ1BNM016V0hyY0U1eE5vMi9zYW5kYm94L0NwWmhlQlM0bFIzdWxrYjFCVUNZcTEtaW1hZ2VzXzE3OTUxNzg3ODAxNjRfbmExZm5fTDJodmJXVXZkV0oxYm5SMUwwZEVReTFUWVdSbGMyRXRabWw0TFhKbGJtTmhibUV0WVhOelpYUnpMekF6TFdOb1pXTnJiM1YwTFhGeWFYTXRabXh2ZHcucG5nIiwiQ29uZGl0aW9uIjp7IkRhdGVMZXNzVGhhbiI6eyJBV1M6RXBvY2hUaW1lIjoxNzk3MjkyODAwfX19XX0_&Key-Pair-Id=K2QY5QTL8JSY6C&Signature=MEQCIGgmPekrHtYMVSSHV-u12MwVI8VYO6OBAJDL2YiUdq1wAiAw9o1xONMfP-MJWV75XexEaiyi8q~~R~1VVEtM3QR2sQ__)

### 8.4 Database dan settlement flow

Diagram ini menunjukkan hubungan `qris_applications`, `orders`, `gdc_qris_mpm_payments`, query GDC, dan settlement idempotent.

![Database dan settlement flow](https://private-us-east-1.manuscdn.com/sessionFile/uoVytNCPM3MzWHrcE5xNo2/sandbox/CpZheBS4lR3ulkb1BUCYq1-images_1795178780164_na1fn_L2hvbWUvdWJ1bnR1L0dEQy1TYWRlc2EtZml4LXJlbmNhbmEtYXNzZXRzLzA0LWRhdGFiYXNlLXNldHRsZW1lbnQtZmxvdw.png?Policy=eyJTdGF0ZW1lbnQiOlt7IlJlc291cmNlIjoiaHR0cHM6Ly9wcml2YXRlLXVzLWVhc3QtMS5tYW51c2Nkbi5jb20vc2Vzc2lvbkZpbGUvdW9WeXROQ1BNM016V0hyY0U1eE5vMi9zYW5kYm94L0NwWmhlQlM0bFIzdWxrYjFCVUNZcTEtaW1hZ2VzXzE3OTUxNzg3ODAxNjRfbmExZm5fTDJodmJXVXZkV0oxYm5SMUwwZEVReTFUWVdSbGMyRXRabWw0TFhKbGJtTmhibUV0WVhOelpYUnpMekEwTFdSaGRHRmlZWE5sTFhObGRIUnNaVzFsYm5RdFpteHZkdy5wbmciLCJDb25kaXRpb24iOnsiRGF0ZUxlc3NUaGFuIjp7IkFXUzpFcG9jaFRpbWUiOjE3OTcyOTI4MDB9fX1dfQ__&Key-Pair-Id=K2QY5QTL8JSY6C&Signature=MEUCIQDe7cSyxpQIjv-pIWF60QRmS8MWKP-77xvECPePVSygSwIgY-GZhr2YrHLb1GGvYLIjn1HC7NKTwpiNxEmpFkSqR4s_)

### 8.5 Status lifecycle

Diagram ini memisahkan lifecycle pengajuan merchant dari lifecycle transaksi QR dinamis.

![Status lifecycle QRIS](https://private-us-east-1.manuscdn.com/sessionFile/uoVytNCPM3MzWHrcE5xNo2/sandbox/CpZheBS4lR3ulkb1BUCYq1-images_1795178780164_na1fn_L2hvbWUvdWJ1bnR1L0dEQy1TYWRlc2EtZml4LXJlbmNhbmEtYXNzZXRzLzA1LXN0YXR1cy1saWZlY3ljbGU.png?Policy=eyJTdGF0ZW1lbnQiOlt7IlJlc291cmNlIjoiaHR0cHM6Ly9wcml2YXRlLXVzLWVhc3QtMS5tYW51c2Nkbi5jb20vc2Vzc2lvbkZpbGUvdW9WeXROQ1BNM016V0hyY0U1eE5vMi9zYW5kYm94L0NwWmhlQlM0bFIzdWxrYjFCVUNZcTEtaW1hZ2VzXzE3OTUxNzg3ODAxNjRfbmExZm5fTDJodmJXVXZkV0oxYm5SMUwwZEVReTFUWVdSbGMyRXRabWw0TFhKbGJtTmhibUV0WVhOelpYUnpMekExTFhOMFlYUjFjeTFzYVdabFkzbGpiR1UucG5nIiwiQ29uZGl0aW9uIjp7IkRhdGVMZXNzVGhhbiI6eyJBV1M6RXBvY2hUaW1lIjoxNzk3MjkyODAwfX19XX0_&Key-Pair-Id=K2QY5QTL8JSY6C&Signature=MEQCIG0zd8xuZu2prTdowwu2prXC1hLH-TyV5CWmX87MRbVzAiBMQrGuTtaOtacp0k1LLy7N~3LhCgj-ac8Nec~3VNScxA__)

Source Mermaid untuk semua diagram disediakan terpisah agar dapat diedit.

## 9. Perubahan repository dan status pelaksanaan

### Frontend

#### `src/pages/CheckoutPage.tsx`

- Ubah `paymentMethod` dari state hardcode menjadi state yang dapat dipilih.
- Tambahkan pilihan QRIS Dinamis hanya untuk user login dan satu merchant.
- Jangan menjalankan Xendit untuk metode QRIS Dinamis.
- Pertahankan authoritative checkout RPC.
- Setelah order berhasil, arahkan ke halaman pembayaran dengan `provider=gdc-mpm`.
- Pastikan retry tidak membuat order baru.

#### `src/lib/gdcQrisMpmApi.ts`

- Pertahankan action `create` dan `status`.
- Validasi bentuk response secara eksplisit.
- Jangan menerima nominal atau MID dari browser.
- Pastikan hanya session user yang dapat membuat/query payment pada fase pertama.

#### `src/pages/PaymentConfirmationPage.tsx`

- Pertahankan render `qr_content` dengan `qrcode.react` (`QRCodeSVG`); `react-qr-code` sudah dihapus agar hanya ada satu library QR.
- Samakan marker provider dengan `QRIS_MPM_GDC`.
- Tambahkan polling status terkontrol.
- Hentikan polling pada `PAID`, `FAILED`, `EXPIRED`, atau order dibatalkan.
- Sembunyikan upload bukti manual pada QRIS Dinamis.
- Tetap pertahankan alur transfer dan QRIS statis.

### Backend

#### `supabase/functions/gdc-qris-mpm/index.ts`

- Pastikan query mapping selalu memakai `orders.merchant_id`.
- Jangan menggunakan MID/account global sebagai fallback.
- Validasi `application.merchant_id === order.merchant_id`.
- Simpan `merchant_id` yang sama ke `gdc_qris_mpm_payments`.
- Tambahkan pengujian toko A versus toko B.
- Jangan mencatat credential atau full response sensitif di log.

#### `supabase/functions/gdc-webhook/index.ts`

Webhook belum menjadi jalur utama sebelum format signature callback GDC dikonfirmasi. Setelah dikonfirmasi:

- Cari payment berdasarkan `partner_reference_no`.
- Ambil `order_id` dari payment record.
- Validasi signature, timestamp, external ID, reference, amount, dan currency.
- Gunakan settlement RPC yang sama.
- Terapkan idempotensi dan replay protection.

### Database/bootstrap

#### `supabase/bootstrap/134_20261101143000_gdc_qris_mpm_checkout.sql`

- Validasi bahwa kolom GDC per toko sudah tersedia.
- Pastikan hanya admin yang dapat mengubah MID/account.
- Pastikan payment record memiliki constraint unik.
- Pastikan RLS mencegah akses langsung browser ke tabel payment.
- Pastikan settlement RPC hanya dapat dipanggil service role.
- Jika diperlukan, tambahkan constraint atau RPC untuk mencegah dua mapping aktif pada satu toko.

---

## 10. Secrets dan deployment — BELUM SELESAI

Secret provider hanya disimpan di Supabase Edge Function Secrets:

```text
GDC_API_BASE_URL
GDC_CLIENT_KEY
GDC_CLIENT_SECRET
GDC_PRIVATE_KEY_PEM
GDC_PARTNER_ID
GDC_CHANNEL_ID
GDC_DEVICE_ID
```

Vercel hanya membutuhkan variabel browser-safe:

```text
VITE_SUPABASE_URL
VITE_SUPABASE_PUBLISHABLE_KEY
VITE_SUPABASE_PROJECT_ID
```

Yang tidak boleh berada di Vercel frontend, GitHub, source code, atau log:

```text
GDC_CLIENT_SECRET
GDC_PRIVATE_KEY_PEM
SUPABASE_SERVICE_ROLE_KEY
GDC access token
Signature request
```

Deployment dilakukan bertahap:

1. Terapkan bootstrap/database ke environment staging.
2. Set Supabase secrets staging.
3. Deploy `gdc-qris-mpm` ke Supabase staging.
4. Uji dengan merchant GDC sandbox.
5. Deploy frontend preview/staging ke Vercel.
6. Pisahkan secrets production dari sandbox.
7. Setelah acceptance criteria terpenuhi, lakukan deployment production.

---

## 11. Rencana pengujian dan hasil sementara

### Pengujian mapping toko

- Order dari toko A mengirim MID toko A.
- Order dari toko B mengirim MID toko B.
- Admin hanya dapat mengaktifkan mapping melalui dashboard dengan role admin.
- Admin tidak dapat menyimpan mapping aktif tanpa MID dan account number.
- Admin dapat menonaktifkan mapping toko tanpa menghapus riwayat transaksi QR.
- Account number selalu berasal dari mapping toko yang sama dengan MID.
- Mapping toko A tidak pernah digunakan untuk order toko B.
- Order tanpa mapping aktif ditolak sebelum request ke GDC.
- Dua mapping aktif untuk satu toko ditolak atau diselesaikan melalui aturan database yang tegas.

### Pengujian transaksi

- Satu order hanya memiliki satu payment record.
- Request ulang setelah QR berhasil tidak membuat QR record ganda.
- Retry setelah kegagalan create aman.
- Nominal di request GDC sama dengan total database.
- QR berhasil ditampilkan pada halaman pembayaran.
- Status `00` dengan nominal cocok menjadi `PAID`.
- Status `00` dengan nominal berbeda tidak menjadi `PAID`.
- Reference berbeda tidak dapat melakukan settlement.
- Status `06` menghasilkan status gagal.
- Payment yang sudah `PAID` tidak diproses ulang sebagai transaksi baru.
- Order kedaluwarsa atau dibatalkan tidak dapat membuat QR baru.

### Pengujian keamanan

- User A tidak dapat membuat QR untuk order user B.
- Browser tidak menerima credential GDC.
- Browser tidak dapat memilih MID toko lain melalui manipulasi request.
- Tabel payment tidak dapat dibaca langsung oleh `anon` atau `authenticated`.
- Settlement hanya dapat dilakukan oleh service role.

### Pengujian kompatibilitas

- Transfer manual tetap berjalan.
- QRIS statis tetap berjalan.
- Guest checkout tetap berjalan sesuai alur lama.
- Xendit tidak dipanggil untuk QRIS Dinamis.
- Checkout multi-merchant tidak memakai satu MID toko pertama.

---

## 12. Kriteria penerimaan sebelum production — BELUM TERPENUHI

Implementasi dianggap siap diproduksi jika seluruh kondisi berikut terpenuhi:

1. Admin dapat menghubungkan setiap toko Sadesa dengan MID dan account number GDC yang benar.
2. Admin dapat melihat status, mengubah, mengaktifkan, dan menonaktifkan mapping QRIS per toko melalui dashboard.
3. User login dapat memilih QRIS Dinamis untuk checkout satu toko.
4. QR toko A dan toko B dibuat menggunakan mapping masing-masing.
5. Setiap order mendapatkan QR dinamis yang unik.
6. QR menggunakan nominal yang berasal dari server.
7. Payment record menyimpan `merchant_id` yang sama dengan order.
8. Pembayaran sukses hanya disettle jika response, reference, currency, dan nominal cocok.
9. Settlement aman ketika dipanggil ulang.
10. Order berubah menjadi `PAID` tanpa upload bukti manual.
11. QRIS manual, transfer, dan guest checkout tidak rusak.
12. Tidak ada secret provider di frontend, Vercel, GitHub, atau log.
13. Build, TypeScript, lint, unit test, dan pengujian Edge Function lulus.
14. Sandbox GDC berhasil diuji menggunakan minimal dua mapping toko berbeda.
15. Rencana callback/webhook sudah memiliki aturan signature yang dikonfirmasi GDC sebelum diaktifkan di production.

---

## 13. Urutan pelaksanaan berikutnya

### Tahap 1 — Validasi database dan mapping merchant

Pastikan setiap toko memiliki `qris_applications` yang benar, satu mapping aktif, MID/account yang sudah dicocokkan dengan dashboard GDC, dan akses admin yang aman.

### Tahap 2 — Dashboard admin untuk mapping QRIS

Buat atau perluas halaman admin QRIS agar admin dapat memilih toko, memasukkan MID/account number, melihat status, melakukan verifikasi, mengaktifkan/menonaktifkan mapping, dan melihat audit perubahan. Gunakan RPC admin yang memiliki validasi role dan merchant ownership; jangan melakukan update langsung dari browser tanpa policy/RPC yang aman.

### Tahap 3 — Perbaikan checkout

Aktifkan state `QRIS_DYNAMIC`, pilihan metode pembayaran, batasan login/satu merchant, dan handoff order ke halaman pembayaran QR dinamis.

### Tahap 4 — Perbaikan backend

Audit pemilihan mapping berdasarkan `orders.merchant_id`, idempotensi payment record, validasi reference, amount, dan settlement RPC.

### Tahap 5 — Penyempurnaan halaman pembayaran

Pastikan QR, nominal, status, retry, polling, error, expiry, dan status `PAID` tampil dengan benar tanpa mencampur alur manual.

### Tahap 6 — Sandbox end-to-end

Uji minimal dua toko dengan mapping GDC berbeda. Pastikan request generate benar-benar menggunakan MID toko masing-masing.

### Tahap 7 — Production readiness

Pisahkan secret production, lakukan review keamanan, dokumentasikan prosedur pengisian mapping merchant, dan aktifkan webhook hanya setelah kontraknya jelas.

---

## 14. Kesimpulan

Sadesa-fix memang membutuhkan database mapping QRIS per toko, tetapi bukan database penuh dari website GDC. Struktur yang dibutuhkan adalah:

```text
qris_applications
  → konfigurasi MID/account GDC per toko

gdc_qris_mpm_payments
  → transaksi QR dinamis per order

orders
  → sumber merchant_id dan nominal order
```

Kunci keberhasilan integrasi adalah backend selalu mengikuti hubungan:

```text
orders.merchant_id
  = qris_applications.merchant_id
  = gdc_qris_mpm_payments.merchant_id
```

Dengan aturan tersebut, setiap toko dapat menerima QR dinamisnya sendiri, setiap order memiliki QR unik, dan dana tidak salah diarahkan ke MID toko lain.
