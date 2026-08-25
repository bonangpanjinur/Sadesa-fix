# P0 Production Controls

Dokumen ini menjelaskan kontrol transaksi production yang ditambahkan pada batch P0. Seluruh migration harus diterapkan pada Supabase staging sebelum digunakan di production.

## Migration order

Migration baru dijalankan sesuai urutan timestamp:

1. `20260825090000_production_refund_return_controls.sql`
2. `20260825093000_payment_reconciliation_ledger.sql`
3. `20260825100000_cashier_approval_and_stock_opname.sql`
4. `20260825110000_atomic_purchase_receiving.sql`
5. `20260825120000_payment_pos_anomaly_detection.sql`

Migration sebelumnya yang terkait atomic POS, inventory/shift, payment invoice, webhook, dan offline queue harus sudah diterapkan lebih dahulu.

## Refund dan return

Kasir membuat permintaan menggunakan `request_pos_sale_return`. RPC mengunci sale dan sale item, menolak quantity yang melebihi quantity terjual atau quantity yang sudah diretur, menghitung nominal dari harga item di database, dan membuat status `pending`. Approval supervisor/admin menggunakan `approve_pos_sale_return`. Approval tersebut melakukan restock dan membuat `pos_stock_mutations` dalam transaksi yang sama. Penolakan tidak boleh mengubah stok.

Halaman POS retur sudah menggunakan request RPC. Karena approval sekarang eksplisit, UI admin/supervisor perlu menampilkan item dengan status `pending`, kemudian memanggil approval RPC setelah validasi kebijakan refund.

## Payment reconciliation

Provider ingestion menggunakan `record_payment_reconciliation` melalui service role. RPC ini memvalidasi invoice, nominal expected/provider, fee, dan status. Unique key provider/invoice mencegah duplikasi. Status yang tersedia adalah `unmatched`, `matched`, `mismatch`, `refunded`, dan `settled`.

Service role tidak boleh dikirim ke browser. Dashboard admin dan merchant hanya memperoleh akses `SELECT` melalui RLS sesuai role/ownership.

## Cashier approvals dan stock opname

`request_pos_void` membuat permintaan void. `decide_pos_void` hanya dapat dipanggil oleh admin atau pemilik tenant; approval mengubah sale menjadi `void`, mengembalikan stok, dan membuat audit mutation atomic.

`approve_pos_stock_opname` mengunci setiap stock row, mengubah quantity ke hasil hitung fisik, dan menulis selisih sebagai mutation bertipe `opname`. Aplikasi harus membatasi pengeditan item opname sesuai status draft/counting.

## Purchase receiving

Halaman penerimaan PO memanggil `receive_pos_purchase_order`. RPC menolak PO cancelled/received, mengunci item, mencegah quantity diterima melebihi pesanan, memperbarui stok, menulis mutation purchase, dan mengubah status menjadi `partial` atau `received` dalam satu transaksi.

## Offline conflicts

HTTP `409` dari bridge sekarang diperlakukan sebagai conflict, bukan retryable transient error. Record disimpan dengan status `conflict`, `conflict_code`, dan `conflict_message`, serta tidak dicoba ulang otomatis. UI kasir wajib menyediakan daftar konflik dan tindakan yang jelas: review server state, batalkan sale lokal, atau kirim ulang hanya setelah penyebab konflik dikonfirmasi.

## Anomaly detection

Migration menyediakan `pos_payment_anomalies` dan `scan_pos_payment_anomalies`. Scanner admin mendeteksi mismatch payment reconciliation dan beberapa return untuk sale yang sama. Scanner bukan pengganti review manusia dan belum menjadikan anomali sebagai auto-block. Semua hasil harus ditinjau admin dengan audit trail.

## Backup restore drill

Jalankan `scripts/backup-restore-drill.sh` hanya dengan database disposable staging:

```bash
BACKUP_RESTORE_DB_URL='postgresql://...' \
BACKUP_RESTORE_TARGET_LABEL=staging \
./scripts/backup-restore-drill.sh
```

Script menolak label production-like, membuat schema-only custom dump, menyimpan checksum, dan memeriksa keberadaan tabel kritis. Restore aktual dilakukan ke database staging baru secara manual atau melalui fasilitas backup provider. Setelah restore, jalankan migration verification, RLS integration test, `pnpm test:security-api`, dan smoke test alur login/POS/payment.

## Required staging verification

Sebelum production, wajib membuktikan: seluruh migration fresh apply; RLS mutation lintas tenant; outlet isolation; refund over-quantity rejection; duplicate invoice/webhook idempotency; concurrent POS checkout; concurrent purchase receiving; offline conflict persistence; provider amount mismatch; dan restore drill dari snapshot ke database disposable.
