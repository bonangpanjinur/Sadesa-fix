# Rekomendasi Perbaikan: POS sebagai Modul Opsional Merchant

## Keputusan Produk

POS sebaiknya menjadi **fitur opsional yang diaktifkan per merchant**, bukan sistem wajib untuk semua merchant dan bukan aplikasi kedua yang memiliki dashboard sendiri.

Prinsip utamanya:

> **Merchant adalah workspace utama. POS adalah modul operasional toko yang dapat diaktifkan sesuai kebutuhan bisnis.**

Dengan pendekatan ini:

- Pedagang online atau pedagang biasa tidak dibebani menu POS.
- Kafe dan restoran dapat mengaktifkan kasir, meja, dapur, QR menu, serta bahan baku.
- Toko retail seperti pakaian, sembako, atau kerajinan dapat mengaktifkan kasir, barcode, varian, dan stok.
- Semua produk, pelanggan, stok, promo, serta laporan tetap berada dalam satu konteks merchant.

## Hubungan Wajib antara Merchant dan POS

POS harus menjadi **modul milik merchant yang sama**, bukan workspace, akun, atau bisnis baru yang berdiri sendiri.

Relasi yang benar:

```text
Merchant
├── Profil toko marketplace
├── Katalog produk bersama
├── Pelanggan bersama
├── Stok bersama
├── Pesanan online
└── Modul POS opsional
    ├── Outlet
    ├── Kasir
    ├── Transaksi offline
    ├── Shift
    └── Operasional toko
```

Aturan integrasinya:

1. Setiap konfigurasi POS wajib memiliki `merchant_id` yang menunjuk ke merchant pemilik.
2. Outlet POS adalah anak dari merchant, bukan merchant baru.
3. User merchant tetap menjadi pemilik utama POS.
4. Aktivasi, paket, dan status POS dikelola dari workspace merchant.
5. Katalog produk POS menggunakan katalog merchant yang sama.
6. Stok online dan offline menggunakan sumber stok merchant yang sama.
7. Pelanggan dan promo dapat dipakai pada kanal online maupun kasir sesuai aturan modul.
8. Laporan merchant dapat menggabungkan transaksi online dan offline.
9. POS menggunakan `MerchantLayout`, `MerchantSidebar`, dan Dashboard Merchant yang sama.
10. Tidak boleh ada pendaftaran merchant kedua hanya untuk memakai POS.

Jika sistem internal memerlukan entitas `tenant` atau `pos_workspace`, entitas tersebut harus menjadi detail teknis di bawah merchant dan tetap memiliki relasi wajib ke `merchant_id`. Entitas tersebut tidak boleh terlihat sebagai identitas bisnis kedua bagi pengguna.

## Masalah yang Harus Diselesaikan

Model saat ini berisiko membuat merchant merasa memiliki dua aplikasi:

1. Dashboard Merchant untuk marketplace atau toko online.
2. Dashboard dan menu POS untuk transaksi offline.

Masalah tersebut muncul ketika POS:

- memiliki dashboard terpisah;
- memiliki kelompok menu utama sendiri;
- mengulang menu produk, stok, pelanggan, promosi, dan laporan;
- memakai istilah POS pada hampir setiap item;
- meminta semua merchant membuat outlet dan workspace kasir;
- tidak membedakan kebutuhan kafe, retail, dan pedagang online.

Target akhirnya bukan sekadar menggabungkan dua sidebar. Targetnya adalah satu hubungan bisnis:

> **Satu merchant, satu katalog, satu stok, satu laporan, dengan POS sebagai kanal penjualan tambahan.**

## Model Status POS per Merchant

Status POS harus melekat pada merchant atau tenant, bukan hanya pada user.

```text
inactive
  -> setup_required
  -> trial
  -> active
  -> suspended
  -> cancelled
```

### Arti Status

| Status | Perilaku |
| --- | --- |
| `inactive` | POS belum digunakan. Menu POS tidak ditampilkan. |
| `setup_required` | Merchant sudah memilih untuk mengaktifkan POS, tetapi setup belum selesai. |
| `trial` | POS aktif dalam masa percobaan. |
| `active` | POS aktif dan dapat digunakan sesuai paket serta role. |
| `suspended` | POS sementara tidak dapat digunakan, tetapi data tetap dipertahankan. |
| `cancelled` | Langganan berhenti. Data historis tetap read-only jika kebijakan bisnis mengizinkan. |

Status fitur harus diperiksa di server untuk setiap route dan mutation POS. Penyembunyian menu di frontend hanya lapisan UX, bukan kontrol akses utama.

## Jenis Bisnis dan Modul yang Disarankan

Saat aktivasi, merchant memilih jenis operasional. Pilihan ini menjadi dasar rekomendasi modul, bukan pembatas permanen.

### Merchant Online atau Marketplace Saja

Modul POS tidak perlu diaktifkan. Merchant cukup menggunakan:

- katalog produk;
- pesanan marketplace;
- stok;
- promo;
- pelanggan;
- analitik toko.

### Retail: Pakaian, Sembako, Kerajinan, dan Sejenisnya

Modul yang disarankan:

- Kasir;
- barcode;
- varian produk;
- stok outlet;
- pembelian dan supplier;
- retur;
- multi-outlet;
- laporan penjualan.

### Kafe atau Restoran

Modul yang disarankan:

- Kasir;
- meja dan dine-in;
- menu digital QR;
- KDS atau dapur;
- bahan baku;
- resep;
- shift kasir;
- stok outlet;
- laporan per outlet dan per kasir.

### Pedagang Sederhana

Gunakan paket ringan:

- Kasir;
- produk;
- stok sederhana;
- transaksi;
- laporan harian.

Menu lanjutan seperti KDS, resep, multi-gudang, dan payroll tidak perlu ditampilkan secara default.

## Struktur Navigasi yang Disarankan

Tidak ada blok navigasi POS terpisah. Semua item dikelompokkan berdasarkan fungsi merchant:

### Penjualan & Operasional

- Pesanan marketplace;
- fulfillment;
- refund;
- kasir;
- transaksi toko;
- retur;
- mode kiosk;
- meja;
- KDS dapur;
- kas harian.

### Katalog, Stok & Pembelian

- katalog produk;
- kategori produk;
- harga produk;
- manajemen stok;
- stok outlet;
- transfer stok;
- bahan baku;
- resep;
- supplier;
- pembelian;
- multi-gudang.

### Promosi & Pelanggan

- promo;
- voucher;
- loyalty;
- pelanggan;
- menu digital QR;
- ulasan;
- analitik pelanggan.

### Analitik, Laporan & Keuangan

- analitik toko;
- insight bisnis;
- laporan penjualan;
- laporan per kasir;
- laporan stok;
- laba rugi;
- cashflow;
- laporan outlet;
- laporan pajak;
- penarikan;
- ekspor akuntansi.

### Tim, Pengaturan & Integrasi

- pengguna dan kasir;
- manajemen akses;
- jadwal shift;
- absensi;
- penggajian;
- target omzet;
- audit trail;
- konflik offline;
- integrasi marketplace;
- pengaturan toko;
- pengaturan operasional.

Menu ditampilkan secara dinamis berdasarkan:

1. status POS merchant;
2. jenis bisnis atau modul yang aktif;
3. role pengguna;
4. outlet yang dipilih.

## Perilaku Menu Berdasarkan Status

### POS Belum Aktif

Sidebar hanya menampilkan menu merchant umum. Di Dashboard Merchant tampil satu kartu:

> **Butuh kasir untuk toko fisik?**  
> Aktifkan Kasir untuk menerima pembayaran langsung dan menyinkronkan stok dengan toko online.

CTA:

- `Aktifkan Kasir`;
- `Pelajari Fitur`.

Jangan tampilkan menu kasir, KDS, meja, laporan kasir, atau pengaturan POS pada sidebar utama.

### POS Sudah Aktif

Menu yang relevan muncul di grup merchant yang sesuai. Tidak ada:

- Dashboard POS;
- workspace POS terpisah;
- sidebar POS kedua;
- label `POS` yang berulang pada semua item.

POS tetap boleh memiliki route teknis `/merchant/pos/...`, tetapi route tersebut dirender dalam `MerchantLayout` dan tidak menjadi pusat navigasi baru.

## Alur Aktivasi POS

### Langkah 1 — Pilih Kebutuhan

Pertanyaan yang disarankan:

> Apakah Anda juga menerima pembayaran langsung di toko fisik?

Pilihan:

- Belum, saya hanya berjualan online;
- Ya, saya memiliki toko retail;
- Ya, saya menjalankan kafe atau restoran;
- Ya, saya memiliki beberapa outlet.

### Langkah 2 — Pilih Modul

Tampilkan rekomendasi berdasarkan jenis bisnis, tetapi izinkan merchant menyesuaikannya.

Contoh rekomendasi kafe:

- Kasir;
- Meja;
- KDS;
- Menu QR;
- Bahan baku;
- Resep.

### Langkah 3 — Sinkronkan Katalog

Tawarkan pilihan:

- gunakan katalog merchant yang sudah ada;
- buat katalog kasir baru;
- pilih produk tertentu untuk dijual di outlet.

Pilihan default sebaiknya **gunakan katalog yang sama** agar tidak terjadi duplikasi produk.

### Langkah 4 — Buat Outlet

Minta:

- nama outlet;
- alamat;
- nomor telepon;
- timezone;
- mata uang.

Outlet hanya wajib dibuat jika modul kasir benar-benar diaktifkan.

### Langkah 5 — Undang Tim

Opsional:

- owner;
- manager;
- kasir;
- staff gudang;
- purchasing;
- finance.

## Integrasi Data yang Wajib

Produk, stok, pelanggan, promo, dan laporan harus memiliki sumber data merchant yang sama.

### Kepemilikan Data

Merchant adalah sumber kepemilikan data. POS hanya menambahkan kanal dan operasi yang membutuhkan transaksi langsung.

```text
merchant_id
  ├── products
  ├── customers
  ├── inventory / stock ledger
  ├── promotions
  ├── online orders
  ├── pos outlets
  └── pos transactions
```

Jangan membuat katalog POS, daftar pelanggan POS, atau stok POS yang terpisah tanpa alasan bisnis yang jelas. Jika sebuah tabel POS perlu menyimpan salinan data untuk performa, salinan tersebut harus memiliki sumber utama yang jelas dan mekanisme sinkronisasi yang dapat diaudit.

### Produk dan Stok

Produk yang dibuat di katalog merchant dapat digunakan oleh kasir. Penjualan dari kanal apa pun harus memperbarui stok yang sama.

Kanal transaksi yang disarankan:

```text
marketplace
online_store
pos
manual
```

Contoh:

- Produk terjual di marketplace → stok outlet atau stok merchant berkurang.
- Produk terjual di kasir → stok marketplace ikut diperbarui.
- Produk dibuat di katalog merchant → dapat dipilih di kasir setelah POS aktif.
- Merchant tidak perlu membuat ulang produk ketika mengaktifkan POS.
- Menonaktifkan POS tidak menghapus produk, pelanggan, atau histori transaksi merchant.

### Pesanan dan Laporan

Dashboard Merchant harus merangkum kanal online dan offline. Filter kanal dapat digunakan jika merchant ingin melihat detail.

Contoh filter:

- Semua kanal;
- Marketplace;
- Toko online;
- Kasir;
- Outlet tertentu;
- Periode tertentu.

Jangan membuat laporan POS yang sepenuhnya terpisah jika metriknya dapat menjadi bagian dari laporan merchant.

## Batas antara Modul dan Kepemilikan

POS boleh memiliki fitur khusus seperti:

- proses pembayaran kasir;
- shift;
- outlet;
- meja;
- KDS;
- mode offline;
- printer struk;
- pembukaan dan penutupan kas.

Namun fitur tersebut tetap bekerja atas nama merchant yang sama. Dengan demikian:

- `merchant_id` adalah pemilik bisnis;
- `outlet_id` adalah lokasi operasional;
- `pos_transaction_id` adalah transaksi kanal kasir;
- `user_id` adalah pengguna yang menjalankan aktivitas;
- `channel = pos` membedakan kanal transaksi, bukan pemilik bisnis baru.

## Status Fitur dan Role Harus Dipisahkan

Status POS menjawab:

> Apakah merchant memiliki dan mengaktifkan POS?

Role menjawab:

> Apa yang boleh dilakukan user setelah POS aktif?

Contoh:

| Kondisi | Hasil |
| --- | --- |
| POS `inactive` | Semua menu POS disembunyikan. |
| POS `active`, role owner | Semua modul yang diaktifkan dapat diakses. |
| POS `active`, role kasir | Hanya kasir, transaksi, customer dasar, dan shift. |
| POS `active`, role gudang | Stok, supplier, pembelian, transfer stok. |
| POS `active`, role finance | Kas, laporan, cashflow, dan akuntansi. |

## Rekomendasi Data Konfigurasi

Implementasi dapat memakai konfigurasi seperti berikut secara konseptual:

```text
merchant_pos_settings
- merchant_id
- status
- business_type
- enabled_modules
- trial_started_at
- trial_ends_at
- activated_at
- suspended_at
```

Jika sistem sudah memiliki tabel tenant, outlet, subscription, atau POS workspace, gunakan struktur yang sudah ada dan tambahkan status/modul di tempat yang paling dekat dengan kepemilikan merchant. Hindari membuat database POS baru yang terpisah dari merchant.

## Aturan UX Penting

1. Jangan menampilkan menu yang tidak aktif.
2. Jangan memaksa pedagang online membuat outlet kasir.
3. Gunakan istilah `Kasir` atau `Operasional Toko` di UI; gunakan `POS` terutama untuk konteks teknis, paket, atau dokumentasi.
4. Jangan gunakan `Dashboard POS`.
5. Berikan satu CTA aktivasi dari Dashboard Merchant.
6. Setelah aktivasi, tetap kembalikan user ke Dashboard Merchant.
7. Tampilkan outlet aktif sebagai konteks, bukan sebagai aplikasi baru.
8. Gunakan progressive disclosure untuk fitur lanjutan.
9. Menu yang sama tidak boleh muncul dua kali dengan nama berbeda.
10. Perubahan status POS harus langsung memengaruhi navigasi setelah refresh atau perubahan subscription.

## Tahapan Implementasi

### Tahap 1 — Feature Gate

- Tetapkan status POS per merchant.
- Sembunyikan menu POS jika status belum aktif.
- Lindungi route dan mutation POS di server.
- Pertahankan akses role-based setelah fitur aktif.

### Tahap 2 — Aktivasi dan Onboarding

- Tambahkan CTA `Aktifkan Kasir`.
- Tambahkan pilihan jenis bisnis.
- Tambahkan pilihan modul.
- Hubungkan setup dengan merchant yang sedang login.
- Buat outlet sebagai anak merchant yang sama.
- Pastikan tidak ada flow yang membuat merchant baru ketika POS diaktifkan.

### Tahap 3 — Konsolidasi Navigasi

- Pertahankan satu `MerchantSidebar`.
- Masukkan menu POS ke grup bisnis merchant.
- Hapus dashboard POS.
- Hapus label POS yang tidak perlu.
- Tampilkan hanya modul yang aktif dan diizinkan.

### Tahap 4 — Konsolidasi Data

- Pastikan katalog merchant dan katalog kasir memakai sumber produk yang sama.
- Pastikan stok online dan offline memakai ledger stok yang sama.
- Tambahkan kanal transaksi.
- Gabungkan laporan online dan offline di Dashboard Merchant.

### Tahap 5 — Paket Berdasarkan Jenis Bisnis

- Buat preset modul retail.
- Buat preset modul kafe/restoran.
- Buat preset modul sederhana.
- Izinkan owner mengubah modul setelah aktivasi.

## Kriteria Penerimaan

Implementasi dianggap selesai jika:

- Merchant tanpa POS tidak melihat menu POS.
- Merchant tanpa POS tidak diminta membuat outlet kasir.
- Merchant dapat mengaktifkan POS dari Dashboard Merchant.
- Merchant dapat memilih preset sesuai jenis usaha.
- Merchant kafe melihat modul meja/KDS/QR jika diaktifkan.
- Merchant retail tidak otomatis melihat meja/KDS.
- Aktivasi POS menggunakan merchant yang sedang login dan tidak membuat akun merchant kedua.
- Outlet POS selalu terhubung ke merchant pemilik.
- Produk yang sama dapat digunakan di marketplace dan kasir.
- Penjualan online dan offline masuk ke laporan merchant yang sama.
- Tidak ada Dashboard POS kedua.
- Tidak ada sidebar POS kedua.
- Role kasir tidak dapat mengakses laporan atau pengaturan sensitif.
- Perubahan status POS memperbarui menu dan route secara konsisten.

## Rekomendasi Akhir

Gunakan arsitektur:

> **One Merchant Workspace + Optional POS Module + Shared Catalog/Inventory + Role-Based Access**

Ini memberi fleksibilitas untuk berbagai jenis pedagang tanpa mengorbankan integrasi antara marketplace, toko online, outlet fisik, dan kasir.