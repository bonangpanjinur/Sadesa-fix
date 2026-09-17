# Audit Buyer: Klasifikasi Pesanan Produk vs Ojek & Kurir

**Tanggal:** 17 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Commit yang diaudit:** `e8a6b59` (`fix: unify courier dashboard shell`)  
**Ruang lingkup:** alur buyer untuk marketplace, ojek penumpang, dan antar barang; query riwayat; kartu order; detail; tracking; aksi lanjutan; serta RPC pembuatan order kurir.

## Ringkasan eksekutif

Observasi pengguna **terbukti**. Pesanan layanan antar barang secara teknis dibuat melalui RPC `create_courier_order`, tetapi disimpan di tabel `orders` yang sama dengan order produk. Hal ini sendiri tidak salah apabila `orders` diperlakukan sebagai tabel transaksi lintas layanan. Masalah kritisnya adalah tidak adanya discriminator transaksi yang eksplisit dan halaman buyer mengklasifikasikan seluruh baris `orders` sebagai order marketplace.

Akibatnya, order kurir yang secara karakteristik tidak mempunyai `merchant_id` dan tidak mempunyai `order_items` dapat tampil sebagai **Toko / Produk / 1 barang / Total Belanja**, memakai ikon toko/produk, dan menerima aksi yang hanya relevan untuk produk. Sementara itu, ride penumpang sudah dipisahkan melalui tabel `ride_requests` dan sudah dirender dengan label **Ojek & Kurir**. Dengan demikian, kategori transportasi saat ini konsisten untuk ride, tetapi belum konsisten untuk antar barang.

**Kesimpulan:** booking dan dispatch kurir memiliki fondasi backend yang cukup baik; cacat utama berada pada **model klasifikasi transaksi dan layer presentasi buyer**, terutama `OrdersPage` dan `OrderDetailSheet`.

## Temuan berbasis bukti

| ID | Tingkat | Temuan | Bukti kode | Dampak |
|---|---|---|---|---|
| B-01 | **P0** | Semua transaksi di `orders` diperlakukan sebagai marketplace pada riwayat buyer | `src/pages/OrdersPage.tsx:70-72, 163-175, 380-383` membentuk `HistoryItem` `marketplace` dari seluruh hasil query `orders` | Order kurir masuk jalur UI produk dan kategori/filter menjadi salah |
| B-02 | **P0** | Query riwayat buyer tidak mengambil field yang diperlukan untuk mengenali order kurir | `src/pages/OrdersPage.tsx:170-175` hanya memilih id, status, total, merchant, payment, dan item; tidak mengambil `pickup_address`, koordinat, `package_type`, `package_weight_kg`, `courier_notes`, `delivery_type`, `courier_id` | Renderer tidak punya data untuk membuat kartu kurir yang benar; fallback menjadi tidak terhindarkan |
| B-03 | **P0** | Renderer kartu order selalu menganggap record memiliki produk dan toko | `src/pages/OrdersPage.tsx:627-700`: `productName` fallback ke `Produk`, `itemCount` dari `order_items`, merchant fallback ke `Toko`, ikon `Store`/`ShoppingBag`, label `Total Belanja` | Screenshot dan gejala pengguna terjelaskan langsung: antar barang terlihat seperti belanja produk |
| B-04 | **P0** | Detail order juga selalu berorientasi produk | `src/components/order/OrderDetailSheet.tsx:82-104` tidak mengambil field pickup/package; baris 152-199 selalu menampilkan merchant, `Item Pesanan`, `Subtotal`, dan `Ongkir`; baris 155 memakai fallback `Toko` | Detail dari notifikasi/deep link tetap salah atau kosong untuk order kurir |
| B-05 | **P1** | Tidak ada discriminator eksplisit untuk membedakan produk, antar barang, dan layanan lain | Pencarian repository tidak menemukan `service_type`, `order_type`, atau `transaction_type` yang relevan pada schema/frontend | Query, laporan, notifikasi, invoice, dan UI harus menebak dari kombinasi nullable fields; mudah tidak konsisten |
| B-06 | **P1** | Aksi produk dapat muncul pada order kurir | `src/pages/OrdersPage.tsx:779-844` menampilkan `Pesan Lagi`, invoice, komplain, dan rating berbasis kondisi umum status; `handleReorder` dipanggil dengan `order_items` kosong | UX membingungkan; tombol reorder akhirnya hanya memunculkan “Tidak ada produk”, sedangkan invoice/review berpotensi memakai asumsi produk |
| B-07 | **P1** | Aksi kontak penjual sudah guarded, tetapi tidak ada aksi kontak/tracking khusus kurir pada kartu | `src/pages/OrdersPage.tsx:709-719` hanya menyediakan `Hubungi Penjual` bila merchant ada; order kurir tidak punya merchant | Order kurir kehilangan affordance yang tepat di riwayat, meskipun tracking dapat dibuka dari kartu umum |
| B-08 | **P1** | Status kurir dipetakan ke konfigurasi order marketplace | `src/pages/OrdersPage.tsx:75-100, 122-129` memakai status order bersama; `ASSIGNED`/`PICKED_UP`/`DELIVERING` diberi label generik marketplace | Status masih bisa terbaca, tetapi copy dan progress tidak membedakan “kurir mengambil barang” dari “toko mengirim produk” |
| B-09 | **P1** | Detail ETA menghitung dari merchant bila tidak ada courier | `src/components/order/OrderDetailSheet.tsx:115-137` menggunakan lokasi merchant fallback; order kurir tidak memiliki merchant | ETA/detail dapat kosong atau salah untuk booking antar barang |
| B-10 | **P2** | Riwayat gabungan hanya punya tab status, bukan kategori layanan | `src/pages/OrdersPage.tsx:113-120, 385-393` hanya menyediakan Semua/Belum Bayar/Diproses/Dikirim/Selesai/Dibatalkan | Buyer tidak dapat memfilter Produk vs Ojek & Kurir secara eksplisit; jumlah tab ikut bercampur |

## Hal yang sudah benar

Implementasi backend booking kurir tidak perlu dianggap sebagai kegagalan desain secara otomatis. Pada `supabase/bootstrap/53_20260911120000_courier_booking_dispatch.sql`:

1. RPC `create_courier_order(jsonb)` mengharuskan autentikasi dan memvalidasi koordinat, berat, alamat, penerima, serta jenis barang (`:12-49`).
2. Order dibuat dengan `merchant_id = NULL`, `subtotal = 0`, `delivery_type = 'INTERNAL'`, biaya pada `shipping_cost/total`, dan detail pickup/package (`:63-80`).
3. Riwayat status `ASSIGNED` dicatat dan assignment kurir ditawarkan ke kurir terdekat yang memenuhi syarat (`:82-114`).
4. Buyer diarahkan ke `/orders/{id}/tracking` setelah booking (`src/pages/transport/CourierBookingPage.tsx:351-387`).
5. `ride_requests` sudah dipisahkan dari `orders` dan diambil terpisah oleh `OrdersPage` (`:308-327`); kartunya telah memakai label **Ojek & Kurir**, ikon `Bike`, pickup, tujuan, jarak, dan tarif (`:543-624`).
6. `OrderTrackingPage` mengambil order berdasarkan `buyer_id`, mengambil `orders` dengan `select('*')`, dan sudah memiliki dukungan courier tracking (`src/pages/OrderTrackingPage.tsx:112-218`). Ini berarti masalah utama bukan hilangnya seluruh kemampuan tracking, melainkan representasi riwayat/detail yang tidak seragam.

## Diagnosis arsitektur

Saat ini terdapat tiga bentuk transaksi dari perspektif buyer:

```text
Produk toko       -> orders + order_items + merchant_id
Antar barang      -> orders + delivery fields + delivery_assignments, tanpa merchant_id/order_items
Ojek penumpang    -> ride_requests
```

Menyimpan produk dan antar barang pada tabel `orders` dapat dipertahankan untuk kompatibilitas fulfillment, pembayaran, dan tracking. Namun kontrak data buyer harus membuat jenis transaksi eksplisit. Menggunakan `merchant_id IS NULL`, `order_items` kosong, atau `pickup_address IS NOT NULL` sebagai satu-satunya klasifikasi adalah solusi sementara dan rapuh.

Klasifikasi yang disarankan:

```text
service_type = MARKETPLACE | COURIER_DELIVERY
history_kind = product | courier_delivery | ride
category = Marketplace | Ojek & Kurir
```

`ride_requests` dapat tetap menjadi tabel tersendiri; pengelompokan **Ojek & Kurir** dilakukan pada view-model/UI, bukan dengan memaksa ride masuk ke `orders`.

## Rekomendasi perbaikan

### P0 — hotfix buyer tanpa menunggu migrasi schema

Buat helper terpusat, bukan kondisi ad hoc di JSX:

```ts
type BuyerTransactionKind = 'product' | 'courier_delivery';

function getBuyerTransactionKind(order: BuyerOrder): BuyerTransactionKind {
  if (
    !order.merchant_id &&
    !order.order_items?.length &&
    Boolean(order.pickup_address) &&
    Boolean(order.package_type)
  ) return 'courier_delivery';
  return 'product';
}
```

Untuk hotfix ini, query `loadBuyerOrders` wajib mengambil minimal:

```text
pickup_address, pickup_lat, pickup_lng,
delivery_address, delivery_lat, delivery_lng,
delivery_name, delivery_phone,
package_type, package_weight_kg, courier_notes,
delivery_type, courier_id
```

Kemudian lakukan hal berikut:

- Render kartu kurir dengan ikon `Bike`/`Truck`/`Package`, judul **Ojek & Kurir**, subjudul **Antar barang**, pickup dan tujuan.
- Ganti `Total Belanja` menjadi **Biaya Layanan**.
- Tampilkan berat dan jenis barang bila tersedia.
- Hilangkan `Hubungi Penjual`, `Pesan Lagi`, dan aksi review produk untuk `courier_delivery`.
- Arahkan klik dan tombol utama ke tracking kurir.
- Pisahkan label/status kurir dari copy marketplace.
- Pertahankan fallback lama hanya untuk data legacy yang benar-benar tidak memenuhi ciri courier.

### P1 — kontrak data eksplisit

Tambahkan kolom `service_type` pada `orders`, idealnya dengan constraint/enum yang jelas:

```sql
service_type text NOT NULL DEFAULT 'MARKETPLACE'
  CHECK (service_type IN ('MARKETPLACE', 'COURIER_DELIVERY'))
```

Migration harus mengisi data lama dengan aturan konservatif, memverifikasi jumlah kandidat courier, lalu mengubah RPC agar selalu menulis `COURIER_DELIVERY`. Untuk order marketplace lama, default `MARKETPLACE` dapat dipakai setelah audit data. Jangan hanya mengandalkan default jika ada writer lain yang memasukkan order.

### P1 — view-model terpadu

Buat mapper/domain contract yang dipakai oleh riwayat, detail, invoice, notifikasi, pencarian, dan filter:

```ts
type BuyerHistoryItem =
  | { kind: 'product'; id: string; merchantName: string; itemCount: number; total: number }
  | { kind: 'courier_delivery'; id: string; pickupAddress: string; destinationAddress: string; packageType: string; weightKg: number | null; total: number }
  | { kind: 'ride'; id: string; pickupAddress: string; destinationAddress: string; total: number };
```

Dengan satu mapper, klasifikasi tidak berbeda antara card, detail sheet, invoice, notifikasi, dan jumlah tab.

### P1 — dua mode detail

`OrderDetailSheet` harus memiliki mode produk dan mode antar barang. Mode antar barang minimal memuat:

```text
Ojek & Kurir
Detail Pengiriman
Pickup
Tujuan
Penerima dan telepon
Jenis barang
Berat
Biaya layanan
Metode/status pembayaran
Status kurir
```

Tambahkan query field pickup/package/courier serta guard akses buyer. Jangan menampilkan `Toko`, `Item Pesanan`, atau `Subtotal` sebagai label utama bila `service_type = COURIER_DELIVERY`.

### P2 — audit lintas modul

Setelah hotfix, lakukan pencarian dan uji terhadap:

- invoice buyer dan merchant;
- notifikasi dan deep link;
- pencarian/filter order;
- laporan omzet/penjualan dan export;
- dispute/refund;
- chat merchant vs chat kurir;
- rating merchant vs rating kurir;
- dashboard admin/desa;
- realtime payload dan cache React Query.

Khusus laporan merchant, filter `merchant_id` yang sudah ada cenderung mengurangi risiko order kurir ikut dihitung sebagai penjualan. Namun hal itu tetap perlu regression test karena tidak menggantikan discriminator eksplisit.

## Acceptance criteria

1. Booking antar barang baru muncul di riwayat sebagai **Ojek & Kurir → Antar barang**, bukan Toko/Produk.
2. Kartu menampilkan pickup, tujuan, jenis barang, berat, dan **Biaya Layanan**.
3. Detail order tidak menampilkan daftar item produk kosong, merchant fallback `Toko`, atau subtotal produk.
4. Ride penumpang tetap muncul dalam kategori **Ojek & Kurir** dengan subtype **Ojek penumpang**.
5. Order produk tetap mempertahankan merchant, item, subtotal, ongkir, reorder, invoice, dan chat merchant.
6. Tombol `Pesan Lagi` tidak muncul untuk order courier/ride.
7. Filter kategori dan jumlah transaksi konsisten antara produk dan ojek/kurir.
8. Data legacy tanpa `service_type` memiliki klasifikasi deterministik dan dicatat untuk migrasi.
9. RLS/ownership buyer tetap diuji untuk riwayat, detail, dan tracking.
10. Build TypeScript dan test unit/integrasi lulus setelah dependency di-install.

## Quality gate audit

- **Static code review:** selesai; temuan inti terkonfirmasi pada file dan baris yang disebutkan.
- **Git status:** bersih; audit dilakukan tanpa mengubah source code.
- **Automated test:** belum dapat dijalankan pada clone shallow ini karena executable `vitest` tidak tersedia (`vitest: not found`), sehingga dependency install/build perlu dilakukan pada pipeline atau environment proyek.
- **Database runtime/RLS staging:** belum dieksekusi; validasi ini diperlukan sebelum migration `service_type` diterapkan.

## Prioritas implementasi

| Prioritas | Pekerjaan | Risiko bila ditunda |
|---|---|---|
| P0 | Klasifikasi dan renderer kartu buyer | Salah persepsi transaksi, UX rusak, tindakan produk muncul pada layanan |
| P0 | Mode detail courier | Detail kosong/salah dan biaya layanan tidak jelas |
| P1 | `service_type` eksplisit dan backfill | Ketidakkonsistenan lintas query, laporan, invoice, dan notifikasi |
| P1 | Mapper `product/courier/ride` terpusat | Perbaikan parsial berulang dan regresi antar halaman |
| P2 | Audit invoice, notifikasi, laporan, chat, rating, filter | Risiko residual pada modul di luar riwayat utama |

**Putusan audit:** **belum layak sign-off UX buyer** untuk kategori antar barang sampai P0 diperbaiki. Alur booking/dispatch backend dapat dilanjutkan ke verifikasi staging terkontrol, tetapi jangan menganggap keberhasilan RPC sebagai bukti bahwa pengalaman buyer sudah benar.
