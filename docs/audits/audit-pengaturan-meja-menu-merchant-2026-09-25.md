# Audit Pengaturan Meja dan Menu Merchant

**Repository:** `bonangpanjinur/Sadesa-fix`  
**Tanggal:** 25 September 2026  
**Scope:** pengaturan meja, QR menu, katalog produk, kategori POS, dan kontrak database terkait.

## Ringkasan eksekutif

Fitur merchant sudah memiliki fondasi operasional yang lengkap: CRUD meja, status meja, order meja/KDS, QR menu per meja, preview menu publik, pencetakan/unduh QR, katalog produk merchant sebagai sumber katalog, kategori bertingkat, stok per outlet, serta RPC publik yang memvalidasi produk dan stok.

Audit menemukan satu celah **P1 integritas data** di boundary database: validasi relasi `pos_tables`/`pos_table_orders` belum secara eksplisit memastikan konsistensi tenant-outlet-meja pada seluruh jalur tulis. Selain itu, beberapa aksi CRUD frontend tidak memeriksa objek `error` dari Supabase sehingga UI dapat menampilkan toast sukses walaupun operasi gagal.

Perbaikan sudah diterapkan pada branch kerja ini.

## Matriks fitur

| Area | Status | Implementasi yang ditemukan | Catatan |
|---|---|---|---|
| CRUD meja | Ada | `POSMejaPage`, `pos_tables` | Tambah, edit, nonaktifkan; sudah diperbaiki agar error database tidak tertelan |
| Area/section | Ada | Filter area dan pilihan section | Section preset; belum ada CRUD section custom |
| Kapasitas dan catatan meja | Ada | Field `capacity`, `notes` | Validasi utama masih perlu diperkuat di database |
| Status meja | Ada | `transition_pos_table`, state machine | Expected status mencegah stale update; kini juga memeriksa akses outlet |
| Order meja internal | Ada | `create_pos_table_order` | Atomic insert + occupied; kini memeriksa akses outlet dan relasi meja |
| KDS/order lifecycle | Ada | `transition_pos_table_order` | pending → cooking → ready → served → paid; cancel pada tahap awal; kini scoped outlet |
| QR per meja | Ada | `POSMenuQRPage`, URL encoded | Preview, copy link, PNG, print bridge, print all |
| Menu publik | Ada | `MenuPublicPage`, RPC `get_public_pos_menu` | Menampilkan produk aktif dan availability berdasarkan stok outlet |
| Order dari QR | Ada | RPC `create_public_pos_table_order` | Validasi tenant, meja, produk, qty, stok, reserve stock |
| Katalog merchant | Ada | `MerchantProductsPage` | Merchant catalog menjadi source of truth; POS menjadi projection kompatibilitas |
| Produk POS | Ada | `POSProdukPage` | SKU/barcode, varian, export CSV, label barcode, link ke katalog merchant |
| Kategori POS | Ada | `POSKategoriPage` | Parent/sub-category dan sort order; error CRUD kini ditampilkan dengan benar |
| Sinkronisasi merchant → POS | Ada | trigger `sync_merchant_product_to_pos` | Backfill dan stock row per outlet tersedia |
| Multi-outlet | Sebagian | `activeOutlet`, stock per outlet, QR table outlet | Pengaturan meja sudah diperketat pada boundary database; kebutuhan uji staging tetap ada |

## Temuan audit dan tindakan

### P1 — Relasi meja/order belum hard-enforced secara menyeluruh

**Risiko:** jalur tulis langsung dapat menghasilkan order yang tenant atau outlet-nya tidak sama dengan meja yang direferensikan, sehingga denah meja, KDS, dan QR menu berpotensi menampilkan data lintas scope.

**Perbaikan:** migration `20260925234500_pos_table_menu_settings_hardening.sql`:

- menambah trigger validasi tenant-outlet pada `pos_tables`;
- menambah validasi `pos_table_orders.table_id` terhadap tenant dan outlet meja;
- memperketat `transition_pos_table`, `transition_pos_table_order`, dan `create_pos_table_order` dengan `pos_user_can_access_outlet`;
- mempertahankan expected-status check dan server-side transition rules;
- membatasi EXECUTE RPC workflow ke role `authenticated`.

### P1 — CRUD meja/kategori mengabaikan error Supabase

**Risiko:** operasi insert/update/delete dapat gagal tetapi UI tetap memberi toast sukses dan menutup dialog.

**Perbaikan:**

- `POSMejaPage.tsx` kini melempar error untuk update, insert, dan soft-delete meja;
- `POSKategoriPage.tsx` kini melempar error untuk insert, update, dan delete kategori;
- pesan kegagalan diteruskan ke handler toast yang sudah ada.

### P2 — Validasi input meja masih dominan di frontend

**Status:** belum diubah dalam patch ini.

**Rekomendasi berikutnya:** tambahkan constraint/trigger database untuk nama non-empty, kapasitas 1–50, batas panjang `section`/`notes`, serta uniqueness nama meja per outlet bila aturan bisnis mengharuskannya.

### P2 — Pengelolaan QR belum memiliki lifecycle revocation

**Status:** URL QR berbasis tenant + table ID dan meja nonaktif/cleaning diblokir RPC menu. Belum ada token rotasi atau audit scan.

**Rekomendasi berikutnya:** tambahkan `qr_version`/revocation token jika merchant membutuhkan invalidasi QR tanpa mengganti meja.

### P2 — Order internal dari dialog meja belum memilih item produk

**Status:** `POSMejaPage` membuat order internal dengan `p_items: []`; order QR publik memiliki item dan reservation stok.

**Rekomendasi berikutnya:** arahkan pembuatan order internal ke kasir atau tambahkan pemilih katalog/varian agar order manual tidak kosong.

## Verifikasi

- Lint file yang diubah: **lulus**.
- Test kontrak POS terarah: **4 test files, 13 tests lulus**.
- `git diff --check`: **lulus**.
- Artefak migration dan bootstrap: **tersedia dan tidak kosong**.
- Typecheck penuh: **gagal pada 17 error existing di 5 file lain** (`ContextualRecommendation`, `ProductMerchantMap`, `AuthContext`, `googleMaps`, `AdminOrderFraudBlocksPage`); tidak ada error pada file meja/kategori yang diubah.

## Artefak perubahan

- `archive/supabase/migrations/20260925234500_pos_table_menu_settings_hardening.sql`
- `supabase/bootstrap/46_20260925234500_pos_table_menu_settings_hardening.sql`
- `src/pages/pos/POSMejaPage.tsx`
- `src/pages/pos/POSKategoriPage.tsx`
- `supabase/bootstrap/manifest.json`
