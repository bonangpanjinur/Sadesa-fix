# Audit Checkout dan QRIS MPM GDC — 1 November 2026

## Ringkasan

Lampiran pengguna menunjukkan request berulang ke `POST /rest/v1/rpc/touch_admin_login_activity` yang gagal `404`, dengan pesan PostgREST bahwa `public.touch_admin_login_activity(p_device_id)` tidak ada di schema cache. Source repository sebenarnya sudah memiliki fungsi tersebut pada bootstrap `111_20261013140000_admin_login_activity.sql` dan client mengirim `p_device_id` yang cocok. Jadi ini adalah **drift antara schema database yang sedang dipakai dan source/migration repository** (atau schema cache PostgREST yang belum diperbarui), bukan endpoint checkout yang membuat RPC tersebut salah. Forward migration baru memuat ulang definisi RPC dan meminta PostgREST reload schema.

Pengguna memilih pembayaran QRIS dinamis langsung ke akun merchant dan memberikan dokumentasi Neo/GDC. Source repository sebelumnya belum menyimpan GDC Merchant ID/Account Number per aplikasi dan belum memiliki adapter GDC untuk checkout. Perubahan yang dibuat menambahkan dua field itu saat admin menerbitkan QRIS dan jalur konfigurasi untuk aplikasi QRIS yang sudah aktif, opsi QRIS MPM untuk checkout akun yang login, Edge Function backend untuk membuat/query QR, serta settlement order yang memverifikasi referensi dan nominal.

## Temuan penting dan mitigasi

| Area | Temuan | Perbaikan yang disiapkan |
|---|---|---|
| Login activity 404 | Source berisi RPC dengan signature yang benar, tetapi backend yang menghasilkan log tampak belum mengeksposnya. | Migration forward-only meng-`CREATE OR REPLACE` fungsi, memastikan tabel/policy dan grants, lalu `NOTIFY pgrst, 'reload schema'`. Deployment migration tetap diperlukan agar 404 hilang pada database aktif. |
| Data aplikasi QR Merchant | Skema aplikasi menyimpan referensi/gambar QRIS, bukan identitas merchant GDC yang dipakai endpoint MPM. | Kolom `gdc_merchant_id` dan `gdc_account_number`, input admin saat penerbitan, dan guard DB yang mewajibkan keduanya saat status diaktifkan. |
| Integritas nominal/provider | QR dinamis tidak boleh dibentuk dari amount yang dapat dimanipulasi frontend. | Edge Function membaca order milik buyer dari database, menggunakan total order di server, lalu meminta QR MPM GDC. Query pembayaran memeriksa referensi, external ID, service code, mata uang dan jumlah sebelum RPC settlement. |
| Credential | API GDC memerlukan key/secret/private key dan signature SNAP. | Kredensial hanya dibaca dari environment server/Supabase Edge Function Secrets, bukan `VITE_*` atau database setting yang dikirim ke browser. Default base URL adalah sandbox Neo/GDC. |
| Callback | Dokumentasi menyebut callback, tetapi autentikasi callback yang ditampilkan tidak cukup menjelaskan proses verifikasi signature untuk membangun verifier yang aman. | Belum menerima callback. Halaman pembayaran melakukan query status yang ditandatangani dari backend (polling); callback URL jangan didaftarkan sebelum verifikasi signature callback dikonfirmasi dengan GDC. |
| QR dinamis kedaluwarsa | Potongan dokumentasi generate yang diberikan tidak mencantumkan masa berlaku atau endpoint pembatalan QR. Order saat ini punya tenggat pembayaran 30 menit. | Implementasi menolak pembuatan QR baru setelah tenggat dan memakai tenggat order yang ada. Perilaku QR yang sudah terbit setelah tenggat belum dapat dipastikan; perlu konfirmasi GDC sebelum mengaktifkan transaksi live. |

## Alur implementasi yang disiapkan

1. Buyer yang login memilih QRIS Dinamis untuk satu merchant; checkout tetap membentuk order melalui RPC otoritatif yang ada.
2. Setelah order dibuat, halaman pembayaran meminta Edge Function `gdc-qris-mpm` membuat atau memuat QR. Function memastikan pemilik order, status/tenggat order, aplikasi QRIS merchant berstatus `ACTIVE`, serta adanya GDC Merchant ID dan Account Number.
3. Backend mengambil B2B access token menggunakan signature RSA-SHA256, lalu menandatangani request QR MPM dengan HMAC-SHA512 sesuai dokumen SNAP GDC.
4. Backend menyimpan `partner_reference_no`, external ID, GDC reference, jumlah, konten QR, dan status; browser hanya mendapat data tampilan QR, tidak mendapat identitas akun provider atau API secret.
5. Browser menanyakan status lewat Edge Function. Hanya respons query GDC dengan referensi yang cocok dan amount IDR sama persis yang diteruskan ke `settle_gdc_qris_mpm_payment`; settlement dikunci row-nya dan idempoten.

Dokumentasi yang dirujuk: [Neo/GDC QRIS MPM Generate, Query, autentikasi dan Callback](https://neo-docs.gdc.co.id/documentation#terminologies). Jalur yang digunakan adalah `POST /v1.0/qr/qr-mpm-generate`, query `POST /v1.0/qr/qr-mpm-query`, service code `47`, dan response success `00`.

## Status verifikasi / deployment

Perubahan repository belum sama dengan deploy ke Supabase. Belum ada migration, Edge Function, secret, callback, atau transaksi provider yang diterapkan ke project aktif. Integrasi belum boleh dianggap siap live sebelum migration/bootstrap bundle dan function dideploy, secret server diisi, credential sandbox diuji, serta GDC mengonfirmasi masa berlaku QR dan tata cara signature callback. Gunakan sandbox endpoint lebih dulu; jangan mengaktifkan endpoint produksi hanya dengan mengganti URL.


## Hasil validasi lokal

- Frontend production build, TypeScript `tsc --noEmit`, lint pada file frontend terkait, migration order, dan bootstrap bundle validation berhasil.
- Tes terarah checkout/admin-login/payment readiness/client GDC: 15 lulus.
- Deno check pada Edge Function berhasil setelah penyesuaian buffer WebCrypto.
- Full test suite: 841 lulus, 20 skipped, 3 gagal pada dua kelompok yang tidak terkait file perubahan ini (`MealTimeReminder.test.tsx` dua kasus; `ridePickupLandmark.contract.test.ts` satu kontrak manifest lama). Kegagalan kontrak manifest mengharapkan nama source yang tidak cocok dengan entry baseline repository; tes komponen pengingat makan juga berada di luar checkout/payment.
