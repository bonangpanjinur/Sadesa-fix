# POS Staging Test Matrix

Test integration POS wajib diarahkan ke Supabase staging khusus dengan fixture tenant, outlet, role, produk, stok, customer, voucher, dan cash session yang dapat di-reset. Jangan menjalankan skenario mutasi berikut terhadap production.

| Skenario | Expected result | Evidence |
|---|---|---|
| Kasir membuka `/pos/kasir` | Diizinkan | Route renders |
| Kasir membuka `/pos/kas` | Ditolak | Redirect unauthorized |
| Staff gudang membuka `/pos/stok` | Diizinkan | Route renders |
| Staff gudang membuka `/pos/kasir` | Ditolak | Redirect unauthorized |
| Dua outlet dengan user berbeda | Setiap user hanya membaca outlet assignment | RLS query result |
| Checkout dengan request key sama dua kali | Satu sale, response kedua `duplicate=true` | Sale count and response |
| Checkout dengan request key berbeda pada stok terakhir bersamaan | Hanya satu berhasil | One success, one stock conflict |
| Retry checkout setelah timeout simulasi | Tidak membuat duplicate sale | Idempotency request row |
| Voucher dengan usage limit 1 secara bersamaan | Hanya satu redemption | Voucher usage count |
| Redeem loyalty balance bersamaan | Hanya satu redemption yang berhasil | Loyalty ledger |
| Dua retur item yang sama bersamaan | Total retur tidak melebihi qty terjual | Return item aggregate |
| Dua open cash session cashier/outlet | Hanya satu session terbuka | Unique partial index |
| Close cash session dua kali | Satu berhasil, request kedua ditolak | Session status |
| Offline price conflict | Event masuk conflict state, bukan auto-post | Outbox/conflict record |
| KDS invalid transition | Ditolak server-side dan UI rollback | State before/after |
| Printer bridge mati | Sale tetap tercatat, print job retryable | Print outbox status |

Integration test dipanggil dengan `RUN_POS_INTEGRATION=true` dan environment `SUPABASE_TEST_URL`, `SUPABASE_TEST_ANON_KEY`, serta fixture IDs khusus staging. Test yang memakai mutasi harus memiliki prefix idempotency unik dan cleanup/reset fixture setelah selesai.
