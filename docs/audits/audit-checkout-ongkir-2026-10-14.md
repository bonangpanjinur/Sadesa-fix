# Audit Alur Checkout dan Ongkos Kirim

**Tanggal:** 14 Oktober 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Cakupan:** cart, checkout login/guest, quote ongkir, pembuatan order, pickup, kurir lokal, ekspedisi, voucher, stok, pembayaran, admin configuration, dan deployment bootstrap.

## Verdict

**NO-GO untuk menyatakan checkout + ongkos kirim production-ready.**

Fondasi authoritative sudah baik dan regression test yang relevan lulus, tetapi masih ada gap operasional/deployment yang harus ditutup sebelum rollout luas.

## Ringkasan temuan

| ID | Prioritas | Temuan | Dampak | Status |
|---|---:|---|---|---|
| CO-14-01 | **P1** | `validate-bootstrap-bundles.py` masih gagal pada 7 bundle non-repeatable: 47, 50, 51, 52, 71, 111, dan 114. | Source migration, bootstrap instalasi baru, dan database target dapat tidak konsisten; pipeline deployment tidak memiliki sinyal hijau. | **Open** |
| CO-14-02 | **P1** | Tabel `marketplace_expedition_rate_cards` sudah dipakai RPC, tetapi tidak ditemukan halaman/UI CRUD admin untuk mengelolanya. | Provider ekspedisi dapat aktif tetapi checkout gagal dengan tarif tujuan belum tersedia; operator tidak punya jalur operasional yang jelas untuk mengisi tarif. | **Open** |
| CO-14-03 | **P1** | `create_marketplace_checkout` dan guest wrapper memanggil fungsi legacy/unpriced, lalu melakukan patch `shipping_cost`, `total`, dan metadata kontrak. | Ada risiko mismatch/race di reservation, voucher, flash sale, COD fee, trigger, dan status order antara pembuatan legacy dan patch baru. | **Open — wajib integration test staging** |
| CO-14-04 | **P2** | Subtotal/price line di cart berasal dari snapshot localStorage; quote server hanya menggantikan subtotal/total ringkasan, bukan rincian harga per item. | Buyer bisa melihat rincian produk yang berbeda dari harga authoritative saat harga/flash sale berubah. | **Open** |
| CO-14-05 | **P2** | Identitas selection cart masih berbasis `product.id`, sementara beberapa line dapat memiliki kombinasi topping berbeda. | Toggle, hapus per merchant, atau selection dapat memperlakukan beberapa line topping sebagai satu produk. | **Open — perlu regression test duplicate line** |

## Kontrol yang sudah benar

1. **Quote dan nominal final dihitung server-side.** `quote_marketplace_checkout` mengambil harga produk/flash sale dari database, menghitung jarak dari koordinat merchant dan tujuan, serta mengembalikan subtotal, ongkir, diskon, total, dan kontrak pricing.
2. **Submit tidak mempercayai nominal dari browser.** Frontend mengirim item, delivery intent, tipe pengiriman, metode pembayaran, voucher, dan idempotency key; tidak mengirim `p_total` atau ongkir final.
3. **Idempotency checkout tersedia.** Authenticated checkout memakai advisory lock dan `marketplace_checkout_idempotency`; guest memakai session hash + checkout key.
4. **Multi-merchant diblokir.** Frontend dan RPC menolak transaksi yang berisi lebih dari satu merchant.
5. **Formula zona terbaru sudah masuk runtime source dan bootstrap bundle 112.** `20261013183000_local_shipping_distance_zone_surcharge.sql` membaca `shipping_zones` sebagai surcharge dan menghasilkan kontrak `LOCAL_COURIER_DISTANCE_ZONE_V1`.
6. **Pickup menghasilkan ongkir nol.** Delivery non-pickup memerlukan koordinat yang valid; server melakukan validasi rentang latitude/longitude.
7. **Payment recovery tersedia.** Jika invoice online gagal setelah order dibuat, order tetap dapat ditemukan dan invoice dapat dicoba ulang dengan aman.
8. **Validasi admin tarif/zona sudah dipakai oleh `AdminSettingsPage`.** Test validasi juga mencakup fee negatif, rentang min/max, jarak zona, nama kosong, dan urutan zona.

## Detail temuan

### CO-14-01 — Validator bootstrap gagal

Perintah:

```text
python3 scripts/validate-bootstrap-bundles.py
```

Hasil saat audit:

```text
Bootstrap bundle validation FAILED
- non-repeatable bundle marker missing: 47_20260927143000_product_category_hierarchy.sql
- non-repeatable bundle marker missing: 50_20260927170000_product_food_beverage_subcategories.sql
- non-repeatable bundle marker missing: 51_20260928114500_product_kelontongan_subcategories.sql
- non-repeatable bundle marker missing: 52_20260928114600_product_agriculture_subcategories.sql
- non-repeatable bundle marker missing: 71_20261003200000_auto_confirm_new_signups.sql
- non-repeatable bundle marker missing: 111_20261013140000_admin_login_activity.sql
- non-repeatable bundle marker missing: 114_20261013220000_self_delivery_lifecycle_hardening.sql
```

Bundle 112 untuk surcharge zona terdaftar di manifest, tetapi status validator global tetap gagal karena bundle-bundle lain.

**Tindakan:** perbaiki marker/bundle yang tidak repeatable atau regenerasi bootstrap/manifest sesuai aturan deployment, lalu ulangi validator pada database staging kosong dan database yang sudah berisi schema.

### CO-14-02 — Rate card ekspedisi belum operasional dari Admin

RPC membaca:

```text
public.marketplace_expedition_rate_cards
```

Field yang diperlukan antara lain provider, service code/name, destination city, base fee, per-kg fee, min/max fee, free-shipping threshold, ETA, priority, default, dan active.

Pencarian source tidak menemukan penggunaan UI untuk `marketplace_expedition_rate_cards`, `service_code`, atau `per_kg_fee`; halaman ekspedisi yang ada hanya mengelola master `expedition_providers`.

**Dampak:** memilih `EXPEDITION` akan gagal jika tidak ada rate card aktif yang cocok dengan kota tujuan. Ini bukan sekadar konfigurasi opsional karena migration sengaja tidak melakukan seed tarif tebakan.

**Tindakan:** buat halaman CRUD Rate Card Ekspedisi dengan validasi overlap/priority/default, atau sediakan proses provisioning resmi yang terdokumentasi dan di-smoke-test.

### CO-14-03 — Create masih memakai fungsi legacy lalu patch

Pada migration `20261013054500_checkout_p1_item_normalization_shipping_contracts.sql`:

- authenticated path memanggil `create_marketplace_checkout_legacy(...)`;
- guest path memanggil `create_guest_marketplace_checkout_unpriced(...)`;
- wrapper kemudian mengunci order, memanggil `marketplace_shipping_contract_quote(...)`, lalu melakukan `UPDATE orders` untuk `shipping_cost`, `total`, shipping contract, dan snapshot ekspedisi.

Pendekatan ini masih dapat dipakai sebagai transisi, namun tidak cukup dibuktikan oleh static contract test. Risiko yang harus diuji di staging:

1. dua request paralel dengan checkout key berbeda dan stok terakhir;
2. flash sale berubah antara quote dan create;
3. voucher usage limit dipakai bersamaan;
4. reservation gagal/rollback setelah order legacy terbentuk;
5. COD fee, diskon, dan `total` tetap identik setelah patch;
6. trigger payment/status berjalan pada nilai final, bukan nilai interim;
7. guest retry mengembalikan order/token yang sama;
8. ekspedisi tidak menghasilkan partial order ketika rate card tidak tersedia.

**Tindakan:** idealnya satukan kalkulasi dan pembuatan order dalam satu fungsi domain authoritative. Jika belum, tambahkan assertion/invariant database dan integration test yang membandingkan hasil quote dengan hasil final create.

### CO-14-04 — Rincian harga cart dapat stale

`CartContext` menyimpan snapshot produk di localStorage. `CheckoutPage` sudah memakai `serverQuote` untuk subtotal, ongkir, voucher, dan total utama, tetapi daftar item masih merender data cart lokal. Jika harga produk atau flash sale berubah, buyer dapat melihat item price lama sementara subtotal server sudah berubah.

**Tindakan:** setelah quote berhasil, tampilkan harga authoritative per line atau beri label jelas bahwa harga item dapat berubah saat verifikasi server.

### CO-14-05 — Cart line identity belum sepenuhnya unik

`selectedItemIds`, `toggleItemSelection`, dan penghapusan memakai `product.id`. Namun cart dapat berisi beberapa line dengan produk dasar sama tetapi topping berbeda. Normalisasi untuk RPC memang menggabungkan kuantitas produk/topping, tetapi selection UI masih berpotensi mengubah atau menghapus line yang tidak dimaksud.

**Tindakan:** gunakan line key stabil berbasis `product.id + topping composition`, lalu tambahkan test untuk dua line produk sama dengan topping berbeda.

## Validasi yang dijalankan

| Pemeriksaan | Hasil |
|---|---|
| `pnpm install --frozen-lockfile` | Lulus |
| Test kontrak checkout/rute/zona/ekspedisi/cart | **5 file, 25 test lulus** |
| `pnpm build` | Lulus |
| `python3 scripts/validate-bootstrap-bundles.py` | **Gagal — 7 bundle marker hilang** |
| Database staging/production replay | Belum dijalankan; kredensial/database aktif tidak tersedia pada sesi audit |

## Prioritas tindak lanjut

### Sebelum production

1. Tutup CO-14-01 dan jalankan validator pada target deployment aktual.
2. Provision rate card ekspedisi yang benar atau implementasikan UI adminnya.
3. Jalankan integration test database untuk CO-14-03, khususnya stok, voucher, flash sale, COD, guest retry, dan concurrency.
4. Pastikan migration 108 + bundle 112 + bundle 114 diterapkan ke target dan PostgREST schema cache di-refresh.

### Setelah blocker ditutup

1. Satukan atau formalkan boundary legacy wrapper dengan assertion final-total.
2. Perbaiki line identity cart dan rincian harga authoritative.
3. Tambahkan observability untuk membandingkan `shipping_pricing_contract` quote vs order.

## Kesimpulan akhir

Checkout sudah **lebih aman secara nominal**: harga, ongkir, voucher, stok, dan jarak utama tidak dipercaya dari browser. Namun hasil audit tetap **NO-GO** karena deployment validator masih merah, ekspedisi belum memiliki jalur konfigurasi tarif yang operasional, dan create path belum dibuktikan terhadap race/mismatch akibat wrapper legacy.
