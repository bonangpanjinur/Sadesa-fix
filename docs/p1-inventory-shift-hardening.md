# P1 Inventory dan Shift Kasir

## Ringkasan

P1 memindahkan operasi stok dan cash session yang sebelumnya terdiri dari beberapa write client-side ke fungsi PostgreSQL atomic. Tujuannya adalah mencegah stok berubah tanpa ledger mutation, cash mutation tercatat tanpa aggregate session, dan closing shift menggunakan angka penjualan lintas sesi yang tidak tepat.

## Inventory

`public.adjust_pos_stock(...)` mengunci baris `pos_stock` dengan `FOR UPDATE`, memvalidasi tenant/outlet, menghitung delta berdasarkan jenis mutasi, menolak stok negatif, memperbarui quantity, dan menulis `pos_stock_mutations` di transaksi yang sama. `POSStokPage` sekarang menggunakan helper `adjustPOSStock`; update stok dan ledger tidak lagi dilakukan sebagai dua request client-side terpisah.

Checkout POS dari P0 juga tetap mengunci stok dan menulis mutation secara atomic. Dengan demikian, adjustment manual dan checkout memakai pola ledger yang sama. Pengurangan bahan baku berbasis resep juga berada di transaksi checkout P0.

## Shift dan cash session

Migration menambahkan `cash_session_id` pada `pos_sales` dan trigger yang secara otomatis menghubungkan penjualan baru ke shift `open` berdasarkan tenant, outlet, dan cashier. Partial unique index membatasi satu shift aktif per cashier/outlet.

`open_cash_session` melakukan validasi actor dan outlet serta membuat sesi dengan session number database-generated. `record_cash_mutation` mengunci sesi, memastikan statusnya masih open, membuat mutation, dan memperbarui `cash_in_total` atau `cash_out_total` dalam satu transaksi. `close_cash_session` mengunci sesi, menghitung ulang penjualan completed berdasarkan cash session, menghitung cash in/out dari mutation ledger, menghitung expected balance dan difference, lalu menutup sesi.

UI `POSKasPage` memakai tiga RPC tersebut. Expected balance yang ditampilkan saat sesi aktif kini memakai `cash_sales_total` milik sesi, bukan seluruh penjualan hari berjalan. Hal ini mencegah penjualan pada shift sebelumnya ikut masuk ke expected cash shift baru.

## Laporan shift

`POSLaporanKasirPage` menampilkan penjualan tunai dan expected cash per sesi selain opening balance, closing balance, dan difference. Angka closing yang telah dihitung database dapat digunakan sebagai rekonsiliasi utama, sementara agregasi performa kasir tetap dipisahkan sebagai laporan penjualan.

## Validasi

Unit test untuk wrapper RPC inventory dan shift ditambahkan. TypeScript, ESLint, full Vitest suite, production build, dan `git diff --check` berhasil lulus pada sandbox.

## Checklist staging sebelum production

Staging perlu membersihkan duplicate open sessions sebelum membuat partial unique index. Setelah migration diterapkan, jalankan skenario opening shift bersamaan, duplicate open shift, wrong tenant/outlet/cashier, adjustment purchase/transfer-out/absolute adjustment, insufficient stock, cash in/out, closing dua kali, closing concurrent, sale masuk ke shift aktif, serta sale setelah shift closed.

Lakukan juga verifikasi bahwa laporan periode tidak mencampur session lintas outlet dan bahwa session yang dibuka sebelum awal periode tetapi ditutup di dalam periode memiliki perlakuan bisnis yang disepakati. RLS integration test wajib dijalankan dengan minimal dua tenant dan dua outlet.
