# Runbook GDC QRIS MPM — Sandbox

Panduan ini untuk memasang dan menguji QRIS dinamis GDC pada **Supabase sandbox/staging**. Jangan gunakan QR uji untuk pembayaran. Jangan menerapkan secret sandbox ke production.

## 1. Prasyarat dan batas aman

- Pastikan project ref berasal dari Supabase Dashboard → Project Settings → General dan environment-nya memang staging/sandbox.
- Pastikan URL Supabase yang dipakai frontend cocok dengan project ref tersebut. `supabase/config.toml` mencantumkan project ref repo, tetapi jangan anggap itu bukti bahwa production/staging yang aktif sama.
- Siapkan kredensial sandbox dari portal atau petugas GDC. Jangan memasukkan kredensial produksi.
- Pastikan perubahan database GDC sudah diterapkan ke project yang sama. Migration source GDC ada di bootstrap `134`, `140`, `141`, `142`, dan `143`, sesuai urutan bootstrap. Workflow `scripts/deploy-supabase-staging.sh` menerapkan semua bootstrap, bukan hanya migration GDC; tinjau target dan prosedur database sebelum menjalankannya.
- Jangan menaruh GDC private key, client secret, service-role key, atau token pada frontend, variabel `VITE_*`, Vercel/Railway, Git, tiket, atau log.

### Batas environment: Vercel vs Supabase

| Lokasi | Yang boleh disimpan | Yang dilarang |
|---|---|---|
| Vercel/frontend | `VITE_SUPABASE_URL`, publishable/anon key, dan konfigurasi UI non-rahasia | Semua `GDC_*`, `ALLOWED_ORIGINS`, `GDC_ADMIN_PREVIEW_ENABLED`, service-role key, private key, client secret, access token, dan signature |
| Supabase Edge Functions | Semua `GDC_*`, `ALLOWED_ORIGINS`, `GDC_ADMIN_PREVIEW_ENABLED`, `CRON_SECRET`, serta secret runtime Supabase melalui Secret Manager/Vault | Menyalin secret ke source code, browser, Vercel, Git, atau log |

`ALLOWED_ORIGINS` berisi daftar origin yang dipisahkan koma dan sudah disetujui. `GDC_ADMIN_PREVIEW_ENABLED=true` hanya untuk preview sandbox; production harus `false`.

`gdc-qris-reconcile` adalah worker service-role-backed yang menerima hanya header `x-cron-secret` dengan nilai `CRON_SECRET` khusus. Worker mengambil maksimal 20 payment `PENDING` per run, query GDC satu per satu, memvalidasi reference/nominal, lalu memanggil `settle_gdc_qris_mpm_payment`. Payment baru boleh di-expire setelah masa tenggang 15 menit dan setelah kesempatan query worker. Migration `147` menjadwalkannya melalui `pg_cron` + `pg_net`; URL Supabase dan `GDC_RECONCILE_CRON_SECRET` harus tersedia di Supabase Vault.

### 1a. Jadwal rekonsiliasi (pg_cron + pg_net + Vault)

Migration `147` menyediakan jadwal worker yang kompatibel, sedangkan migration `148` bersifat **fail-fast**: migration akan gagal jika `pg_cron`, `pg_net`, Vault, atau secret wajib belum tersedia. Buat secret lebih dulu, terapkan migration `148`, lalu jadwal **harus tetap diverifikasi** setelah migration.

Dua secret Vault harus dibuat manual (SQL Editor project staging; ganti placeholder, jangan simpan nilai asli di Git):

```sql
select vault.create_secret('https://<project-ref>.supabase.co', 'SUPABASE_URL');
select vault.create_secret('<nilai-acak-panjang>', 'GDC_RECONCILE_CRON_SECRET');
```

Nilai `GDC_RECONCILE_CRON_SECRET` di Vault **harus sama persis** dengan Edge Function secret `CRON_SECRET` (nama berbeda, nilai sama). Jika berbeda, worker membalas 401 setiap run.

Urutan yang disarankan: buat kedua secret Vault, set Edge Function secret `CRON_SECRET` dengan nilai yang sama, deploy `gdc-qris-reconcile`, apply bootstrap sampai migration `148`, lalu jalankan query verifikasi di bawah. Jangan menganggap migration sukses sebagai bukti job sudah berjalan.

Verifikasi (tidak mencetak secret):

```sql
select jobname, schedule, active from cron.job where jobname = 'gdc-qris-mpm-reconcile-worker';
select status, return_message, start_time from cron.job_run_details
  where jobid = (select jobid from cron.job where jobname = 'gdc-qris-mpm-reconcile-worker')
  order by start_time desc limit 5;
select id, status_code, error_msg, created from net._http_response order by created desc limit 5;
```

Respons yang diharapkan: `status_code = 200`. `401` berarti secret tidak sama; `NULL`/error URL berarti secret Vault `SUPABASE_URL` belum dibuat.

### 1b. Pembayaran yang terlambat

Worker memeriksa payment `PENDING` (paling lama dulu, maksimal 20 per run) dan payment `EXPIRED` karena deadline selama 24 jam terakhir (maksimal 10 per run).

- Jika GDC melaporkan status `00` dan order masih memenuhi syarat, pembayaran dilunasi lewat `settle_gdc_qris_mpm_payment` seperti biasa.
- Jika GDC melaporkan `00` tetapi order sudah dibatalkan/kedaluwarsa/di-refund, settlement ditolak dan payment ditandai `error_code = 'PAID_AFTER_EXPIRY_NEEDS_REVIEW'`. Dana sudah diterima merchant: admin harus memutuskan refund manual atau menghidupkan kembali order. Cari dengan:

```sql
select order_id, merchant_id, amount, reference_no, updated_at
from public.gdc_qris_mpm_payments
where error_code = 'PAID_AFTER_EXPIRY_NEEDS_REVIEW' order by updated_at desc;
```

Tambahkan skenario ini ke uji staging: bayar QR setelah deadline + masa tenggang, lalu pastikan payment ditandai (atau dilunasi jika order masih hidup).

## 2. Konfigurasi gateway dan deploy function

`supabase/config.toml` menetapkan satu blok `functions.gdc-qris-mpm` dengan `verify_jwt = true`. Endpoint ini hanya untuk user login dan handler tetap memvalidasi token dengan `auth.getUser()` serta memanggil RPC `is_admin()` untuk preview admin. **Jangan** mengatasi error dengan menonaktifkan verifikasi JWT.

Di mesin tepercaya yang sudah login Supabase CLI, set ref yang telah diverifikasi:

```sh
supabase login
export SUPABASE_PROJECT_REF="<project-ref-staging-yang-sudah-diverifikasi>"
supabase functions deploy gdc-qris-mpm --project-ref "$SUPABASE_PROJECT_REF"
```

Pastikan deployment selesai tanpa error dan function tersebut tercatat pada project staging yang sama dengan frontend. Deploy website saja tidak mendeploy Edge Function.

## 3. Pasang credential GDC sandbox sebagai Edge Function Secrets

Gunakan Supabase Edge Function Secrets pada project staging. Dari CLI, cara repo yang konsisten dengan runbook secrets lain adalah memakai env-file di luar repo:

```sh
mkdir -p "$HOME/.config/sadesa"
chmod 700 "$HOME/.config/sadesa"
umask 077
$EDITOR "$HOME/.config/sadesa/gdc-sandbox.env"
```

Isi **nilai yang benar-benar diberikan GDC untuk sandbox**, dengan nama variabel berikut:

```dotenv
GDC_CLIENT_KEY=<client-key-sandbox>
GDC_CLIENT_SECRET=<client-secret-sandbox>
GDC_PRIVATE_KEY_PEM=<PKCS8-PEM-sandbox-dengan-baris-baru-di-escape-sebagai-\n>
GDC_PARTNER_ID=<partner-id-UUID-sandbox>
GDC_CHANNEL_ID=<channel-id-sandbox>
GDC_DEVICE_ID=<device-id-sandbox>
GDC_API_BASE_URL=https://neo-sandbox-api.gdc.co.id/snap
```

`GDC_API_BASE_URL` bersifat opsional karena source memakai host sandbox tersebut sebagai default. Kunci privat harus berupa PEM PKCS#8 yang mulai dengan `-----BEGIN PRIVATE KEY-----`; kode mengubah escape literal `\n` menjadi baris baru. Jangan gunakan format `BEGIN RSA PRIVATE KEY` kecuali GDC memberi instruksi dan source disesuaikan secara teruji.

Kirim env-file ke project staging yang sama:

```sh
supabase secrets set --project-ref "$SUPABASE_PROJECT_REF" \
  --env-file "$HOME/.config/sadesa/gdc-sandbox.env"
supabase secrets list --project-ref "$SUPABASE_PROJECT_REF"
```

Verifikasi hanya **nama** secret yang muncul; jangan menyalin nilai secret ke terminal output, chat, atau log. Setelah dipastikan tersimpan pada secret manager yang disetujui, hapus salinan lokal dengan aman sesuai kebijakan organisasi.

Handler juga menggunakan runtime variables Supabase `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, dan `SUPABASE_ANON_KEY` untuk memvalidasi user dan membaca mapping. Ini berbeda dari credential GDC. Jangan menyalin service-role key ke env frontend atau memasukkannya ke Git. Jika handler mengatakan konfigurasi runtime Supabase belum lengkap, periksa project deployment/runtime dengan administrator Supabase—jangan menebak atau menggandakan secret managed.

## 4. Diagnosis “Unauthorized” setelah deploy

Gunakan browser DevTools → Network saat menekan tombol uji, lalu buka `POST .../functions/v1/gdc-qris-mpm`. Jangan menyalin header `Authorization`, cookies, atau token. Periksa project ref URL, HTTP status, dan response body saja.

- **401, body menyebut sesi tidak ditemukan:** request tiba tanpa `Authorization: Bearer <user access token>`. Masuk ulang, pastikan sesi Supabase browser aktif, lalu uji lagi.
- **401, body menyebut sesi tidak valid/kedaluwarsa:** token pengguna ditolak oleh Supabase Auth. Refresh halaman atau logout/login ulang. Jangan mengganti token dengan publishable/anon key.
- **500, body menyebut runtime Supabase belum lengkap:** deployment/runtime function tidak memiliki salah satu konfigurasi Supabase yang dibutuhkan. Periksa project URL dan runtime variables melalui Dashboard/log dengan admin Supabase.
- **403, akses admin diperlukan:** sesi valid, tetapi user tersebut tidak lolos RPC `is_admin()` pada database project itu.
- **409, mapping belum tersimpan atau host bukan sandbox:** simpan mapping MID/account number yang benar pada record pengajuan dan pastikan host sandbox tetap aktif.
- **502 / pesan konfigurasi GDC:** baru pada tahap ini periksa nama dan kelengkapan GDC secrets, status credential sandbox, format PKCS#8 PEM, dan log provider yang hanya mencatat status/kode respons tanpa secret.
- **Gateway error seperti “Invalid JWT” tanpa body JSON dari handler:** gateway menolak token sebelum function berjalan. Periksa sesi browser, project URL, dan `verify_jwt`; jangan mematikan pemeriksaan JWT.

## 5. Tes penerimaan sandbox

1. Login sebagai admin pada staging dan konfirmasi mapping GDC tersimpan.
2. Klik **Buat QR Uji Sandbox · Rp1.000** sekali.
3. Pastikan respons sukses bertanda `PREVIEW`, nominal `1000` IDR, QR content dan reference terisi.
4. Pastikan fungsi memakai endpoint sandbox dan tidak membuat order Sadesa atau mengubah status aktivasi. Source preview memang tidak menulis ke `orders` atau `gdc_qris_mpm_payments`.
5. **Jangan bayar QR uji.** Hentikan pengujian bila QR ternyata memakai host/credential production.

Simpan bukti hasil (waktu, project ref non-rahasia, HTTP status, response code provider, deployment version) tanpa token, signature, account secret, atau isi private key. Uji checkout transaksi nyata dan settlement tetap membutuhkan rencana staging terpisah.
