# P0 POS Price Book, Loyalty, and Offline Staging Validation

Dokumen ini melengkapi `docs/rls-staging-runbook.md` untuk validasi RPC price book, loyalty ledger, locking, idempotency, dan offline price conflict. Jalankan hanya terhadap project staging/disposable, tidak terhadap production.

## Environment fixture

Gunakan file environment lokal yang tidak di-commit, misalnya `.env.pos.staging`:

```dotenv
RUN_RLS_INTEGRATION=true
RUN_POS_INTEGRATION=true
SUPABASE_TEST_URL=https://staging-project.supabase.co
SUPABASE_TEST_ANON_KEY=staging-publishable-key
POS_TEST_STAFF_EMAIL=pos-staff@example.test
POS_TEST_STAFF_PASSWORD=staging-password
POS_TEST_TENANT_ID=tenant-fixture-uuid
POS_TEST_OUTLET_ID=outlet-fixture-uuid
POS_TEST_PRODUCT_ID=product-fixture-uuid
POS_TEST_CUSTOMER_ID=customer-fixture-uuid
POS_TEST_CASHIER_ID=authenticated-user-uuid
```

Akun staff harus menjadi `pos_users` aktif pada tenant dan outlet fixture. Produk harus memiliki stock row. Customer fixture sebaiknya khusus integration test karena test earn dan redeem mengubah saldo. Rule `earn` dan `redeem` aktif harus tersedia di tenant tersebut.

## Run

```bash
set -a
. ./.env.pos.staging
set +a
pnpm test:integration
```

Suite akan menjalankan RLS isolation, effective price resolution, loyalty earn idempotency, dan concurrent redemption. Tanpa `RUN_POS_INTEGRATION=true`, test price/loyalty otomatis skip agar unit test lokal tidak membutuhkan database.

## Expected controls

| Skenario | Hasil yang diharapkan |
|---|---|
| Effective price | Harga berasal dari price book yang cocok dengan tenant, outlet, segment, periode, dan priority. |
| Earn duplicate | Pemanggilan kedua dengan idempotency key sama mengembalikan entry yang sama dan tidak menambah saldo dua kali. |
| Concurrent redeem | Dua redeem penuh yang berjalan bersamaan hanya boleh menghasilkan satu success. |
| Offline price change | RPC mengembalikan error code `P0001`; queue menyimpan status `conflict` dan tidak retry otomatis. |
| Offline unchanged price | Sale diproses melalui `process_pos_sale` dengan request key offline yang sama dan dapat di-retry idempotently. |

Migration harus diterapkan sebelum suite dijalankan. Bila kredensial staging belum tersedia, hasil `Tests ... skipped` bukan bukti bahwa RPC aman; itu hanya berarti validation database belum dijalankan.
