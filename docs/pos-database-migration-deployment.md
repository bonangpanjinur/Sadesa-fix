# Laporan Deployment Migrasi Database POS

**Repository:** `bonangpanjinur/remix-of-umkm-sadesa`  
**Branch:** `main`  
**Commit terbaru:** `f290f74`  
**Status push:** Sudah berhasil dipush dan diverifikasi sama dengan `origin/main`.

## Ringkasan

Perubahan POS yang sudah dipush menambahkan penguatan otorisasi, invariant pembayaran, dan fondasi checkout yang lebih aman. Migration database yang paling penting untuk deployment ini adalah `20260828160000_pos_payment_invariants.sql`. File yang sama tersedia dalam bentuk bootstrap di `supabase/bootstrap/08_20260826010000_to_20260829160000.sql`.

Migration tersebut menambahkan validasi database agar nilai pembayaran POS konsisten dengan total transaksi. Pembayaran tunai tidak boleh kurang dari total dan kembalian harus sesuai. Pembayaran non-tunai harus sama dengan total transaksi dan tidak boleh menghasilkan kembalian. Validasi ini berada di database sehingga tidak hanya bergantung pada UI atau client PWA.

Implementasi konsolidasi juga menambahkan `20260904090000_pos_unified_transaction_history.sql`. Migration ini membuat `pos_transaction_migration_map` secara idempotent dan view `pos_unified_transaction_history` untuk menggabungkan histori `pos_sales` dengan transaksi legacy yang belum memiliki pasangan modern. View memakai `security_invoker` dan tetap mengikuti RLS; migration tersebut tidak membuka kembali penulisan transaksi baru ke `pos_transactions`.

## File migrasi yang relevan

| Urutan | File | Tujuan | Risiko |
|---|---|---|---|
| 1 | `archive/supabase/migrations/20260823070000_atomic_pos_checkout.sql` | RPC checkout atomic beserta side effect transaksi/stok | Tinggi; wajib diuji pada staging |
| 2 | `archive/supabase/migrations/20260823071000_payment_invoice_idempotency.sql` | Idempotency pembayaran/invoice | Tinggi; cegah transaksi ganda |
| 3 | `archive/supabase/migrations/20260823091000_harden_pos_sale_amounts.sql` | Penguatan nilai amount pada penjualan POS | Tinggi; dapat menolak data lama yang tidak valid |
| 4 | `archive/supabase/migrations/20260823092000_harden_pos_sale_totals.sql` | Penguatan konsistensi total penjualan | Tinggi; perlu verifikasi data existing |
| 5 | `archive/supabase/migrations/20260828160000_pos_payment_invariants.sql` | Invariant pembayaran dan kembalian | Tinggi; migration utama dari perubahan terbaru |
| 6 | `supabase/bootstrap/07_20260822040000_to_20260825200000.sql` | Bundle bootstrap fungsi/schema POS yang digunakan repository | Tinggi; hanya jalankan pada database yang menggunakan jalur bootstrap |
| 7 | `supabase/bootstrap/08_20260826010000_to_20260829160000.sql` | Bootstrap bundle yang memuat invariant pembayaran dan hardening POS sampai workflow transition | Tinggi; jangan dijalankan dua kali terhadap target yang sama |
| 8 | `supabase/bootstrap/09_20260904090000_to_20260904090000.sql` | Bootstrap standalone untuk mapping idempotent dan unified reporting histori legacy/modern | Tinggi; validasi mapping tenant/outlet pada staging sebelum rollout |
| 9 | `archive/supabase/migrations/20260904090000_pos_unified_transaction_history.sql` | Sumber migration untuk bundle bootstrap unified history | Referensi sumber; gunakan bundle bootstrap untuk jalur bootstrap |
| 10 | `supabase/bootstrap/10_20260905000000_merchant_pos_product_catalog.sql` | Mapping Merchant–POS, projection katalog, dan backfill row stok per outlet aktif | Tinggi; jangan menimpa stok existing dan jangan menjalankan bersama representasi migration-history |
| 11 | `archive/supabase/migrations/20260905000000_merchant_pos_product_catalog.sql` | Representasi migration-history untuk mapping katalog dan stok outlet | Referensi alternatif; gunakan hanya jika target memakai migration history |
| 12 | `supabase/bootstrap/11_20260905100000_pos_legacy_reconciliation.sql` | Laporan exception dan rekonsiliasi exact-match legacy tanpa menyalin transaksi | Tinggi; jalankan hanya setelah snapshot dan review exception tersedia |
| 13 | `archive/supabase/migrations/20260905100000_pos_legacy_reconciliation.sql` | Representasi migration-history laporan rekonsiliasi legacy | Referensi alternatif; jangan diterapkan bersama bundle bootstrap yang sama |

Direktori `archive/supabase/migrations` dan `supabase/bootstrap` memiliki peran berbeda. Tim deployment harus memastikan terlebih dahulu apakah environment target dikelola menggunakan histori migration Supabase atau bundle bootstrap repository. **Jangan menjalankan kedua representasi migration yang sama pada database target yang sama tanpa memastikan idempotency-nya.**

## Prosedur staging yang disarankan

Pertama, buat backup database dan catat schema/function yang sudah terpasang. Selanjutnya jalankan migration pada staging menggunakan mekanisme deployment database yang menjadi standar environment tersebut. Jika staging memakai migration history, gunakan file di `archive/supabase/migrations`; jika staging memakai bootstrap, gunakan file di `supabase/bootstrap` sesuai urutan nama file.

Sebelum deployment, jalankan validasi repository:

```bash
cd /path/to/remix-of-umkm-sadesa
bash scripts/validate-migrations.sh supabase/bootstrap
bash scripts/validate-migrations.sh archive/supabase/migrations
STAGING_BOOTSTRAP_REPLAY=true bash scripts/validate-bootstrap-staging.sh
```

Validator staging memeriksa seluruh bundle berdasarkan manifest, mengulang deployment untuk menguji idempotency, memastikan tabel/view POS dan fungsi katalog serta rekonsiliasi tersedia, memeriksa kolom mapping Merchant, serta menghitung outlet aktif yang belum memiliki row stok. Setelah migration selesai, lakukan smoke test berikut pada staging: buat transaksi tunai dengan pembayaran lebih besar dan pastikan kembalian benar; coba pembayaran tunai kurang dari total dan pastikan ditolak; coba pembayaran non-tunai dengan nominal berbeda dari total dan pastikan ditolak; kirim request checkout yang sama dua kali menggunakan request key yang sama dan pastikan hanya satu penjualan tercatat; lalu verifikasi pengurangan stok, voucher, loyalty, dan payment record.

### Rekonsiliasi histori legacy

Ambil snapshot dan simpan hasil laporan sebelum melakukan perubahan status mapping:

```sql
SELECT reconciliation_status, count(*)
FROM public.pos_legacy_reconciliation_report
GROUP BY reconciliation_status
ORDER BY reconciliation_status;
```

Review semua baris `merchant_tenant_unmapped`, `outlet_mapping_required`, `multiple_modern_candidates`, dan `total_mismatch`. Hanya setelah exception tersebut diselesaikan secara manual, administrator boleh menjalankan `SELECT * FROM public.reconcile_exact_legacy_pos_transactions();`. Fungsi tersebut hanya memasangkan baris dengan tenant, nomor transaksi, dan total yang identik serta memiliki tepat satu kandidat modern. Fungsi tidak membuat `pos_sales`, tidak menghapus `pos_transactions`, dan tidak menyalin item atau pembayaran.

Acceptance criteria rekonsiliasi adalah tidak ada `exact_match_ready`, `total_mismatch`, atau `multiple_modern_candidates` yang belum ditinjau; seluruh baris yang tidak dapat dipasangkan tetap terlihat pada unified history; dan jumlah transaksi serta total finansial legacy yang direkonsiliasi cocok dengan laporan audit yang disetujui.

## Deployment production

Deploy ke production hanya setelah staging lulus dan tidak ada data transaksi existing yang melanggar invariant. Jalankan migration dalam maintenance window singkat atau periode transaksi rendah. Simpan output migration, timestamp deployment, hash commit, dan hasil smoke test sebagai bukti release.

Setelah deployment, pantau error RPC checkout, penolakan payment invariant, jumlah transaksi gagal, serta antrean outbox cetak. Jika jumlah penolakan meningkat, hentikan rollout aplikasi terlebih dahulu dan periksa apakah client masih mengirim `discount_amount`, `total`, `payment_amount`, atau `change_amount` dengan kontrak lama.

## Rollback dan catatan keselamatan

Rollback utama sebaiknya berupa **restore backup atau forward-fix**, bukan langsung menghapus constraint atau trigger. Penghapusan validasi pembayaran dapat membuka kembali risiko transaksi tidak konsisten. Jika migration gagal sebelum selesai, ikuti mekanisme transaction rollback dari tool database yang digunakan. Jika migration sudah berhasil tetapi aplikasi mengalami incompatibility, rollback aplikasi ke commit sebelumnya hanya aman setelah dipastikan payload aplikasi lama masih kompatibel dengan invariant baru.

Perubahan database belum dieksekusi ke project Supabase production oleh proses ini; yang dilakukan adalah push kode dan penyediaan file migration. Eksekusi migration membutuhkan akses ke project database target serta konfirmasi environment staging/production yang digunakan.

## Checklist deployment

| Pemeriksaan | Status |
|---|---|
| 14 commit POS sudah dipush ke `origin/main` | Selesai |
| Working tree lokal bersih setelah push | Selesai |
| Build aplikasi berhasil pada validasi terakhir | Selesai |
| Test suite berhasil pada validasi terakhir | Selesai |
| Migration file tersedia di repository | Selesai |
| Unified history migration dan bootstrap bundle tersedia | Selesai |
| Validator staging mencakup katalog dan stok POS | Selesai |
| Migration tervalidasi pada database staging | Belum dilakukan |
| Backup database production | Harus dilakukan oleh operator deployment |
| Smoke test checkout production | Belum dilakukan |
| Monitoring pascadeployment | Harus disiapkan saat release |

## Referensi repository

- [Migration atomic POS checkout](../archive/supabase/migrations/20260823070000_atomic_pos_checkout.sql)
- [Migration invariant pembayaran POS](../archive/supabase/migrations/20260828160000_pos_payment_invariants.sql)
- [Bootstrap POS sampai workflow transition](../supabase/bootstrap/08_20260826010000_to_20260829160000.sql)
- [Bootstrap unified transaction history](../supabase/bootstrap/09_20260904090000_to_20260904090000.sql)
- [Unified transaction history source migration](../archive/supabase/migrations/20260904090000_pos_unified_transaction_history.sql)
- [Script validasi migration](../scripts/validate-migrations.sh)
