
## Implementasi remediasi 2026-10-02

Perubahan yang diterapkan:

- Migration `20261002130000_inventory_atomicity_hardening.sql` menambahkan floor constraint reservation pada `pos_stock`, RPC consume reservation, RPC raw-material save/adjust atomic, penerimaan batch atomic yang memperbarui saldo utama + ledger, penyelesaian transfer dengan validasi kelengkapan item dan `transfer_in` pada stok tujuan baru, RPC pembuatan PO header+detail transactional, serta RPC perubahan minimum stok dengan role/outlet scope.
- `POSBahanBakuPage`, `POSStokPage`, dan `POSPembelianPage` tidak lagi menulis saldo/detail inventory secara terpisah dari browser; jalur tersebut memakai RPC baru.
- Bootstrap bundle `63_20261002130000_inventory_atomicity_hardening.sql` dan manifest diperbarui.

Verifikasi implementasi: bootstrap validation lulus, migration validation lulus untuk 64 SQL deployment files (dengan 11 warning duplicate timestamp historis), ESLint lulus, 3 test files lulus dengan 8 test lulus dan 2 skipped, serta production build lulus.

Batasan residual: `process_pos_sale` masih belum menerima `reservation_id` sebagai bagian dari transaksi checkout yang sama, sehingga lifecycle consumed/released perlu integrasi lanjutan pada RPC checkout/order fulfillment. Konsumsi FEFO juga sudah memiliki jalur batch atomic untuk receipt, tetapi belum dihubungkan ke checkout utama.
