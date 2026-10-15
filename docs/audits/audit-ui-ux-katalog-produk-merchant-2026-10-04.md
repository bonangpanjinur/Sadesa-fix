# Audit UI/UX Manajemen Produk / Katalog Merchant

**Tanggal audit:** 4 Oktober 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Cakupan:** halaman katalog, alur tambah/edit produk, pencarian dan filter, tabel/kartu mobile, stok, gambar, varian, promo, status POS, empty state, dan skalabilitas data.

## Ringkasan eksekutif

Halaman Katalog Produk sudah memiliki fitur inti yang cukup lengkap:

- daftar produk desktop dan kartu mobile;
- pencarian nama produk;
- filter kategori;
- tambah/edit produk melalui schema validation;
- upload gambar utama;
- status aktif/nonaktif;
- status promo;
- penanda stok rendah/habis;
- penanda produk tertaut POS;
- halaman gambar dan varian;
- dukungan subkategori dan category contract.

Tantangan utama bukan kelengkapan fitur, melainkan **alur kerja yang terpecah, kontrol katalog yang kurang cepat untuk operasional harian, serta query yang belum siap untuk katalog besar**.

## Temuan prioritas

### P0 — Katalog belum berorientasi tindakan harian

Header saat ini hanya menampilkan jumlah produk dan tombol `Tambah Produk`. Merchant belum langsung mendapatkan ringkasan seperti:

- produk aktif;
- produk nonaktif;
- stok habis;
- stok menipis;
- produk promo.

**Dampak:** merchant harus menggunakan filter atau memindai daftar untuk mengetahui kondisi katalog.

**Rekomendasi:** tambahkan summary strip ringkas di atas tabel:

```text
Semua 42 | Aktif 36 | Stok habis 3 | Stok menipis 5 | Promo 8
```

Setiap angka dapat diklik untuk mengaktifkan filter terkait.

### P0 — Query mengambil seluruh produk tanpa pagination

`MerchantProductsPage` memuat semua produk merchant dengan `.order('created_at')` tanpa limit/pagination. Setelah itu, produk POS juga dicari menggunakan daftar seluruh product ID.

**Dampak:** waktu buka dan ukuran payload akan meningkat ketika katalog merchant membesar; pencarian/filter menjadi client-side dan hanya bekerja pada data yang sudah diambil.

**Rekomendasi:**

- gunakan pagination atau infinite loading;
- gunakan search server-side dengan `ilike` atau RPC yang aman;
- gunakan count server-side untuk summary strip;
- pertimbangkan query status POS yang tidak membentuk `in(...)` terlalu panjang;
- tampilkan `Menampilkan 1–25 dari X produk`.

### P1 — Edit produk terpecah antara modal dan halaman detail

Dari katalog, `Edit` membuka modal yang berisi informasi dasar dan varian jika produk sudah ada. Aksi `Gambar & Varian` membuka halaman detail yang hanya memiliki tab Gambar dan Varian. Di repository juga terdapat `MerchantProductDetailEditor` dengan form detail lebih lengkap, tetapi tidak terhubung sebagai route aktif.

**Dampak:** merchant tidak memiliki satu tempat yang jelas untuk mengelola seluruh lifecycle produk. Fitur promo, ambang stok, gambar, topping, dan varian tersebar.

**Rekomendasi:** pilih satu pola utama:

- **Pola halaman detail penuh:** katalog → `/merchant/products/:id` → tab Info, Gambar, Varian, Topping, Stok; atau
- **Pola modal cepat + halaman lanjutan:** modal hanya untuk nama/harga/status, halaman detail untuk seluruh konfigurasi.

Rekomendasi utama: gunakan halaman detail penuh untuk edit, dan pertahankan modal hanya untuk `Tambah Produk` cepat.

### P1 — Aksi produk utama tersembunyi di menu tiga titik desktop

Desktop hanya menampilkan tombol overflow. Aksi yang sering dilakukan seperti Edit, Gambar & Varian, dan Nonaktifkan memerlukan satu klik tambahan.

**Rekomendasi:** tampilkan maksimal dua CTA langsung:

- `Edit`
- `Gambar & Varian`

Aksi sekunder tetap di overflow:

- Aktifkan/nonaktifkan;
- Hapus;
- Duplikasi produk;
- Lihat katalog publik.

### P1 — Mobile sudah memakai kartu, tetapi aksi operasional belum lengkap

Kartu mobile sudah baik dalam menampilkan gambar, nama, harga, status, stok, promo, dan jumlah terjual. Namun kartu hanya menampilkan `Edit` dan `Gambar & Varian`; merchant tidak dapat mengaktifkan/nonaktifkan produk atau menghapus produk tanpa masuk ke desktop-style action flow.

**Rekomendasi:** tambahkan overflow icon yang jelas pada pojok kartu, atau gunakan bottom sheet aksi:

```text
Edit informasi
Kelola gambar & varian
Aktifkan / Nonaktifkan
Duplikasi
Hapus
```

### P1 — Status stok menggunakan threshold hard-coded di katalog

Katalog menghitung stok rendah dengan `item.stock <= 5`, sementara halaman stok menggunakan `low_stock_threshold` atau `min_stock_alert`. Ini dapat membuat label di katalog berbeda dengan halaman Stok.

**Dampak:** merchant bisa melihat produk sebagai “aman” di satu halaman tetapi “menipis” di halaman lain.

**Rekomendasi:** ambil threshold dari sumber yang sama dan gunakan helper bersama:

- `Habis` jika stok = 0;
- `Kritis` jika stok di bawah threshold;
- `Menipis` jika stok sama dengan atau mendekati threshold;
- `Aman` jika di atas threshold.

### P1 — Form tambah produk belum memandu informasi yang paling berdampak

Form sudah memiliki validasi nama, kategori, harga, stok, dan deskripsi. Namun pada form tambah produk:

- ambang stok belum tersedia;
- diskon/promo hanya berupa switch `Sedang Promo`, tanpa detail diskon dan masa berlaku;
- varian baru muncul saat edit;
- belum ada preview ringkas produk sebelum disimpan;
- belum ada indikator kelengkapan listing.

**Rekomendasi:** jadikan form bertahap:

1. **Wajib:** gambar, nama, kategori, harga, stok.
2. **Tingkatkan penjualan:** deskripsi, varian, topping.
3. **Promosi:** diskon dan masa berlaku.
4. **Operasional:** ambang stok, status aktif, keterkaitan POS.

Untuk merchant baru, tampilkan checklist `Kelengkapan produk` agar form terasa lebih mudah diselesaikan.

### P1 — Produk tertaut POS perlu status dan batasan yang lebih terlihat

Produk tertaut POS diberi badge `POS`, dan stok pada form edit dinonaktifkan. Namun pembatasan baru dipahami setelah merchant mencoba mengubah nilai atau membaca helper text.

**Rekomendasi:**

- tampilkan info banner di header: `Produk dikelola oleh POS`;
- jelaskan field yang bersumber dari POS;
- arahkan dengan CTA `Kelola di POS`;
- gunakan icon/link yang sama di tabel, kartu mobile, dan halaman detail.

### P2 — Kategori berpotensi membebani form

Form menggunakan dua select: kategori utama dan subkategori. Ini benar secara data, tetapi helper text template menampilkan informasi teknis seperti workflow dan listing fields langsung di form.

**Rekomendasi:**

- gunakan label operasional: `Jenis produk` dan `Subkategori`;
- tampilkan helper singkat setelah pilihan berubah;
- pindahkan detail template/atribut ke `Info selengkapnya` atau tooltip;
- bila kategori tidak memiliki subkategori, tampilkan state `Kategori ini tidak memiliki subkategori` tanpa membuat merchant mengira ada field yang gagal dimuat.

### P2 — Statistik views/order_count belum cukup kontekstual

Tabel menampilkan views dan order count tanpa periode. Angka historis bisa disalahartikan sebagai performa bulan ini atau periode aktif.

**Rekomendasi:**

- labeli sebagai `Total dilihat` dan `Total terjual`; atau
- tambahkan pilihan periode `7 hari / 30 hari / Semua waktu`;
- jadikan statistik lanjutan hanya tampil di halaman detail atau Product Analytics.

## Audit state dan aksesibilitas

### Yang sudah baik

- loading state sudah ditangani melalui `DataTable`;
- mobile card memiliki `mobileCardAriaLabel`;
- tombol icon action memiliki `aria-label` dan `title`;
- input form memiliki `aria-invalid` dan `aria-describedby` untuk error;
- validasi schema mencegah harga/stok/nama tidak valid;
- produk POS mencegah perubahan data yang tidak semestinya.

### Yang perlu diperbaiki

- tambahkan empty state khusus untuk katalog kosong dengan CTA `Tambah produk pertama`;
- bedakan empty state hasil pencarian/filter dari katalog benar-benar kosong;
- beri pesan error dan retry untuk query kategori, bukan hanya daftar kosong;
- beri `aria-label` pada tombol hapus opsi varian;
- tambahkan konfirmasi non-destructive yang lebih informatif untuk penghapusan produk;
- gunakan dialog konfirmasi berbasis komponen UI agar konsisten, bukan `window.confirm`;
- gunakan sticky save bar pada halaman detail mobile agar tombol `Simpan` tidak hilang saat scroll.

## Struktur informasi yang direkomendasikan

### Header katalog

```text
Katalog Produk
Kelola produk yang tampil di marketplace dan POS

[+ Tambah produk] [Import / Export]

[Semua] [Aktif] [Stok habis] [Stok menipis] [Promo]

[Cari nama / SKU] [Kategori] [Status] [Sortir]
```

### Kolom desktop yang disarankan

| Kolom | Isi |
|---|---|
| Produk | thumbnail, nama, kategori |
| Harga | harga aktif, badge promo bila ada |
| Stok | jumlah, status stok, sumber POS bila tertaut |
| Performa | total dilihat, total terjual |
| Status | aktif/nonaktif, promo |
| Aksi | Edit, Gambar & Varian, overflow |

### Kartu mobile yang disarankan

```text
[foto] Nama produk                  [•••]
       Kategori
       Rp harga

Stok 12 • Aman       Aktif
Total terjual 24

[Edit] [Gambar & Varian]
```

## Backlog implementasi berdasarkan dampak

| Prioritas | Perubahan | Dampak |
|---|---|---|
| P0 | Pagination/server-side search dan count | Katalog siap tumbuh |
| P0 | Summary strip status produk | Merchant memahami kondisi katalog dalam 3 detik |
| P1 | Satukan pola edit modal/detail | Mengurangi kebingungan alur |
| P1 | Tampilkan CTA edit langsung di desktop | Mempercepat pekerjaan berulang |
| P1 | Samakan threshold stok dengan halaman Stok | Meningkatkan kepercayaan status |
| P1 | Aksi lengkap pada kartu mobile | Operasional satu tangan |
| P1 | Banner dan CTA khusus produk POS | Mengurangi kesalahan edit stok |
| P2 | Checklist kelengkapan produk | Meningkatkan kualitas listing |
| P2 | Empty state dan error state yang spesifik | Mengurangi dead-end |
| P2 | Statistik dengan konteks periode | Mencegah salah interpretasi |

## Definition of Done

- Merchant dapat mengetahui jumlah aktif, habis, menipis, dan promo tanpa membuka filter.
- Katalog tetap responsif saat produk mencapai ratusan atau ribuan item.
- Edit informasi dasar, gambar, varian, topping, stok, dan promo memiliki alur yang jelas.
- Aksi paling sering dapat dilakukan dalam satu klik dari desktop dan maksimal dua tap dari mobile.
- Threshold stok konsisten antara Katalog, Beranda, dan halaman Stok.
- Empty, loading, error, dan filtered-empty state memiliki copy dan CTA berbeda.
- Produk tertaut POS menjelaskan sumber data dan lokasi pengelolaannya secara eksplisit.
