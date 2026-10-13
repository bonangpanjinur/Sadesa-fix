# Audit Keseluruhan Ongkos Kirim

**Tanggal:** 13 Oktober 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Cakupan:** Admin, checkout pembeli, kurir lokal/ojek, pedagang/merchant, self-delivery, ekspedisi, konfigurasi tarif, rekonsiliasi COD, dan deployment database.

## Kesimpulan

Alur ongkos kirim sudah memiliki fondasi server-side yang cukup baik: quote dan checkout menghitung ulang jarak dari koordinat server, ongkir disimpan pada order, kontrak pricing dapat diaudit, serta pembatasan delivery lokal memiliki guard database. Namun **belum boleh dinyatakan production-ready** sebelum sumber konfigurasi dan flow operasional berikut dibereskan:

1. **P0 — Rekonsiliasi COD sebelumnya menghitung uang yang harus disetor terlalu besar** karena menambahkan `shipping_cost` ke `orders.total`, padahal `total` sudah termasuk ongkir. Bug ini sudah diperbaiki di UI kurir.
2. **P1 — Migrasi zona ongkir terbaru belum masuk bootstrap deployment.** Migrasi dan bundle final sudah ditambahkan sebagai `112_20261013183000_local_shipping_distance_zone_surcharge.sql`.
3. **P1 — Admin masih memiliki dua sumber konfigurasi komisi kurir.** UI legacy sudah diarahkan ke halaman wallet; sumber konfigurasi aktif sekarang `commission_fee_settings`.
4. **P1 — Flow tombol admin belum selalu cocok dengan state machine kurir.** Antar sendiri dari `NEW` dan tombol generik `SENT` untuk `INTERNAL` dapat gagal pada RPC terbaru.
5. **P1 — Sumber zona vs formula jarak harus ditetapkan sebagai kontrak bisnis tunggal.** Source sekarang sudah membaca `shipping_zones` sebagai surcharge zona, tetapi setting dan validasi admin harus dipastikan konsisten.

## Matriks temuan

| ID | Prioritas | Area | Temuan | Dampak | Status |
|---|---:|---|---|---|---|
| ONG-P0-01 | **P0** | Kurir/COD | UI menghitung expected cash sebagai `order.total + order.shipping_cost`, padahal total checkout sudah `subtotal + ongkir + biaya COD - diskon`. | Kurir diminta menyetor lebih besar; rekonsiliasi menjadi shortage palsu. | **Diperbaiki** |
| ONG-P1-02 | **P1** | Deployment | Migration zona ongkir `20261013183000` belum tercantum di bootstrap. | Database baru/target tertentu dapat tetap memakai formula lama tanpa surcharge zona. | **Diperbaiki** |
| ONG-P1-03 | **P1** | Admin/komisi | Pengaturan legacy `courier_commission` di `app_settings` bukan sumber yang dibaca payout aktual; payout membaca `commission_fee_settings`. | Admin dapat mengubah angka yang terlihat aktif tetapi tidak memengaruhi settlement kurir. | **Diperbaiki** — kontrol legacy dihapus dan diarahkan ke halaman wallet canonical |
| ONG-P1-04 | **P1** | Admin/state | Dialog admin dapat mencoba `NEW → DELIVERING` untuk self-delivery, sedangkan RPC mengharuskan `NEW → PROCESSED` lebih dulu. | Tombol admin gagal walaupun UI terlihat tersedia. | **Belum diperbaiki** |
| ONG-P1-05 | **P1** | Admin/state | Tombol “Kirim” generik dapat mencoba `PROCESSED → SENT` untuk order `INTERNAL`; state itu hanya valid untuk ekspedisi pada RPC terbaru. | Assignment kurir lokal gagal atau operator mendapat error membingungkan. | **Belum diperbaiki** |
| ONG-P1-06 | **P1** | Checkout | Quote dan create sudah sama-sama menghitung jarak server-side, tetapi tetap perlu assertion/test bahwa quote yang ditampilkan dan final create selalu identik. | Perubahan koordinat/setting antara quote dan submit dapat membingungkan buyer tanpa observability memadai. | **Perlu test staging** |
| ONG-P1-07 | **P1** | Checkout | Validitas produk, voucher, stok, total, dan item harus tetap hanya berasal dari RPC authoritative; cart/local state tidak boleh menjadi sumber nominal. | Manipulasi harga/discount/ongkir dapat memengaruhi order bila ada jalur legacy yang masih terbuka. | **Perlu verifikasi staging/RLS** |
| ONG-P2-08 | P2 | Kurir | `courier_earning_estimate` di UI dapat menampilkan gross shipping, sedangkan komisi dipotong saat payout. | Kurir dapat mengira estimasi sebagai pendapatan bersih. | **Belum diperbaiki** |
| ONG-P2-09 | P2 | Kurir | Fallback kartu tawaran memakai full `shipping_cost` bila `courier_earning_estimate` null. | Estimasi earning dapat terlalu tinggi jika kebijakan fee/komisi berubah. | **Belum diperbaiki** |
| ONG-P2-10 | P2 | Pedagang | Self-delivery sudah menyimpan snapshot fee dan ledger, tetapi perlu uji concurrency, retry, cancel, dan refund. | Risiko ledger fee tidak selaras dengan lifecycle order. | **Perlu test staging** |
| ONG-P2-11 | P2 | Admin | Validasi konfigurasi tarif perlu menjamin fee non-negatif, `min_fee <= max_fee`, zona terurut, jarak positif, nama terisi, dan tidak overlap. | Setting invalid dapat menghasilkan quote tidak terduga. | **Belum diperbaiki** |
| ONG-P2-12 | P2 | Ekspedisi | Rate card/provider/service/berat/ETA perlu ditampilkan dan disnapshot pada order sebelum pembayaran. | Buyer/admin sulit merekonsiliasi nominal ekspedisi dengan provider yang dipilih. | **Sebagian tersedia; perlu smoke test** |

## Temuan yang sudah diperbaiki

### 1. Expected cash COD tidak lagi menggandakan ongkir

Sebelumnya:

```text
expected_cash = order.total + order.shipping_cost
```

Padahal checkout authoritative sudah menyimpan:

```text
order.total = subtotal + shipping_cost + cod_service_fee - discount
```

Sekarang UI kurir memakai `order.total` langsung untuk daftar COD, default input setor, dan dialog konfirmasi. Kolom `shipping_cost` tetap dibaca untuk kebutuhan data/kompatibilitas, tetapi tidak lagi ditambahkan ke expected cash.

### 2. Bootstrap migrasi zona ongkir ditambahkan

Migrasi source:

```text
archive/supabase/migrations/20261013183000_local_shipping_distance_zone_surcharge.sql
```

Bundle deployment:

```text
supabase/bootstrap/112_20261013183000_local_shipping_distance_zone_surcharge.sql
```

Implementasi pricing INTERNAL saat ini menggunakan:

```text
base_fee + round(distance_km × per_km_fee) + zone_surcharge
```

Kemudian nominal dibatasi oleh `min_fee` dan `max_fee`, serta menjadi gratis ketika subtotal memenuhi `free_shipping_min_order`.

### 3. Sumber komisi kurir Admin disatukan

Kartu komisi kurir pada `AdminSettingsPage` tidak lagi membaca atau menulis `app_settings.courier_commission`, yang merupakan konfigurasi legacy dengan semantik berbeda. Admin sekarang diarahkan ke `/admin/wallet-commissions`, yang membaca dan menyimpan `commission_fee_settings` — tabel yang digunakan payout aktual, termasuk `fee_percent`, `is_enabled`, dan `charge_courier_delivery`.

## Audit per area

### Admin

- Admin dapat mengatur base/per-km/min/max/free-shipping dan zona.
- Konfigurasi zona sekarang sudah dipakai fungsi quote setelah migrasi terbaru diterapkan.
- Masih ada risiko salah sumber pada komisi kurir: `app_settings.courier_commission` harus dihapus, diberi label legacy, atau diarahkan langsung ke `commission_fee_settings`.
- Tombol operasional order perlu dipetakan satu per satu ke RPC state machine; jangan memakai status `SENT` generik untuk delivery `INTERNAL`.
- Tambahkan validasi server dan UI untuk zona serta tarif invalid.

### Checkout pembeli

- Quote mengambil harga produk dan koordinat merchant dari server.
- Jarak dihitung server-side menggunakan koordinat merchant dan tujuan.
- Checkout final menghitung ulang kontrak ongkir dan menyimpan `shipping_pricing_contract` pada order.
- Pickup menghasilkan ongkir nol; expedition memakai rate card/provider; internal memakai kontrak lokal.
- Risiko yang masih perlu dibuktikan dengan staging adalah kesetaraan quote vs create, jalur legacy yang masih dapat dipanggil, serta race pada voucher/stok/order multi-merchant.

### Kurir

- Assignment, acceptance, ownership, pickup, start delivery, dan proof of delivery memiliki guard server-side.
- Rekonsiliasi COD sudah diperbaiki agar memakai total order authoritative.
- Estimasi earning perlu dibedakan jelas antara gross ongkir, fee platform, dan net payout.
- Auto-dispatch/offer expiry memerlukan recovery/redispatch yang diuji pada staging.

### Pedagang

- Merchant dapat memilih antar sendiri atau memakai kurir desa setelah order diproses.
- Self-delivery menyimpan snapshot persentase/nominal fee dan ledger per order, sehingga perubahan setting berikutnya tidak mengubah histori.
- Perlu pengujian retry simultan, cancel setelah fee dibuat, refund, dan kewajiban proof of delivery.
- Flow merchant/admin harus memastikan status order tidak melompati state yang diperlukan.

## Validasi yang dijalankan

| Pemeriksaan | Hasil |
|---|---|
| `pnpm exec tsc --noEmit` | **Lulus** |
| `pnpm test` | **Lulus — 184 file, 739 passed, 20 skipped** |
| `pnpm build` | **Lulus** |
| ESLint file kurir yang diubah | **Lulus** |
| `pnpm validate:migrations` | **Lulus**, dengan warning duplicate timestamp lama |
| `pnpm validate:db-bootstrap` | **Gagal pada 6 bundle lama** yang sudah tidak repeatable (`47`, `50`, `51`, `52`, `71`, `111`); bundle baru `112` sudah repeatable dan tidak menambah error baru |
| Audit staging/production database | **Belum dijalankan** karena kredensial/environment staging tidak tersedia pada sesi ini |

## Prioritas tindak lanjut

### P0 — sebelum transaksi live

1. Deploy dan smoke-test migration/bootstrap ongkir.
2. Uji COD: subtotal, ongkir, biaya COD, diskon, expected cash, collected cash, dan variance.
3. Pastikan buyer tidak dapat mengubah `shipping_cost`, `total`, `subtotal`, item price, atau voucher melalui direct table write/legacy RPC.

### P1 — sebelum rollout luas

1. **Selesai:** satukan sumber komisi kurir ke `commission_fee_settings` dan hilangkan kontrol legacy.
2. Perbaiki dialog admin agar self-delivery dan assignment INTERNAL memanggil flow yang sesuai state machine.
3. Tambahkan assertion/test quote-vs-create.
4. Pastikan seluruh target database menerima bootstrap `112` atau migration equivalent.

### P2 — penguatan operasional

1. Tambahkan validasi tarif/zona dan audit log perubahan konfigurasi.
2. Tampilkan gross fee, platform fee, dan net earning secara terpisah kepada kurir.
3. Tambahkan integration test self-delivery, offer expiry/redispatch, ekspedisi rate card, refund, dan concurrency.
