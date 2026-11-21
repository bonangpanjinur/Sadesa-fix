# Runbook GDC QRIS MPM — Sandbox

Panduan ini untuk memasang dan menguji QRIS dinamis GDC pada **Supabase sandbox/staging**. Jangan gunakan QR uji untuk pembayaran. Jangan menerapkan secret sandbox ke production.

## 1. Prasyarat dan batas aman

- Pastikan project ref berasal dari Supabase Dashboard → Project Settings → General dan environment-nya memang staging/sandbox.
- Pastikan URL Supabase yang dipakai frontend cocok dengan project ref tersebut. `supabase/config.toml` mencantumkan project ref repo, tetapi jangan anggap itu bukti bahwa production/staging yang aktif sama.
- Siapkan kredensial sandbox dari portal atau petugas GDC. Jangan memasukkan kredensial produksi.
- Pastikan perubahan database GDC sudah diterapkan ke project yang sama. Migration source GDC ada di bootstrap `134`, `140`, `141`, `142`, dan `143`, sesuai urutan bootstrap. Workflow `scripts/deploy-supabase-staging.sh` menerapkan semua bootstrap, bukan hanya migration GDC; tinjau target dan prosedur database sebelum menjalankannya.
- Jangan menaruh GDC private key, client secret, service-role key, atau token pada frontend, variabel `VITE_*`, Vercel/Railway, Git, tiket, atau log.

## 2. Konfigurasi gateway dan deploy function

`supabase/config.toml` menetapkan satu stanza `verify_jwt = false` untuk `gdc-qris-mpm` agar request mencapai handler dan mendapat diagnosis terarah. Ini **bukan endpoint publik**: handler wajib memvalidasi `Authorization: Bearer <user access token>` dengan `auth.getUser()` dan memanggil RPC `is_admin()` sebelum akses admin/provider. Jangan menghapus pemeriksaan tersebut atau mempercayai header dari klien tanpa validasi.

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
- **Gateway error sebelum ada body handler:** pastikan URL menunjuk project yang benar, request menyertakan publishable `apikey`, dan deployed function/config adalah versi terbaru. Jika gateway dikonfigurasi berbeda di Dashboard, cocokkan dengan repo; jangan menghapus validasi JWT di handler.

## 5. Tes penerimaan sandbox

1. Login sebagai admin pada staging dan konfirmasi mapping GDC tersimpan.
2. Klik **Buat QR Uji Sandbox · Rp1.000** sekali.
3. Pastikan respons sukses bertanda `PREVIEW`, nominal `1000` IDR, QR content dan reference terisi.
4. Pastikan fungsi memakai endpoint sandbox dan tidak membuat order Sadesa atau mengubah status aktivasi. Source preview memang tidak menulis ke `orders` atau `gdc_qris_mpm_payments`.
5. **Jangan bayar QR uji.** Hentikan pengujian bila QR ternyata memakai host/credential production.

Simpan bukti hasil (waktu, project ref non-rahasia, HTTP status, response code provider, deployment version) tanpa token, signature, account secret, atau isi private key. Uji checkout transaksi nyata dan settlement tetap membutuhkan rencana staging terpisah.
