# RLS Integration Test Runbook

Panduan ini menjalankan suite RLS terhadap **Supabase staging atau project test terisolasi**. Suite memakai publishable/anon key dan session user fixture; jangan gunakan service-role key dan jangan arahkan ke production.

## 1. Siapkan project staging

Buat project Supabase terpisah, terapkan semua migration terbaru, lalu buat fixture berikut:

| Fixture | Kebutuhan |
|---|---|
| Buyer A | User biasa yang memiliki satu order sendiri. |
| Buyer B | User biasa dengan order berbeda. |
| Merchant A | Merchant pada tenant pertama. |
| Merchant B | Merchant pada tenant kedua. |
| POS staff | Staff pada tenant pertama yang hanya diberi akses ke satu outlet. |
| Outlet assigned | Outlet yang boleh dibaca POS staff. |
| Outlet unassigned | Outlet tenant yang sama tetapi tidak diberikan kepada POS staff. |
| Disposable outlet | Outlet aman untuk mutation delete test. Gunakan hanya jika test delete diaktifkan atau fixture memang disposable. |

Gunakan data dummy, email dummy, dan password khusus staging. Jangan menyalin password production.

## 2. Buat file environment lokal

Simpan file seperti `.env.rls.staging` di luar Git atau pastikan masuk `.gitignore`:

```dotenv
SUPABASE_TEST_URL=https://your-staging-project.supabase.co
SUPABASE_TEST_ANON_KEY=your-staging-publishable-key

RLS_TEST_BUYER_EMAIL=buyer-a@example.test
RLS_TEST_BUYER_PASSWORD=use-a-staging-password
RLS_TEST_MERCHANT_EMAIL=merchant-a@example.test
RLS_TEST_MERCHANT_PASSWORD=use-a-staging-password
RLS_TEST_MERCHANT_OWN_ID=uuid-merchant-a
RLS_TEST_MERCHANT_OTHER_ID=uuid-merchant-b
RLS_TEST_BUYER_OWN_ORDER_ID=uuid-order-a
RLS_TEST_BUYER_OTHER_ORDER_ID=uuid-order-b

RLS_TEST_POS_TENANT_OWN_ID=uuid-tenant-a
RLS_TEST_POS_TENANT_OTHER_ID=uuid-tenant-b
RLS_TEST_POS_OUTLET_OWN_ID=uuid-outlet-a
RLS_TEST_POS_OUTLET_OTHER_ID=uuid-outlet-b
RLS_TEST_POS_PRODUCT_OTHER_ID=uuid-product-tenant-b
RLS_TEST_POS_STAFF_EMAIL=pos-staff@example.test
RLS_TEST_POS_STAFF_PASSWORD=use-a-staging-password
RLS_TEST_POS_OUTLET_ASSIGNED_ID=uuid-outlet-assigned
RLS_TEST_POS_OUTLET_UNASSIGNED_ID=uuid-outlet-unassigned
```

Nilai ID harus berasal dari database staging. Pastikan Buyer A dan Buyer B benar-benar berbeda; demikian juga Merchant A/Merchant B dan outlet assigned/unassigned.

## 3. Jalankan test

Dari root repository:

```bash
RLS_ENV_FILE=.env.rls.staging ./scripts/run-rls-staging.sh
```

Script akan menolak URL yang tidak tampak seperti staging. Untuk project test yang URL-nya tidak mengandung kata `staging`, gunakan override secara sadar:

```bash
ALLOW_NON_STAGING_RLS_TARGET=true \
RLS_ENV_FILE=.env.rls.test \
./scripts/run-rls-staging.sh
```

Override tersebut hanya boleh digunakan untuk project yang benar-benar disposable dan tidak menyimpan data production.

## 4. Skenario yang dijalankan

Suite saat ini memeriksa read isolation buyer dan merchant, akses password reset token, insert outlet lintas tenant, update produk tenant lain, delete outlet tenant lain, read stock tenant lain, serta read stock outlet yang tidak di-assign pada tenant yang sama.

RLS yang benar dapat menghasilkan error authorization `42501` atau response kosong akibat row-level filtering. Keduanya diterima sebagai penolakan akses. Hasil yang mengembalikan data tenant lain, mengubah row tenant lain, atau menghapus fixture non-disposable adalah failure kritis.

## 5. Setelah test selesai

Hapus file environment lokal atau pastikan tidak pernah di-commit. Jika test mutation membuat data probe, verifikasi cleanup melalui dashboard staging. Jangan menjalankan test delete pada production. Simpan output test pada CI artifact tanpa menyertakan password, access token, atau response yang memuat data pribadi.

## 6. CI dengan secret GitHub

Untuk menjalankan suite secara terjadwal di GitHub Actions, gunakan environment `staging` dan repository secrets untuk credential. Password fixture sebaiknya berupa akun test yang dapat di-reset, bukan akun staf nyata. Tambahkan job terpisah dari unit test dan beri approval environment sebelum menjalankan mutation test.
