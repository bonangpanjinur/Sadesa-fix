# Audit Integrasi GDC QRIS MPM Dinamis

Tanggal audit: 2026-11-11  
Scope: Admin QRIS/GDC, checkout marketplace, payment confirmation, Edge Function GDC, webhook, settlement, merchant readiness, dan deployment.

## Kesimpulan eksekutif

Implementasi sudah memiliki fondasi yang benar: `qrContent` dari response provider disimpan sebagai `gdc_qris_mpm_payments.qr_content`, dikembalikan sebagai `qr_content`, lalu dirender dengan `QRCodeSVG`. Identity order juga sudah dibedakan dengan `payment_channel = QRIS_MPM_GDC` dan `payment_intent = GDC_MPM`.

Namun sistem belum siap dinyatakan production-ready. Ada satu blocker pembayaran yang dapat membuat seluruh settlement GDC gagal, satu blocker deployment yang membuat bootstrap tidak tervalidasi, serta deployment Supabase/frontend yang tidak otomatis mengikuti commit GitHub. Selain itu, jalur GDC legacy masih hidup berdampingan dengan jalur MPM baru sehingga observability dan maintenance berisiko salah arah.

## Temuan prioritas

### P0 — Settlement GDC selalu berpotensi ditolak karena deadline order NULL

Bukti:

- `supabase/bootstrap/138_20261109100000_checkout_qris_finality.sql:262-269` mengatur `v_deadline := NULL` untuk semua order `TRANSFER`.
- `supabase/bootstrap/138_20261109100000_checkout_qris_finality.sql:962-965` menolak settlement jika `v_order.confirmation_deadline IS NULL`.
- `supabase/functions/gdc-qris-mpm/index.ts:266-267` hanya menolak jika deadline ada dan sudah lewat, sehingga pembuatan QR tetap bisa berjalan walaupun deadline NULL.

Dampak:

1. Order QR GDC dapat dibuat.
2. Provider dapat mengembalikan `qrContent` dan pembeli dapat membayar.
3. Saat status `00` diproses melalui polling/webhook, RPC settlement menolak dengan `GDC payment arrived outside the order payment window` karena deadline NULL.
4. Pembayaran berpotensi sudah masuk provider tetapi order tetap belum `PAID`.

Perbaikan yang diperlukan:

- Saat checkout `TRANSFER + QRIS_MPM_GDC`, isi `confirmation_deadline`, misalnya `now() + interval '30 minutes'` atau nilai konfigurasi yang disepakati.
- Pastikan `marketplace_stock_reservations.expires_at` tidak lebih pendek daripada payment deadline.
- Tambahkan test database/integration khusus: order GDC dibuat, deadline terisi, settlement status `00` berhasil, order menjadi `PAID`.
- Jangan hanya menghapus pengecekan NULL dari settlement; itu akan menghilangkan batas waktu pembayaran.

### P0 — Manifest bootstrap stale setelah migration 138 diubah

Validasi lokal menghasilkan:

```text
Bootstrap bundle validation FAILED
- hash mismatch: 138_20261109100000_checkout_qris_finality.sql
```

File aktual saat audit:

```text
sha256: ca563ec7c7c5c66111a3435a18d035470556b5bdc180d9edb185a24e91dce6eb
bytes: 51936
```

Manifest masih mencatat hash dan ukuran lama:

```text
sha256: 5f6bdf8297069a2b2412810b83613d2eaa05fe7cb1fe22c1a68d984a77c3d819
bytes: 24903
```

Dampak:

- `validate-bootstrap-bundles.py` gagal.
- Pipeline/deployment yang memvalidasi manifest dapat menolak migration 138.
- Perubahan SQL yang sudah dipush ke GitHub belum tentu masuk ke paket bootstrap yang dianggap resmi.

Perbaikan:

- Regenerasi `supabase/bootstrap/manifest.json` melalui workflow resmi repository, bukan edit hash manual.
- Jalankan kembali `python3 scripts/validate-bootstrap-bundles.py` sampai status OK.
- Commit manifest bersama perubahan migration.

### P0 — GitHub push tidak sama dengan deployment Supabase atau frontend

Repository `main` sudah memuat `[functions.gdc-qris-mpm] verify_jwt = false`, tetapi browser masih menerima `401` pada `gdc-qris-mpm`. Ini membuktikan configuration file di GitHub belum diterapkan ke Edge Function remote, atau function remote masih deployment lama.

Hal yang sama terlihat dari bundle frontend lama yang masih mengirim kode wilayah `3206100`, padahal source terbaru sudah mengonversinya ke `32.06.10`.

Perbaikan deployment:

```bash
supabase functions deploy gdc-qris-mpm --no-verify-jwt
supabase functions deploy gdc-webhook --no-verify-jwt
supabase functions deploy wilayah-proxy
supabase functions deploy google-maps
```

Kemudian deploy ulang frontend dari `main`, invalidate cache/service worker, dan verifikasi bundle baru.

`verify_jwt = false` hanya mematikan gateway JWT. `gdc-qris-mpm` tetap memvalidasi `Authorization: Bearer <user access token>` di dalam handler pada `index.ts:193-200`.

## Audit alur Admin

### Yang sudah benar

- Admin UI memiliki field khusus `gdc_merchant_id` dan `gdc_account_number`.
- `admin_issue_qris_mpm` menyimpan identity GDC dan mengubah status menjadi `ISSUED_PENDING_ACTIVATION`.
- `admin_activate_qris` hanya mengaktifkan aplikasi jika kedua field GDC terisi.
- Trigger database menolak status `ACTIVE` jika identity GDC kosong.
- Admin tidak diminta mengunggah QR statis untuk MPM dinamis; ini sesuai kebutuhan `qrContent` dinamis.
- Merchant tidak dapat mengubah identity GDC secara langsung; perubahan dibatasi admin/RPC.

### Yang masih kurang

1. **Belum ada validasi ke provider sebelum aktivasi.** UI menampilkan `identitas terisi`, tetapi source sendiri mengakui kelengkapan field belum membuktikan identity valid di provider. Admin bisa mengaktifkan typo NMID atau Account Number.
2. **Belum ada tombol test-readiness yang memanggil GDC dengan aman.** Tambahkan RPC/Edge Function admin-only yang memvalidasi format, melakukan query non-finansial bila provider mendukung, atau setidaknya melakukan controlled availability check.
3. **Availability hanya mengecek dua field database.** `gdc-qris-mpm` mengembalikan `available: true` bila `status = ACTIVE` dan dua string tidak kosong. Ia tidak mengecek credentials Edge Function, token GDC, device ID, channel ID, atau konektivitas provider.
4. **UI status `QRIS Sadesa aktif` masih mudah disalahartikan sebagai QR dinamis siap.** Pisahkan status aplikasi QRIS dengan status operasional MPM:
   - Application active
   - GDC identity complete
   - GDC credentials configured
   - Provider connectivity verified
   - Last successful QR generation
5. **Tidak ada audit log khusus untuk perubahan NMID/Account Number.** Simpan admin, waktu, nilai lama/baru yang disanitasi, dan alasan perubahan. Jangan simpan secret provider di tabel application.
6. **Tidak ada kontrol merchant-level enable/disable GDC.** Jika provider bermasalah, admin hanya bisa mengosongkan/mengubah identity atau menunggu error. Tambahkan status operational flag agar availability bisa dimatikan tanpa merusak data onboarding.

## Audit alur Checkout

### Yang sudah benar

- Checkout hanya menawarkan QR MPM kepada user login.
- Availability dicek berdasarkan merchant pertama dan cart dibatasi satu merchant.
- Saat QR dinamis dipilih, client mengirim `p_payment_method = TRANSFER` dan `p_payment_channel = QRIS_MPM_GDC`.
- Order menyimpan `payment_channel` dan `payment_intent` dalam transaction melalui trigger.
- URL `provider=gdc-mpm` hanya dipakai sebagai presentation route; PaymentConfirmation menggunakan channel order sebagai sumber otoritatif.
- Checkout tidak mempercayai nominal dari client untuk pembuatan QR; backend membaca total order.
- GDC QR dibuat setelah order tersimpan, sehingga provider menerima order ID sebagai partner reference.
- `qrContent` divalidasi tidak kosong dan maksimum 4000 karakter sebelum disimpan.
- Client merender `qr_content` menggunakan `QRCodeSVG`.

### Yang salah/berisiko

1. **Deadline payment GDC tidak dibuat**, menyebabkan P0 settlement failure seperti di atas.
2. **Pesan error availability terlalu generik.** `CheckoutPage` mengubah semua error menjadi `Ketersediaan QR MPM gagal diverifikasi`, sehingga user/admin tidak bisa membedakan:
   - JWT/deployment error
   - GDC credentials missing
   - merchant identity missing
   - database error
   - provider unavailable
3. **Availability endpoint bukan health check provider.** UI dapat mengaktifkan radio QR dinamis walaupun token GDC atau signature provider pasti gagal.
4. **Race pada create QR masih perlu integration test remote.** Ada idempotent ledger per `order_id`, tetapi tidak ada test concurrent request terhadap Edge Function remote. Status `CREATING/UNKNOWN` sudah aman secara konservatif, tetapi perlu dibuktikan.
5. **Retry hanya aman untuk status tertentu.** Status `UNKNOWN` sengaja tidak boleh langsung di-create ulang, ini benar, tetapi UI perlu menyediakan tindakan rekonsiliasi/status yang jelas agar order tidak menggantung.
6. **Admin fallback tidak boleh muncul untuk timeout/UNKNOWN.** Implementasi saat ini sudah menahan fallback hanya untuk `FAILED/EXPIRED`; perilaku ini harus dipertahankan.
7. **Tidak ada validasi scanner terhadap EMV payload di client.** QR generator hanya mengecek string tidak kosong. Minimal tambahkan validasi panjang/format payload dan test bahwa output QR dapat dipindai dengan fixture provider.

## Audit Payment Confirmation

### Yang sudah benar

- `PaymentConfirmationPage` memanggil `createOrGetGdcQrisMpm(orderId)` hanya jika order channel `QRIS_MPM_GDC` dan method `TRANSFER`.
- QR hanya dirender dari `gdcPayment.qr_content`, bukan dari QR statis admin.
- Polling status setiap 15 detik mencegah request bertumpuk dengan `inFlight` guard.
- Status `UNKNOWN` tidak langsung dialihkan ke pembayaran manual.
- Fallback manual memerlukan status server `MANUAL_FALLBACK_PENDING`.

### Yang perlu diperbaiki

- Tampilkan reference number, status provider, attempt number, dan waktu update secara aman untuk membantu support.
- Bedakan pesan `QR belum dibuat`, `provider sedang direkonsiliasi`, `provider gagal`, dan `settlement gagal`.
- Saat settlement gagal setelah provider status `00`, jangan hanya menampilkan status generic; buat status `RECONCILIATION_REQUIRED`/support ticket yang terlihat admin.
- Tambahkan timeout UX: polling tidak boleh tanpa batas tanpa menjelaskan kepada user bahwa transaksi harus diperiksa admin.

## Audit sisi Merchant

### Kondisi saat ini

Merchant hanya mengajukan data QRIS dan melihat status aplikasi. Identity GDC dikelola admin, sesuai prinsip keamanan. Merchant tidak melihat detail NMID/Account Number, sehingga merchant tidak bisa memperbaiki typo sendiri.

### Kekurangan

1. Merchant tidak melihat status operasional GDC yang terpisah dari status aplikasi QRIS.
2. Merchant tidak melihat hasil test activation/provider.
3. Tidak ada informasi “QR dinamis menerima pembayaran langsung ke akun merchant” yang disertai status provider terakhir.
4. Tidak ada peringatan ketika GDC identity berubah atau dinonaktifkan admin.
5. Merchant order view belum memiliki layar khusus untuk pembayaran GDC `PENDING`, `UNKNOWN`, `PAID`, `FAILED`, `EXPIRED` dan rekonsiliasi. Merchant perlu melihat order umum, tetapi support operasional membutuhkan ledger GDC.
6. Legacy `gdc-payment` masih ada dengan model berbeda (`orders.payment_qr_content`, `GDC_QRIS`, `payment_invoice_id`), sedangkan MPM baru memakai `gdc_qris_mpm_payments`, `QRIS_MPM_GDC`, `qr_content`. Pastikan tidak ada route merchant/checkout yang masih memakai jalur lama. Untuk jangka panjang, retire atau beri label jelas pada legacy function.

## Audit Webhook dan settlement

### Yang sudah benar

- Signature, timestamp, partner ID, external ID, reference, amount, currency, dan partner reference diverifikasi.
- MPM webhook diarahkan ke ledger `gdc_qris_mpm_payments`, tidak memakai legacy invoice path.
- Settlement memakai service role dan RPC server-side.
- Idempotency untuk status `PAID` sudah tersedia.
- Amount dan currency dibandingkan dengan ledger/order.

### Temuan yang perlu diperbaiki

1. **Tanggal pembayaran webhook fallback ke `now()`.** `supabase/functions/gdc-webhook/index.ts:179-182` hanya membaca `additionalInfo.paymentDate`, lalu memakai waktu server jika field tidak ada. Helper `parseGdcCallbackPaymentDate` sudah ada tetapi tidak digunakan. Ini dapat membuat callback tanpa payment date diterima seolah-olah terjadi sekarang. Gunakan `paidTime/paymentDate/additionalInfo.paymentDate`, validasi tanggal, lalu reject jika callback status `00` tidak memiliki timestamp valid.
2. **Path signature harus dites pada URL deployment aktual.** `new URL(req.url).pathname` harus sama persis dengan path yang ditandatangani provider. Tambahkan fixture test untuk `/functions/v1/gdc-webhook`.
3. **Status callback gagal dan sukses perlu test integration terhadap RPC.** Unit test helper ada, tetapi belum membuktikan perubahan ledger/order dalam database.
4. **Fallback/manual operation perlu audit trail.** Saat `MANUAL_FALLBACK_PENDING`, simpan admin/user yang meminta fallback, timestamp, dan alasan.
5. **Expired status perlu batas provider dan local deadline yang konsisten.** Saat payment deadline lokal habis, sistem perlu menandai payment/order expired secara deterministik atau tetap melakukan status query sesuai kebijakan provider.

## Riwayat dua jalur GDC dan hasil cleanup

Jalur baru:

```text
CheckoutPage
→ gdc-qris-mpm
→ gdc_qris_mpm_payments.qr_content
→ QRCodeSVG
→ gdc-qris-mpm status/webhook
→ settle_gdc_qris_mpm_payment
```

Jalur lama yang sudah dihapus dari source aktif:

```text
gdcPaymentApi
→ gdc-payment
→ orders.payment_qr_content/payment_invoice_id/payment_channel = GDC_QRIS
→ legacy gdc-webhook path
```

`gdcPaymentApi` tidak terlihat dipakai oleh checkout baru. Sebelum cleanup, keberadaan dua model ini berbahaya karena:

- monitoring bisa melihat status dari tabel yang salah;
- webhook/deployment dapat mengarah ke function lama;
- operator dapat menguji endpoint lama lalu menyimpulkan MPM baru sudah berfungsi;
- kolom order lama dapat menimbulkan status ambigu.

Source of truth sekarang ditetapkan pada ledger `gdc_qris_mpm_payments` dan `QRIS_MPM_GDC`. Data/kolom legacy tetap dipertahankan untuk kompatibilitas historis dan fitur pembayaran lain, tetapi tidak lagi memiliki handler GDC aktif.

## Checklist deployment wajib

1. Perbaiki deadline GDC di checkout core/settlement.
2. Regenerasi manifest bootstrap setelah migration berubah.
3. Jalankan:

```bash
python3 scripts/validate-bootstrap-bundles.py
bash scripts/validate-migrations.sh
```

4. Deploy database migration 134–138 dalam urutan yang benar dan reload schema.
5. Deploy Edge Functions:

```bash
supabase functions deploy gdc-qris-mpm --no-verify-jwt
supabase functions deploy gdc-webhook --no-verify-jwt
supabase functions deploy wilayah-proxy
supabase functions deploy google-maps
```

6. Pastikan secret Edge Function terisi:

```text
GDC_API_BASE_URL
GDC_CLIENT_KEY
GDC_CLIENT_SECRET
GDC_PRIVATE_KEY_PEM
GDC_PARTNER_ID
GDC_CHANNEL_ID
GDC_DEVICE_ID
SUPABASE_SERVICE_ROLE_KEY
```

7. Deploy frontend dari commit `main`, invalidate cache/service worker.
8. Verifikasi database:

```sql
SELECT merchant_id, status, gdc_merchant_id, gdc_account_number, activated_at
FROM public.qris_applications
WHERE status = 'ACTIVE';
```

9. Uji end-to-end dengan nominal kecil/test merchant:

```text
availability → create → response.qrContent → scan → status 00 → settlement → order PAID
```

10. Uji failure matrix:

```text
missing Authorization
missing GDC secret
invalid merchant identity
provider timeout
provider status UNKNOWN
provider status 06
provider status 07
amount mismatch
callback duplicate
manual fallback after final failure
```

## Hasil validasi source

- `bash scripts/validate-migrations.sh`: lolos dengan warning duplicate timestamps.
- `python3 scripts/validate-bootstrap-bundles.py`: gagal karena hash migration 138 stale.
- Unit test/lint belum bisa dijalankan di workspace ini karena `node_modules` belum terpasang (`vitest` dan `eslint` tidak tersedia).

## Urutan perbaikan yang disarankan

### Fase 1 — blocker pembayaran dan deployment

- Perbaiki `confirmation_deadline` GDC.
- Perbaiki webhook payment date.
- Regenerasi manifest.
- Deploy database, functions, dan frontend.

### Fase 2 — observability dan admin readiness

- Pisahkan availability database dari provider health.
- Tambahkan test connection/status GDC admin-only.
- Tambahkan dashboard ledger GDC dan rekonsiliasi.
- Tambahkan audit log perubahan identity.

### Fase 3 — cleanup arsitektur

- Tetapkan ledger MPM baru sebagai source of truth.
- Hapus/retire legacy `gdc-payment` setelah tidak ada consumer — selesai pada cleanup ini.
- Tambahkan integration tests remote/staging dan test callback signature.
