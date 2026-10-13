# Audit Alur Checkout dan Ongkos Kirim

**Tanggal:** 13 Oktober 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Scope:** konfigurasi admin, cart, checkout login/guest, quote server, pembuatan order, voucher, stok, pickup, kurir lokal, self-delivery merchant, ekspedisi, pembayaran, dan deployment migration.  
**Metode:** inspeksi source React/TypeScript, SQL migration/bootstrap, static contract tests, dan validator migration. Tidak ada replay ke database production/staging pada sesi ini.

## Kesimpulan eksekutif

Fondasi checkout saat ini sudah jauh lebih aman dibanding audit lama: frontend memakai `quote_marketplace_checkout`, submit memakai RPC authoritative dengan idempotency key, nominal utama dihitung server, flash sale dihitung server, multi-merchant diberi guard, dan delivery restriction memiliki trigger database.

Namun alur **belum dapat dinyatakan benar end-to-end** karena terdapat gap penting antara apa yang disediakan admin dan apa yang benar-benar dipakai checkout:

1. **Pengaturan `shipping_zones` di admin tidak dipakai oleh RPC checkout.** Admin dapat menyimpan zona dan tarifnya, tetapi ongkir INTERNAL memakai `base_fee + per_km_fee`, bukan zona.
2. **Admin hanya mengelola master nama ekspedisi, bukan rate card ekspedisi.** Checkout EXPEDITION mencari `marketplace_expedition_rate_cards`; tabel ini tidak memiliki menu CRUD admin dan migration sengaja tidak melakukan seed tarif. Akibatnya ekspedisi akan gagal untuk tujuan yang belum memiliki rate card.
3. **Validasi form ongkir admin menerima nilai tidak valid** seperti negatif, `min_fee > max_fee`, atau angka yang tidak konsisten. RPC memiliki fallback/penjepit nilai, tetapi tidak mengembalikan error konfigurasi yang jelas.
4. **Validator bootstrap gagal** karena marker bundle non-repeatable hilang. Ini berisiko deployment tidak konsisten walaupun source migration terbaru sudah ada.
5. **Dua sumber kontrak shipping masih berlapis:** `quote_marketplace_checkout` dan wrapper create menghitung kontrak baru, tetapi tetap mendelegasikan pembuatan order ke fungsi legacy lalu melakukan patch order. Ini bekerja sebagai hardening transisional, tetapi masih perlu uji staging untuk memastikan trigger reservation/payment/discount tidak menimbulkan mismatch.

## Matriks temuan

| ID | Prioritas | Area | Temuan | Dampak |
|---|---:|---|---|---|
| CO-01 | **P1** | Admin → checkout | `shipping_zones` dapat diatur admin, tetapi tidak pernah dibaca oleh `marketplace_shipping_contract_quote`; ongkir INTERNAL hanya memakai `shipping_base_fee`. | Admin melihat konfigurasi zona yang tampak aktif, tetapi perubahan zona tidak berdampak pada ongkir pelanggan. Tarif yang dibayar bisa berbeda dari ekspektasi bisnis. |
| CO-02 | **P1** | Ekspedisi | Checkout membaca `marketplace_expedition_rate_cards`, tetapi tidak ada halaman admin CRUD untuk tabel tersebut. Halaman `/admin/expeditions` hanya mengelola `expedition_providers`. | Provider bisa aktif namun checkout ekspedisi gagal dengan “Tarif ekspedisi untuk tujuan ini belum tersedia”. Tidak ada jalur operasional untuk mengisi tarif dari UI. |
| CO-03 | **P1** | Admin validation | `ShippingFeeForm` memakai `parseInt(...) || 0` tanpa validasi non-negatif, relasi min/max, atau batas kewajaran. `ShippingZonesForm` juga menerima jarak/tarif 0, zona tidak urut, dan nama kosong. | Admin dapat menyimpan konfigurasi tidak valid. Hasil runtime dapat menjadi gratis, terpotong oleh server, atau tidak sesuai konfigurasi yang disetujui. |
| CO-04 | **P1** | Deployment | `python3 scripts/validate-bootstrap-bundles.py` gagal: marker hilang untuk bundle 47, 50, 51, 52, 71, dan 111. | Bundle dapat dianggap tidak tervalidasi atau migration tertentu tidak terlacak oleh pipeline. Checkout/ongkir bisa berbeda antara source, bootstrap, dan database target. |
| CO-05 | **P1** | Kontrak checkout | Wrapper create baru memanggil `create_marketplace_checkout_legacy`, kemudian melakukan update ongkir/total/metadata pada order. Quote dan create tidak merupakan satu fungsi kalkulasi/order transaction tunggal. | Risiko mismatch antara nilai yang dihitung legacy dan patch baru, terutama COD fee, voucher, flash sale, reservation, multi-order, serta trigger payment. Wajib diuji concurrency di staging. |
| CO-06 | **P1** | Pilihan ekspedisi | UI tidak mengirim `expedition_rate_card_id`; server selalu memilih rate terbaik/default berdasarkan kota. Ini sah bila bisnis memang otomatis memilih, tetapi UI tidak menampilkan provider/service yang dipilih sebelum submit. | Pembeli dapat melihat “Tarif server” tanpa mengetahui provider/service final. Pemilihan admin/provider tidak transparan. |
| CO-07 | **P2** | Cart identity | `selectedItemIds` dan selection menggunakan `product.id`, sedangkan cart dapat memiliki beberapa line produk yang sama dengan kombinasi topping berbeda. | Seleksi, hapus, dan checkout dapat memperlakukan beberapa line sebagai satu item; perlu regression test khusus duplicate product + topping. |
| CO-08 | **P2** | Harga UI | Cart menyimpan snapshot product di localStorage dan menampilkan harga lokal; quote server sudah authoritative, tetapi summary tetap menampilkan harga cart sebelum quote. | UI dapat menampilkan rincian item yang berbeda dari subtotal server saat harga/flash sale berubah. Total utama memang server, tetapi rincian perlu diberi indikator refresh. |
| CO-09 | **P2** | Guest checkout | Guest diarahkan ke RPC anon dan transfer-only secara UI; wrapper guest memakai fungsi legacy unpriced lalu patch order. | Kontrak guest perlu uji staging terpisah untuk token, idempotency, rate, proof upload, dan reservation expiry. |

## Alur aktual yang ditemukan

### 1. Cart

- Item disimpan di `localStorage` melalui `CartContext`.
- Quantity sudah dibatasi maksimum 1000 dan disesuaikan dengan stok lokal.
- Cart melakukan refresh stok dan harga produk di `CartPage`, tetapi tidak memperbarui seluruh snapshot harga/name/merchant pada item.
- Checkout menggunakan item terpilih dan menormalisasi base product + topping ke `{ product_id, quantity }`.
- Cart multi-merchant ditolak di UI checkout.

**Kontrol yang baik:** quantity negatif/pecahan sudah ditangani di client dan `normalize_marketplace_checkout_items` menolak quantity invalid di server.

### 2. Quote checkout

Frontend memanggil:

```text
quote_marketplace_checkout(p_items, p_delivery, p_delivery_type, p_voucher_id)
```

Server:

- mengambil harga product dari database;
- mengambil flash sale aktif;
- memastikan satu merchant;
- memvalidasi voucher akun, periode, merchant, minimum order, usage, dan limit;
- menghitung jarak garis lurus dari koordinat merchant tersimpan ke koordinat tujuan;
- menghitung kontrak `PICKUP`, `INTERNAL`, atau `EXPEDITION`;
- mengembalikan subtotal, ongkir, diskon, total, distance, dan shipping contract.

**Catatan:** jarak yang ditampilkan frontend berasal dari layanan rute/Google/fallback, sedangkan nominal server memakai jarak haversine. Ini sudah benar untuk mencegah manipulasi nominal, tetapi selisih visual antara jarak rute dan jarak tarif harus dijelaskan ke pengguna.

### 3. Submit checkout login

Frontend memanggil:

```text
create_marketplace_checkout(
  p_items,
  p_delivery,
  p_delivery_type,
  p_payment_method,
  p_voucher_id,
  p_checkout_key
)
```

Server memakai advisory lock + tabel idempotency, lalu mendelegasikan pembuatan order ke fungsi legacy dan melakukan snapshot shipping contract serta update total/order metadata.

- ONLINE membuat invoice Xendit setelah order tersimpan.
- TRANSFER diarahkan ke halaman payment proof.
- Retry menggunakan checkout key yang sama.
- Cart dibersihkan setelah order sukses; saat invoice gagal order tetap tersedia untuk recovery.

### 4. Submit guest checkout

Guest menggunakan session key/token dan hanya transfer melalui UI. RPC anon membuat order dengan guest token, lalu wrapper melakukan snapshot shipping contract dan menyimpan hasil tanpa token mentah.

**Status verifikasi:** belum diuji terhadap database aktif pada sesi ini.

## Audit konfigurasi ongkir admin

### `shipping_base_fee`

Admin menyimpan:

```json
{
  "base_fee": 5000,
  "per_km_fee": 2000,
  "min_fee": 5000,
  "max_fee": 50000,
  "free_shipping_min_order": 100000
}
```

RPC INTERNAL menggunakan tepat field-field ini. Jadi bagian ini **terhubung**, tetapi perlu validasi input admin.

### `shipping_zones`

Admin menyimpan contoh:

```json
{
  "zones": [
    { "name": "Dalam Desa", "max_distance_km": 5, "fee": 5000 },
    { "name": "Antar Desa", "max_distance_km": 15, "fee": 10000 },
    { "name": "Luar Kecamatan", "max_distance_km": 30, "fee": 20000 }
  ]
}
```

Tidak ditemukan pemakaian `shipping_zones` di RPC checkout ataupun frontend checkout selain halaman admin. Ini adalah gap konfigurasi paling jelas.

### `expedition_providers`

`/admin/expeditions` mengelola:

- nama provider;
- logo;
- website tracking;
- status aktif;
- urutan tampil.

Data ini dipakai oleh rate quote untuk snapshot provider, logo, dan tracking URL. Namun provider saja **belum cukup** untuk menghitung tarif.

### `marketplace_expedition_rate_cards`

RPC membutuhkan rate card berisi provider, service code/name, tujuan kota, base fee, per-kg fee, min/max, free shipping threshold, ETA, priority, default, dan active.

Migration membuat tabel dan policy admin, tetapi tidak ditemukan UI admin untuk mengisi/mengubahnya. Akibatnya, kontrak ekspedisi hanya siap secara schema, belum siap secara operasional.

## Audit delivery restriction

Frontend membatasi kurir lokal jika:

- jarak > 10 km;
- kabupaten/kota berbeda;
- kecamatan berbeda.

Database juga memiliki trigger `validate_delivery_method_restriction` yang memeriksa `buyer_distance_km`, city, dan district ketika `delivery_type = INTERNAL`. Ini adalah kontrol penting dan sudah benar secara konsep.

**Catatan:** source trigger berada pada bootstrap historis; pastikan migration tersebut benar-benar sudah diterapkan pada database target dan tidak tertimpa oleh schema lama.

## Audit pembayaran dan stok

Kontrol yang ditemukan:

- checkout satu merchant untuk transfer/online;
- provider online dicek melalui konfigurasi/payment readiness;
- reservation stok menggunakan RPC;
- idempotency key mencegah order ganda pada retry;
- pembayaran setelah reservation expired memiliki guard di migration hardening;
- bukti transfer memakai RPC scoped buyer/guest.

Yang masih wajib diuji pada staging:

1. dua request paralel dengan checkout key berbeda untuk stok terakhir;
2. voucher request paralel sampai usage limit;
3. harga berubah antara quote dan submit;
4. flash sale habis antara quote dan submit;
5. reservation rollback jika legacy checkout gagal di tengah;
6. payment PAID tepat saat reservation expired;
7. guest retry dengan token/key yang sama;
8. kombinasi topping yang memakai product stok sama.

## Bukti pemeriksaan teknis

### File/komponen utama

- `src/pages/CheckoutPage.tsx`
- `src/pages/CartPage.tsx`
- `src/contexts/CartContext.tsx`
- `src/pages/admin/AdminSettingsPage.tsx`
- `src/pages/admin/AdminExpeditionProvidersPage.tsx`
- `supabase/migrations/20261013052500_marketplace_checkout_shipping_quote.sql`
- `supabase/migrations/20261013054500_checkout_p1_item_normalization_shipping_contracts.sql`
- `supabase/bootstrap/106_20261013050000_self_delivery_admin_fee.sql`
- `supabase/bootstrap/04_20260909190000_to_20260911072000.sql`

### Validasi yang dijalankan

- `bash scripts/validate-migrations.sh`: **lulus**, dengan warning duplicate timestamp `11`.
- `python3 scripts/validate-bootstrap-bundles.py`: **gagal** karena marker non-repeatable hilang untuk bundle 47, 50, 51, 52, 71, dan 111.
- Test Vitest tidak dapat dijalankan karena `node_modules` belum tersedia pada checkout repository ini (`pnpm exec vitest`: command not found).

## Rekomendasi prioritas

### P0 sebelum production checkout

1. Pastikan migration 107/108 dan seluruh migration dependency benar-benar diterapkan ke staging/production.
2. Perbaiki validator/bootstrap marker yang gagal, lalu regenerate manifest/bundle.
3. Jalankan test database aktif untuk checkout authoritative, voucher race, reservation, payment expiry, dan guest checkout.
4. Verifikasi signature RPC aktif di database target dan reload schema cache PostgREST.

### P1

1. Pilih satu sumber aturan ongkir INTERNAL:
   - jika model zona, ubah RPC agar memakai `shipping_zones`; atau
   - jika model formula jarak, hapus/nonaktifkan UI `shipping_zones` agar admin tidak disesatkan.
2. Buat halaman admin **Rate Card Ekspedisi** atau sediakan migration/seed resmi untuk rate card yang disetujui bisnis.
3. Tambahkan validasi admin: semua fee >= 0, `min_fee <= max_fee`, `base_fee` berada dalam rentang, jarak zona > 0 dan urut naik, nama zona tidak kosong, dan tidak ada overlap.
4. Satukan perhitungan quote dan create ke satu fungsi domain authoritative atau tambahkan assertion bahwa hasil final create harus sama dengan quote yang dikirim/ditampilkan.
5. Tampilkan provider, service, berat, ETA, dan nominal ekspedisi yang dipilih sebelum submit.
6. Tambahkan observability untuk menyimpan/menampilkan `shipping_pricing_contract` pada detail order dan laporan admin.

### P2

1. Ubah identity cart dari hanya `product.id` menjadi line key `product + toppings`.
2. Setelah quote server tersedia, tampilkan subtotal per item dari data authoritative atau beri label bahwa harga dapat berubah saat submit.
3. Tambahkan test kontrak untuk perubahan setting admin dan seluruh delivery type.

## Verdict

**Checkout marketplace sudah memiliki fondasi authoritative yang baik, tetapi integrasi admin → ongkir belum lengkap dan deployment validator sedang gagal.**

Status rekomendasi: **NO-GO untuk menyatakan alur checkout + ongkir selesai production** sampai CO-01, CO-02, CO-04, dan pengujian staging pada CO-05 ditutup.
