# RLS Integration Testing

Suite `src/test/rls.integration.test.ts` menguji Row Level Security dan isolasi multi-tenant melalui Supabase Data API dengan user fixture sungguhan. Test bersifat read-only terhadap order, merchant, dan password reset token.

## Menjalankan

Jalankan suite default dengan:

```bash
npm run test:integration
```

Tanpa fixture, suite akan melakukan skip terhadap skenario remote dan tetap lulus agar unit test lokal tidak memerlukan credential. Untuk menjalankan test RLS sebenarnya, set:

```bash
export RUN_RLS_INTEGRATION=true
export SUPABASE_TEST_URL="https://<test-project>.supabase.co"
export SUPABASE_TEST_ANON_KEY="<publishable-or-anon-key>"
export RLS_TEST_BUYER_EMAIL="buyer.fixture@example.test"
export RLS_TEST_BUYER_PASSWORD="..."
export RLS_TEST_MERCHANT_EMAIL="merchant.fixture@example.test"
export RLS_TEST_MERCHANT_PASSWORD="..."
export RLS_TEST_MERCHANT_OWN_ID="<merchant-owned-by-fixture>"
export RLS_TEST_MERCHANT_OTHER_ID="<merchant-owned-by-another-user>"
export RLS_TEST_BUYER_OWN_ORDER_ID="<order-owned-by-buyer-fixture>"
export RLS_TEST_BUYER_OTHER_ORDER_ID="<order-owned-by-another-buyer>"

npm run test:integration
```

## Fixture policy

Fixture harus dibuat pada project Supabase test atau staging, bukan production. Gunakan dua user buyer yang berbeda, dua merchant dari tenant berbeda, dan order dengan merchant serta buyer yang jelas. Jangan menyimpan password, service-role key, atau fixture credential ke repository. Service-role key tidak diperlukan oleh test ini.

## Skenario yang diuji

| Skenario | Ekspektasi |
|---|---|
| Buyer membaca dua order | Hanya order milik buyer fixture yang terlihat. |
| Merchant membaca dua merchant record | Hanya merchant milik user fixture yang terlihat. |
| Merchant membaca order tenant lain | Hasil kosong. |
| Anonymous membaca password reset token | Tidak ada baris yang terlihat; idealnya ditolak dengan `42501`. |
| Authenticated user membaca password reset token | Tidak ada baris yang terlihat; idealnya ditolak dengan `42501`. |

Suite ini adalah baseline awal. Tahap berikutnya sebaiknya menambahkan test untuk insert/update/delete, outlet-level access POS, withdrawal, courier assignment, dan role escalation. Untuk test mutation, setiap fixture harus memiliki cleanup atau memakai transaction/RPC khusus test agar data tidak tertinggal.

## Mutation dan POS outlet fixture

Mutation suite juga membutuhkan environment variable berikut:

```bash
export RLS_TEST_POS_TENANT_OWN_ID="<tenant-yang-dimiliki-merchant-fixture>"
export RLS_TEST_POS_TENANT_OTHER_ID="<tenant-milik-tenant-lain>"
export RLS_TEST_POS_OUTLET_OWN_ID="<outlet-tenant-sendiri>"
export RLS_TEST_POS_OUTLET_OTHER_ID="<outlet-tenant-lain>"
export RLS_TEST_POS_PRODUCT_OTHER_ID="<produk-pos-tenant-lain>"
```

Skenario delete menggunakan `RLS_TEST_POS_OUTLET_OTHER_ID`. Karena operasi delete bersifat nyata, ID tersebut harus menunjuk ke outlet disposable pada project staging/test. Jangan menunjuk ke outlet produksi. Test akan memeriksa bahwa operasi lintas tenant menghasilkan baris kosong atau error authorization `42501`. Jika operasi ternyata berhasil karena policy salah, test akan gagal; operasi insert memiliki cleanup defensif, sedangkan fixture delete tetap harus dipulihkan dari staging seed.

Untuk menguji granularitas outlet dalam tenant yang sama, siapkan user staff POS yang bukan owner tenant dan berikan assignment hanya ke satu outlet:

```bash
export RLS_TEST_POS_STAFF_EMAIL="pos.staff.fixture@example.test"
export RLS_TEST_POS_STAFF_PASSWORD="..."
export RLS_TEST_POS_OUTLET_ASSIGNED_ID="<outlet-yang-diberikan-ke-staff>"
export RLS_TEST_POS_OUTLET_UNASSIGNED_ID="<outlet-lain-dalam-tenant-sama>"
```

Skenario ini memastikan staff dapat membaca stok outlet yang ditugaskan, tetapi tidak dapat membaca stok outlet lain dalam tenant yang sama. Owner tenant tetap diharapkan dapat melihat seluruh outlet miliknya.
