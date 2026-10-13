# Audit Jalur Ojek / Kurir Lokal dan Ongkir Internal

**Tanggal:** 13 Oktober 2026  
**Scope:** hanya `delivery_type = INTERNAL` untuk pesanan marketplace: konfigurasi admin, quote ongkir, checkout, batas jarak/wilayah, pemilihan kurir, tawaran kurir, pickup, pengantaran, proof of delivery, antar sendiri merchant, fee platform, earning kurir, dan transisi status. **Ekspedisi sengaja tidak dibahas.**

**Metode:** static audit source React/TypeScript, SQL migration/bootstrap, dan pemeriksaan kontrak. Belum ada replay ke database staging/production pada sesi ini.

## Verdict

**Jalur ojek sudah memiliki kontrol server yang cukup baik, tetapi belum aman dinyatakan production-ready.**

Masalah paling penting:

1. **Alur admin `OrderDetailsDialog` memiliki pilihan/status yang tidak cocok dengan RPC terbaru.** Pilihan antar sendiri dari status `NEW` mencoba langsung `NEW → DELIVERING`, padahal RPC hanya mengizinkan `NEW → PROCESSED`. Tombol generik “Kirim” pada order INTERNAL dari `PROCESSED` mencoba `PROCESSED → SENT`, padahal `SENT` hanya diizinkan untuk ekspedisi. Ini dapat membuat aksi admin gagal walaupun UI menyediakan tombolnya.
2. **Setting `courier_commission` pada AdminSettings bukan sumber komisi payout aktual.** Payout memakai tabel `commission_fee_settings`, sedangkan AdminSettings menyimpan setting legacy di `app_settings`. Admin dapat mengubah angka yang terlihat seperti komisi kurir, tetapi angka itu tidak dipakai oleh `apply_transaction_commission`.
3. **Ongkir ojek memakai formula jarak, bukan zona.** `shipping_base_fee` terhubung dan dipakai, tetapi `shipping_zones` hanya disimpan admin dan tidak digunakan untuk menghitung ongkir internal.
4. **Self-delivery sudah memiliki snapshot fee dan ledger, tetapi checkout buyer tidak secara eksplisit memberi pilihan self-delivery.** Pilihan antar sendiri dibuat merchant setelah order masuk. Itu benar bila kebijakan bisnisnya merchant yang menentukan, tetapi harus dipastikan sesuai UX dan kebijakan operasional.

## Matriks temuan

| ID | Prioritas | Area | Temuan | Dampak |
|---|---:|---|---|---|
| OJ-01 | **P1** | Admin order state | `OrderDetailsDialog` pada `NEW` dapat memilih self-delivery lalu memanggil `merchant_transition_order(NEW, DELIVERING)`. RPC terbaru tidak mengizinkan transisi tersebut. | Aksi “Proses & Kirim Sendiri” dari dialog admin gagal dengan error invalid transition. |
| OJ-02 | **P1** | Admin order state | Tombol generik “Kirim” pada `PROCESSED` INTERNAL memanggil `SENT`; RPC terbaru hanya mengizinkan `SENT` dari `PROCESSED` untuk `EXPEDITION`. | Tombol UI terlihat valid tetapi gagal untuk order ojek. Assignment harus melalui `dispatch_merchant_order` atau `create_delivery_offer`. |
| OJ-03 | **P1** | Komisi kurir | `AdminSettingsPage` menyimpan `app_settings('courier_commission')`, tetapi `apply_transaction_commission` membaca `commission_fee_settings` berdasarkan `owner_type = 'COURIER'`. | Admin dapat mengubah komisi yang tidak berdampak pada payout/ledger aktual; risiko salah hitung fee dan laporan keuangan. |
| OJ-04 | **P1** | Ongkir admin | Form admin menjelaskan ongkir berdasarkan “jarak dan zona”, namun RPC `marketplace_shipping_contract_quote` untuk INTERNAL hanya memakai `shipping_base_fee` (`base_fee`, `per_km_fee`, `min_fee`, `max_fee`, `free_shipping_min_order`). | Perubahan `shipping_zones` tidak mengubah ongkir pembeli. Admin bisa salah mengira zona aktif. |
| OJ-05 | **P1** | Database deployment | Trigger pembatasan lokal hanya efektif bila migration/bootstrap delivery restriction sudah diterapkan pada database target. Validator bootstrap sebelumnya gagal pada marker bundle lain, sehingga deployment consistency belum terbukti. | Ada risiko database target tidak memiliki trigger/state machine versi yang sama dengan source. |
| OJ-06 | **P2** | Pemilihan kurir | `getAvailableCouriers` membaca tabel `couriers` langsung dan menghitung active orders dari client; dispatch server hanya memilih kurir aktif, approved, available, punya GPS, dan terdekat dari pickup. | Daftar manual di UI dapat berbeda dari kandidat authoritative server; jarak/availability bisa berubah antara daftar dan assign. Assignment tetap divalidasi server, tetapi UX bisa membingungkan. |
| OJ-07 | **P2** | Tawaran kurir | Auto dispatch membuat tawaran 5 menit dan mengubah order ke `ASSIGNED`, sementara `courier_id` tetap NULL sampai kurir menerima. | Ini secara kontrak benar, tetapi order dapat lama berada `ASSIGNED` jika tawaran kedaluwarsa; perlu recovery/redispatch yang diuji. |
| OJ-08 | **P2** | Earning | `courier_earning_estimate` diinisialisasi sama dengan `shipping_cost`; fee commission baru diterapkan melalui `apply_transaction_commission` saat order final. | UI kurir menampilkan estimasi gross, sementara payout akhir dapat berkurang oleh fee. Label perlu jelas agar tidak dianggap pendapatan bersih. |
| OJ-09 | **P2** | Self-delivery | Fee antar sendiri dihitung dari `shipping_cost`, lalu disnapshot ke order dan ledger saat status menjadi `DELIVERING`. | Kontrak sudah auditable, tetapi perlu uji retry, perubahan setting setelah order dibuat, dan status ledger ketika order dibatalkan/refund. |
| OJ-10 | **P2** | Test | Test khusus delivery/ojek tidak dijalankan karena `node_modules` belum tersedia. | Validasi saat ini static; belum membuktikan RPC berjalan pada database aktif. |

## Alur yang benar dan sudah terhubung

### 1. Checkout buyer → quote ongkir ojek

Untuk `delivery_type = INTERNAL`:

1. Buyer memilih alamat dan koordinat tujuan.
2. `quote_marketplace_checkout` mengambil harga produk dari database.
3. Server mengambil koordinat merchant dari `merchants.location_lat/location_lng`.
4. Server menghitung jarak haversine dari merchant ke tujuan.
5. Server membaca `app_settings.shipping_base_fee`.
6. Server menghitung:

```text
base_fee + round(distance_km × per_km_fee)
```

7. Nilai dibatasi oleh `min_fee` dan `max_fee`.
8. Bila subtotal mencapai `free_shipping_min_order`, ongkir menjadi 0.
9. Hasil quote mengembalikan subtotal, shipping cost, discount, total, dan distance.

**Penilaian:** sumber nominal server sudah benar dan tidak mempercayai nominal ongkir dari client.

### 2. Checkout submit

Saat submit, fungsi create checkout menghitung ulang jarak dari koordinat yang tersimpan/diterima server dan membuat snapshot kontrak shipping. `buyer_distance_km` disimpan pada order, sehingga trigger delivery restriction dapat memvalidasi order.

**Kontrol yang baik:** harga, voucher, subtotal, shipping contract, dan total tidak seharusnya dapat diubah hanya dengan memanipulasi client.

### 3. Pembatasan ojek lokal

Frontend menandai order wajib memakai metode lain jika:

- jarak lebih dari 10 km;
- kabupaten/kota berbeda;
- kecamatan berbeda.

Database memiliki trigger `validate_delivery_method_restriction` yang memeriksa:

- `delivery_type = INTERNAL`;
- `buyer_distance_km <= 10`;
- city tujuan vs city merchant bila keduanya tersedia;
- district tujuan vs district merchant bila keduanya tersedia.

**Penilaian:** defence-in-depth sudah ada. Frontend bukan satu-satunya pengaman.

**Catatan:** pembandingan wilayah database memakai nama wilayah merchant dan nama tujuan, bukan hanya ID. Jika metadata merchant kosong, pengecekan wilayah dilewati dan jarak menjadi otoritas utama. Itu sesuai komentar migration, tetapi kelengkapan data merchant harus dipastikan.

### 4. Merchant memilih kurir

Dari status `PROCESSED`, merchant dapat:

- memilih **Antar Sendiri**; atau
- membuka **Kurir Desa**.

Untuk kurir desa:

- UI dapat meminta auto-assign ke `dispatch_merchant_order`;
- server memilih kurir `ACTIVE`, `APPROVED`, `is_available = true`, memiliki GPS, dan terdekat dari pickup;
- server membuat `delivery_assignments` status `OFFERED` selama 5 menit;
- order menjadi `ASSIGNED`, tetapi `orders.courier_id` masih NULL sampai kurir menerima.

**Penilaian:** pemisahan `ASSIGNED` dan `COURIER_ACCEPTED` sudah benar secara konsep.

### 5. Kurir menerima/menolak

`respond_delivery_offer`:

- hanya dapat dipanggil oleh courier yang memiliki assignment;
- memeriksa status `OFFERED` dan expiry;
- bila menerima, assignment menjadi `ACCEPTED`, order mendapat `courier_id`, status `COURIER_ACCEPTED`;
- bila menolak, assignment menjadi `REJECTED`, courier dimasukkan ke `courier_rejected_ids`, order kembali `ASSIGNED`.

**Penilaian:** assignment scoped dan acceptance authoritative di server.

### 6. Pickup → delivery → selesai

State machine kurir:

```text
ASSIGNED
  → COURIER_ACCEPTED
  → PICKED_UP
  → DELIVERING
  → DELIVERED
  → DONE
```

- `courier_pickup_order` memvalidasi user adalah courier approved dan pemilik order.
- `courier_start_delivery` hanya menerima status `PICKED_UP` atau legacy `SENT`.
- `courier_complete_delivery` mewajibkan proof path dan idempotent terhadap retry setelah status `DELIVERED`.
- Feed aktif kurir mencakup order `MARKETPLACE`, bukan hanya direct courier delivery.

**Penilaian:** kontrol ownership dan proof sudah baik.

## Detail temuan kritis

### OJ-01 — self-delivery dari dialog admin tidak cocok dengan RPC

Di `src/components/order/OrderDetailsDialog.tsx`, saat status order `NEW`, pilihan antar sendiri menyebabkan:

```text
p_to_status = 'DELIVERING'
```

Namun `merchant_transition_order` terbaru mengizinkan dari `NEW` hanya:

```text
PROCESSED, CANCELED, REJECTED
```

`DELIVERING` hanya valid dari `PROCESSED`/`READY` untuk self-delivery.

**Perbaikan yang disarankan:**

- ubah alur UI menjadi `NEW → PROCESSED`, lalu merchant memilih antar sendiri dari status `PROCESSED`; atau
- buat RPC khusus yang atomik untuk menerima order + memilih self-delivery dengan guard dan snapshot fee.

Jangan hanya melonggarkan state machine tanpa memastikan payment, stock, dan fee snapshot tetap benar.

### OJ-02 — tombol “Kirim” generic masih memakai status `SENT`

Di dialog yang sama, untuk order `PROCESSED` non-pickup/non-expedition, tombol generic memanggil `SENT`. Pada RPC terbaru:

```text
PROCESSED → SENT hanya jika delivery_type = EXPEDITION
```

Untuk `INTERNAL`, status yang benar adalah assignment (`ASSIGNED`) melalui:

- `dispatch_merchant_order(order_id)`; atau
- `create_delivery_offer(order_id, courier_id)`.

**Perbaikan yang disarankan:** hapus tombol generic tersebut untuk INTERNAL atau ganti dengan flow assign courier.

### OJ-03 — dua sumber konfigurasi komisi kurir

Ditemukan dua kontrak:

1. `AdminSettingsPage` menyimpan `app_settings` dengan key `courier_commission`.
2. `apply_transaction_commission` membaca `commission_fee_settings` untuk `owner_type = 'COURIER'` dan `charge_courier_delivery`.

Sumber kedua yang dipakai payout aktual adalah halaman/admin wallet commission. Sumber pertama berpotensi legacy/dead setting.

**Perbaikan yang disarankan:**

- pilih satu sumber authoritative;
- hapus atau beri label legacy pada `courier_commission` di AdminSettings;
- buat satu halaman pengaturan yang langsung mengubah `commission_fee_settings`;
- tambahkan test yang memastikan perubahan admin mengubah fee payout pada order delivery.

### OJ-04 — formula jarak vs zona

Untuk ojek, `shipping_base_fee` terhubung dan digunakan. Tetapi `shipping_zones` tidak dipakai oleh quote server.

Jika bisnis memang ingin:

```text
Dalam Desa = Rp5.000
Antar Desa = Rp10.000
Luar Kecamatan = Rp20.000
```

maka fungsi quote harus membaca zona. Jika bisnis ingin formula jarak, UI zona harus dihapus/nonaktifkan atau diubah menjadi dokumentasi, bukan setting aktif.

## Audit self-delivery merchant

Migration terbaru membuat aturan:

- `self_delivery_fee` default `{ percent: 0, enabled: false }`;
- ketika merchant memilih self-delivery, fee dihitung dari `shipping_cost`;
- fee dan persentase disnapshot ke `orders` dan `merchant_delivery_fee_ledger`;
- status fee `DUE` hanya jika enabled dan amount > 0, selain itu `WAIVED`;
- order diberi `is_self_delivery = true` dan status `DELIVERING`.

**Yang sudah benar:** fee tidak dihitung ulang berdasarkan setting baru setelah order berjalan; ada snapshot untuk audit.

**Yang wajib diuji:**

- klik/retry merchant pada status `PROCESSED`;
- dua request self-delivery bersamaan;
- perubahan persentase setelah order `DELIVERING`;
- order self-delivery dibatalkan;
- refund setelah ledger fee dibuat;
- apakah merchant boleh menandai `DELIVERED` tanpa proof;
- apakah status `DONE` otomatis atau menunggu buyer.

## Rekomendasi prioritas untuk ojek

### P0/P1 sebelum production

1. Perbaiki `OrderDetailsDialog` agar seluruh tombol menghasilkan transisi yang valid untuk INTERNAL.
2. Pastikan route aktif merchant/admin hanya memakai satu state machine yang sama.
3. Hapus/redirect setting `courier_commission` legacy agar tidak menyesatkan admin.
4. Putuskan model ongkir: zona atau formula jarak. Implementasikan hanya satu model authoritative.
5. Terapkan migration delivery restriction, state machine, self-delivery fee, checkout quote, dan bootstrap secara konsisten pada staging.
6. Uji database aktif dengan skenario:
   - order INTERNAL jarak 0, 5, 10, 10.01 km;
   - beda kecamatan dan beda kabupaten;
   - koordinat merchant kosong;
   - merchant menerima order lalu assign otomatis;
   - tawaran expired lalu redispatch;
   - dua kurir menerima offer hampir bersamaan;
   - kurir menolak lalu kurir kedua menerima;
   - retry pickup/start/complete;
   - self-delivery retry dan fee ledger;
   - fee commission aktif/nonaktif.

### P2

1. Buat RPC/list authoritative untuk kandidat kurir agar UI manual tidak membaca data mentah dan berbeda dari dispatch server.
2. Tampilkan kepada kurir secara eksplisit: ongkir pembeli, estimasi gross, fee platform, dan estimasi net.
3. Tambahkan recovery job/endpoint untuk order `ASSIGNED` dengan offer expired.
4. Tambahkan test kontrak untuk setiap transisi state INTERNAL.
5. Tambahkan test konfigurasi bahwa setting admin ongkir dan komisi benar-benar memengaruhi RPC payout/quote.

## File bukti utama

- `src/pages/CheckoutPage.tsx`
- `src/lib/deliveryRestriction.ts`
- `src/lib/courierApi.ts`
- `src/pages/merchant/MerchantOrdersPage.tsx`
- `src/pages/admin/AdminSettingsPage.tsx`
- `src/pages/admin/AdminWalletCommissionPage.tsx`
- `src/components/order/OrderDetailsDialog.tsx`
- `src/components/admin/CourierAssignDialog.tsx`
- `src/pages/courier/CourierDeliveryPage.tsx`
- `supabase/migrations/20261013052500_marketplace_checkout_shipping_quote.sql`
- `supabase/migrations/20261013054500_checkout_p1_item_normalization_shipping_contracts.sql`
- `supabase/bootstrap/106_20261013050000_self_delivery_admin_fee.sql`
- `supabase/bootstrap/07_20260917214000_to_20260919090000.sql`
- `supabase/bootstrap/06_20260914153000_to_20260918170000.sql`
- `supabase/bootstrap/88_20261009092000_commission_wallet_operations.sql`

## Status verifikasi

- Test kontrak khusus delivery/ojek tidak dapat dijalankan karena `node_modules` belum tersedia.
- Audit ini adalah audit static source/migration; belum menggantikan test integrasi terhadap database staging aktif.

**Kesimpulan akhir:** nominal ongkir ojek di checkout sudah server-authoritative dan pembatasan lokal memiliki trigger database. Tetapi jalur admin memiliki mismatch status yang dapat menggagalkan operasi, dan konfigurasi komisi kurir memiliki dua sumber yang tidak sama. Dua hal tersebut harus dibereskan sebelum alur ojek dianggap benar seluruhnya.
