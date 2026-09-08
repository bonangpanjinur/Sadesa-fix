# Rencana Bisnis Marketplace Gratis + POS Berbayar

> **Status implementasi — 8 September 2026:** Fase 0, Fase 1, dan Fase 4 **selesai secara teknis di repository**. Dashboard admin sekarang menghitung KPI pertumbuhan POS: attach rate, trial-to-paid, MRR, churn 30 hari, dan kesehatan sinkronisasi. Fase 2 **sebagian selesai secara teknis di repository** untuk mapping katalog, projection stok, reservation ledger, rekonsiliasi server-side, alert kegagalan/stale projection, identitas SKU/barcode tenant-scoped, dan stok varian/outlet; inbox pesanan marketplace yang mandiri dari POS serta QR menu/order meja masih menjadi pekerjaan terbuka. Validasi staging/production dan pengujian konflik juga masih terbuka. Fase 3 **selesai secara teknis di repository untuk alur offline dasar**; uji perangkat nyata, konflik lintas kanal, dan validasi staging/production masih terbuka. Fase 5 **selesai secara teknis di repository** untuk entitlement komersial, promo partner, dan SLA support. Migration baru belum diterapkan ke staging/production.

## 0. Analisis kesiapan saat ini

| Area | Status | Catatan |
|---|---|---|
| Fondasi aplikasi | **Siap untuk development** | SPA Vite/React/TypeScript, halaman merchant dan POS, serta bootstrap Supabase sudah tersedia. |
| Entitlement POS | **Siap diuji di staging** | Guard server-side, lifecycle trial/paid/grace/suspended/cancelled, audit, export, dan reaktivasi sudah ada di repository. |
| Katalog dan stok non-varian | **Siap diuji di staging** | POS outlet stock menjadi sumber operasional, marketplace menjadi projection, reservation ledger dan rekonsiliasi sudah tersedia. |
| Identitas katalog | **Siap setelah migration diterapkan** | Constraint database dan validasi form untuk SKU/barcode unik per tenant sudah tersedia; validasi konsistensi produk–varian–outlet tetap perlu staging. |
| Projection stale | **Siap setelah migration diterapkan** | Alert warning berbasis umur sinkronisasi dipindai saat halaman Integrasi POS dibuka dan tampil bersama alert error. |
| POS offline | **Siap untuk uji staging/pilot terbatas** | Queue, retry/dead-letter, conflict center, cache stale, dan receipt offline sudah ada; skenario perangkat ditutup, refresh, listrik mati, dan konflik stok masih perlu diuji menyeluruh. |
| Laporan resmi | **Siap diuji di staging; belum boleh dipasarkan sebagai laporan resmi** | Kontrak laporan canonical, ledger hutang/piutang, jurnal posted, dan rekonsiliasi harian sudah tersedia; penerapan bundle dan validasi staging/production masih terbuka. |
| Produksi | **Belum siap** | Migration harus diterapkan dan diuji di staging; variabel Supabase publik, Edge Functions, Auth redirect, dan pilot merchant masih perlu dikonfigurasi. |

**Prioritas kerja:** terapkan migration Fase 2–5 ke staging, validasi konflik dan perangkat Fase 2–3, lalu jalankan pilot merchant sebelum membuka POS secara luas. Jangan menandai fase sebagai siap produksi hanya karena halaman, KPI, atau RPC sudah ada di repository.

## 1. Ringkasan keputusan

Model yang paling sehat untuk platform ini adalah **freemium berbasis dua produk yang saling menguatkan**:

1. **Marketplace SaDesa**
   - Gratis untuk semua merchant yang telah memiliki role `merchant`.
   - Merchant dapat menampilkan produk, menerima pesanan online, dan membangun reputasi.
   - Admin mengatur batas pemakaian dan kualitas konten, bukan mengunci akses dasar secara sewenang-wenang.

2. **POS SaDesa**
   - Produk berbayar untuk transaksi toko fisik, outlet, kasir, stok operasional, pembelian, dan laporan.
   - Harga, paket, trial, diskon, suspend, dan override ditentukan admin/super admin.
   - POS terhubung ke marketplace melalui katalog dan ledger stok, bukan melalui dua stok yang berjalan sendiri-sendiri.

3. **Omnichannel**
   - Penjualan offline di POS dan penjualan online di marketplace masuk ke satu model produk dan satu riwayat stok.
   - POS dirancang **offline-first** sehingga kasir tetap dapat menjual ketika internet terputus.
   - Marketplace membutuhkan koneksi internet; pesanan online tidak boleh dibuat seolah-olah sudah mengurangi stok offline sebelum reservasi server berhasil.

4. **Marketplace tidak bergantung pada POS**
   - Upload produk, halaman toko, inbox pesanan, konfirmasi pesanan, dan fulfillment dasar harus tetap tersedia tanpa subscription POS.
   - Subscription POS hanya menambahkan kemampuan operasional toko fisik dan projection katalog ke tenant/outlet POS.
   - POS suspended atau cancelled tidak boleh menutup toko marketplace, menghapus produk, atau menghentikan penerimaan pesanan marketplace.

5. **SaDesa adalah marketplace multi-vertikal**
   - Platform harus dapat melayani barang, makanan/minuman, jasa, sewa, pengalaman wisata, dan transportasi lokal tanpa memaksa semua kategori memakai alur order yang sama.
   - Admin mengatur kategori, template listing, atribut wajib, jenis fulfillment, aturan komisi, dan fitur yang tersedia melalui konfigurasi.
   - Setiap kategori memakai kontrak order dan settlement yang sesuai, tetapi tetap menggunakan identitas merchant, pelanggan, pembayaran, dispute, dan audit platform yang konsisten.

**Rekomendasi utama:** jangan menjual “fitur POS sebagai add-on kecil” saja. Jual POS sebagai **sistem operasional usaha** yang menghemat stok, waktu kasir, dan kesalahan pencatatan, sementara marketplace gratis menjadi jalur akuisisi merchant dan sumber nilai tambahan.

**Keputusan produk:** POS offline bukan sekadar fitur tambahan. Untuk target UMKM, POS harus tetap bisa dipakai untuk transaksi kasir dasar saat koneksi terputus, lalu melakukan sinkronisasi dan rekonsiliasi ketika online kembali.

---

## 2. Alasan model ini cocok untuk SaDesa

### Masalah merchant yang ingin diselesaikan

Pedagang kecil biasanya memiliki tiga kebutuhan berbeda:

- **Ditemukan pelanggan:** etalase online, foto produk, lokasi, ulasan, dan pesanan online.
- **Menjual cepat di toko:** kasir, barcode, pembayaran, struk, shift, dan pelanggan.
- **Mengendalikan usaha:** stok, pembelian, margin, kas, hutang/piutang, dan laporan.

Marketplace gratis menjawab kebutuhan pertama dengan hambatan masuk rendah. POS berbayar menjawab kebutuhan kedua dan ketiga yang memiliki nilai berulang setiap hari.

### Mengapa marketplace sebaiknya gratis

- Menambah jumlah merchant dan variasi produk.
- Menciptakan efek jaringan antara pembeli, desa, kurir, dan pedagang.
- Menjadi jalur trial alami untuk mengedukasi merchant tentang manfaat pencatatan.
- Mengurangi hambatan bagi UMKM yang belum siap membayar software.

Gratis tidak berarti tanpa kendali. Admin tetap perlu mengatur kuota, moderasi, status verifikasi, komisi atau biaya transaksi bila kelak diperlukan, serta perlindungan dari spam dan penyalahgunaan.

### Mengapa POS layak berbayar

POS memiliki manfaat yang lebih terukur:

- transaksi dan stok harian,
- jumlah kasir dan outlet,
- perangkat/printer,
- sinkronisasi marketplace,
- laporan usaha,
- dukungan dan pemulihan data,
- kontrol akses staf.

Merchant yang sudah bergantung pada POS memiliki willingness-to-pay lebih tinggi daripada merchant yang baru membuat etalase online.

### Cakupan usaha multi-vertikal

SaDesa sebaiknya menggunakan **template kategori**, bukan satu formulir produk yang dipaksakan untuk semua usaha:

| Vertikal | Contoh merchant | Model listing/order | Data penting |
|---|---|---|---|
| Barang retail | kaos, baju, kelontongan, oleh-oleh kering | beli produk, pickup atau kirim | varian, ukuran, warna, stok, SKU, berat, pengiriman |
| Makanan/minuman | warung, kafe, katering, minuman | pesan sekarang, pickup, delivery, atau order meja | modifier, level/topping, waktu siapkan, jam tersedia, stok bahan |
| Jasa terjadwal | barbershop, pijat, fotografer, photobox, servis | booking slot atau request jadwal | durasi, tenaga kerja, lokasi, jadwal, deposit, pembatalan |
| Jasa panggilan | tukang listrik, tukang air, tukang cuci, teknisi | request pekerjaan dan penawaran | area layanan, biaya kunjungan, estimasi, bukti pekerjaan, status provider |
| Sewa | alat, kendaraan, perlengkapan acara, studio | booking rentang waktu dengan deposit | kalender ketersediaan, durasi, deposit, denda, kondisi barang |
| Wisata/pengalaman | paket desa, pemandu, ojek wisata, tur lokal | booking kapasitas atau rute | jadwal, titik temu, kapasitas, peserta, tarif rute, operator |

Fitur bersama tetap harus tersedia untuk semua vertikal: profil merchant, katalog/listing, pencarian, checkout atau booking, notifikasi, pembayaran, status order, chat atau instruksi, ulasan, refund, dispute, payout, dan audit. Perbedaannya berada pada template listing, state machine order, fulfillment, dan settlement.

### Strategi peluncuran multi-vertikal

Jangan meluncurkan semua kategori sekaligus hanya karena sistem dapat menampungnya. Gunakan pendekatan bertahap:

1. **Gelombang awal:** barang retail, makanan/minuman, dan jasa terjadwal karena kebutuhan lokalnya mudah dipahami dan frekuensi order dapat diukur.
2. **Gelombang kedua:** jasa panggilan, sewa, dan photobox/fotografi setelah scheduling, area layanan, deposit, dan dispute stabil.
3. **Gelombang ketiga:** wisata, paket pengalaman, dan ojek wisata setelah kapasitas, operator, rute, keselamatan, serta settlement partner tervalidasi.

Setiap gelombang harus memiliki owner bisnis, target supply merchant, target demand pelanggan, SLA fulfillment, aturan pembatalan, dan metrik unit economics sendiri. Kategori baru tidak cukup hanya ditambahkan ke dropdown.

---

## 3. Batas produk yang harus tegas

### Marketplace gratis

Fitur dasar yang sebaiknya tersedia untuk seluruh merchant aktif:

- profil toko dan jam operasional;
- katalog produk;
- kategori, foto, harga, varian, dan stok;
- halaman toko publik;
- pesanan marketplace;
- konfirmasi pesanan dan status fulfillment dasar;
- inbox pesanan marketplace yang dapat dipakai tanpa POS;
- ulasan dan rating;
- promosi dasar yang dibatasi;
- statistik ringan;
- penarikan saldo sesuai aturan platform.

### Batasan marketplace yang dapat dikendalikan admin

Batasan harus transparan dan mudah dipahami. Contoh:

| Area | Paket marketplace gratis yang disarankan |
|---|---|
| Produk aktif | 50–100 produk, dapat diubah admin per segmen |
| Foto produk | Batas ukuran/kuota penyimpanan yang wajar |
| Pesanan | Tidak dibatasi secara keras; gunakan rate limit dan proteksi abuse |
| Promosi | Promo dasar; kampanye besar memerlukan eligibility |
| Statistik | Ringkasan 7/30 hari; analitik lanjutan menjadi nilai POS |
| Outlet | 1 lokasi marketplace utama |
| Pengguna staf | Pemilik saja |
| Import/export | Export dasar; import massal dapat dibatasi |
| Dukungan | Self-service dan pusat bantuan |

**Prinsip penting:** jangan membatasi jumlah order sukses hanya untuk mendorong upgrade. Itu merusak marketplace dan menghukum merchant yang sedang tumbuh. Batasi fitur operasional lanjutan, kapasitas, analitik, dan automasi.

### POS berbayar

Fitur POS yang menjadi alasan upgrade:

- tenant usaha dan multi-outlet;
- kasir dan role staf;
- PIN kasir;
- barcode scanner;
- checkout tunai, QRIS, transfer, debit, dan metode lain;
- hold/resume bill;
- struk dan reprint;
- sesi kas dan tutup shift;
- stok per outlet;
- stok opname, mutasi, transfer, dan pembelian;
- retur;
- pelanggan dan loyalty;
- laporan kasir, outlet, stok, penjualan, laba rugi, dan cashflow;
- mode offline untuk penjualan kas;
- sinkronisasi POS–marketplace;
- QR menu dan pemesanan sesuai meja per outlet;
- audit log dan kontrol akses.

### Pesanan meja melalui QR POS

Pemesanan meja adalah fitur POS opsional, bukan perilaku default semua toko marketplace:

- QR dibuat oleh tenant POS untuk kombinasi outlet dan meja tertentu.
- Untuk kebutuhan meja, gunakan **QR code**, bukan barcode satu dimensi, karena pelanggan akan memindainya dengan kamera ponsel.
- Scan QR membuka toko Merchant yang sama, tetapi membawa konteks outlet dan meja yang telah divalidasi server.
- Toko yang dibuka dari marketplace atau tautan biasa tetap menjadi toko online normal tanpa konteks meja.
- Tombol atau alur “pesan untuk meja” hanya boleh muncul setelah konteks QR meja berhasil diverifikasi; parameter meja yang diketik atau diubah manual dari URL tidak cukup.
- Order meja dan order marketplace boleh memakai katalog, harga, reservasi, dan ledger stok yang sama, tetapi harus menyimpan kanal/sumber order yang berbeda agar fulfillment dan laporan tidak tercampur.
- QR harus memiliki scope tenant/outlet/meja, dapat dinonaktifkan atau dicabut, tidak mengekspos ID internal secara langsung, dan dilindungi dari penyalahgunaan serta order berulang.
- Jika POS tidak aktif, outlet atau meja tidak tersedia, atau QR sudah dicabut, sistem harus menolak konteks meja dengan jelas dan tidak diam-diam menganggapnya sebagai order meja.

Fitur ini memberikan nilai tambahan yang jelas untuk POS tanpa mengurangi akses marketplace gratis. Satu merchant tetap memiliki satu toko publik; QR hanya menambahkan mode pemesanan berbasis meja.

---

## 4. Model paket dan harga

Harga berikut adalah **hipotesis awal untuk diuji**, bukan harga final. Admin/super admin perlu dapat mengubah harga tanpa perubahan kode.

### Paket yang disarankan

| Paket | Target | Harga uji | Isi utama |
|---|---|---:|---|
| Marketplace | Semua merchant | Gratis | Etalase online, pesanan, katalog dasar, statistik ringan |
| POS Starter | Warung/toko kecil, 1 outlet | Rp49.000–79.000/bulan | 1 outlet, 2 pengguna, kasir, stok dasar, transaksi, laporan dasar |
| POS Growth | Toko berkembang | Rp129.000–199.000/bulan | 1–3 outlet, lebih banyak kasir, pembelian, retur, loyalty, laporan lanjutan, offline sync |
| POS Business | Retail/multi-outlet | Rp299.000–499.000/bulan | multi-outlet lebih luas, akses granular, analitik, audit, prioritas dukungan |
| Add-on outlet | Merchant multi-outlet | Rp25.000–75.000/outlet/bulan | outlet tambahan sesuai batas paket |

### Aturan monetisasi

- Sediakan **trial POS 14 atau 30 hari** setelah merchant aktif.
- Saat trial berakhir, blokir operasi POS baru secara bertahap, tetapi jangan menghapus data.
- Izinkan merchant melihat dan mengekspor data historis setelah suspend.
- Data marketplace tetap aktif selama merchant memenuhi aturan marketplace.
- Jangan menjual paket dengan kuota yang tidak jelas.
- Harga, periode tagihan, pajak, status pembayaran, grace period, dan suspend harus terlihat di halaman langganan.
- Perubahan harga hanya berlaku untuk periode berikutnya dan harus memberi notifikasi.
- Berikan diskon onboarding untuk desa, koperasi, atau program pemerintah secara terukur dan memiliki tanggal berakhir.

### Mesin monetisasi yang dapat dikonfigurasi admin

Admin/super admin boleh mengubah status gratis, berbayar, tarif, komisi, dan eligibility tanpa perubahan kode, tetapi semua aturan harus memiliki versi, tanggal efektif, scope, dan audit. Jenis monetisasi yang dapat digunakan:

| Sumber pendapatan | Cara kerja | Cocok untuk |
|---|---|---|
| Langganan POS | biaya bulanan berdasarkan outlet, pengguna, modul, atau kapasitas | semua merchant yang membutuhkan operasional toko |
| Komisi order | persentase dari nilai barang/jasa setelah aturan diskon yang ditentukan | barang, makanan, jasa, wisata |
| Biaya transaksi tetap | nominal per order atau booking | order bernilai kecil, booking jasa, tiket |
| Biaya lead/booking | biaya saat pelanggan mengirim request atau booking terkonfirmasi | jasa panggilan, fotografer, tukang, ojek wisata |
| Listing atau promosi | biaya untuk featured placement, kampanye, atau slot promosi | merchant yang ingin meningkatkan jangkauan |
| Add-on operasional | outlet, pengguna, printer, analitik, loyalty, atau dukungan prioritas | merchant POS dan merchant profesional |
| Layanan platform | biaya delivery, payment handling, escrow, atau proteksi tertentu | order yang memakai layanan tambahan platform |
| Program partner | paket khusus desa, koperasi, sponsor, atau institusi | akuisisi merchant dan distribusi lokal |

#### Dimensi aturan tarif

Mesin tarif harus dapat menentukan aturan berdasarkan:

- kategori atau template usaha;
- kanal order: marketplace, POS, QR meja, booking, atau rental;
- merchant, tier merchant, wilayah, partner, atau program subsidi;
- nilai order, jenis pembayaran, biaya delivery, dan status fulfillment;
- tanggal efektif, masa promosi, minimum fee, maksimum fee, dan kuota;
- siapa yang menanggung biaya: merchant, pelanggan, partner, atau dibagi.

Tarif tidak boleh dihitung ulang secara berbeda di layar, checkout, payout, dan laporan. Saat order dibuat, sistem menyimpan snapshot harga, komisi, pajak, diskon, biaya layanan, dan net payout yang berlaku pada saat itu.

#### Admin boleh mengubah gratis menjadi berbayar, dengan guardrail

Fleksibilitas bisnis penting, tetapi perubahan mendadak dapat merusak kepercayaan dan membuat dispute. Setiap perubahan monetisasi harus:

1. dibuat sebagai aturan baru dengan tanggal efektif di masa depan;
2. menampilkan simulasi dampak terhadap merchant, pelanggan, GMV, dan payout;
3. tidak mengubah order, booking, sewa, atau transaksi yang sudah dibuat;
4. memberi notifikasi dan ringkasan biaya sebelum berlaku;
5. memiliki masa transisi atau grandfathering bila dampaknya besar;
6. memiliki owner, alasan, approval, dan audit trail;
7. dapat di-rollback atau diganti dengan aturan koreksi tanpa menghapus histori;
8. menampilkan rincian fee secara jelas sebelum checkout dan pada laporan payout.

Dengan aturan ini, admin dapat mengubah Marketplace dari gratis menjadi berkomisi, membuat kategori tertentu berbayar, atau menguji tarif baru kapan saja secara bisnis—tanpa merusak transaksi yang sedang berjalan.

#### Rekomendasi tahap monetisasi

1. Awali marketplace dengan akses gratis dan fee rendah atau nol untuk kategori prioritas agar supply tumbuh.
2. Ukur order sukses, biaya support, fraud, payment, delivery, dan payout sebelum menetapkan take rate.
3. Terapkan komisi atau biaya booking pada kategori yang sudah menghasilkan nilai nyata.
4. Monetisasi POS berdasarkan penghematan operasional, bukan dengan mengunci inbox marketplace.
5. Tambahkan featured listing dan layanan premium setelah pencarian organik serta kualitas katalog cukup sehat.

### Settlement, payout, dan dispute lintas vertikal

Settlement tidak boleh memakai satu aturan untuk semua kategori:

- **Barang:** payout setelah fulfillment atau delivery berhasil dan periode komplain yang ditentukan.
- **Makanan/minuman:** payout setelah order selesai; pembatalan sebelum diproses mengikuti kebijakan merchant.
- **Jasa:** payout setelah provider menandai selesai dan pelanggan atau timer penyelesaian mengonfirmasi.
- **Sewa:** deposit ditahan sampai aset kembali dan pemeriksaan kerusakan selesai.
- **Wisata/ojek:** payout setelah jadwal atau perjalanan selesai, dengan aturan no-show dan pembatalan.

Semua kategori tetap membutuhkan fee ledger, payout ledger, refund, dispute, adjustment, dan audit yang dapat direkonsiliasi. Platform tidak boleh menganggap order berhasil sebagai pendapatan bersih sebelum kewajiban kepada merchant, provider, pelanggan, pajak, dan partner dihitung.

### Trial dan grace period

Alur yang disarankan:

1. Merchant yang disetujui memilih “Coba POS”.
2. Admin/super admin mengaktifkan entitlement trial.
3. Merchant menyelesaikan setup usaha, outlet, produk, dan kasir.
4. H-7 dan H-1, sistem mengirim pengingat.
5. Saat jatuh tempo, masuk **grace period 3–7 hari**.
6. Selama grace period, transaksi masih dapat berjalan dengan peringatan.
7. Setelah suspend:
   - transaksi POS baru dihentikan;
   - data dan laporan tetap dapat dibaca;
   - export tetap tersedia;
   - marketplace tetap mengikuti status marketplace;
   - reaktivasi tidak boleh menggandakan tenant, outlet, atau produk.

Struktur yang sudah ada (`pos_subscriptions`, status tenant POS, trial, entitlement activation, dan enabled modules) dapat menjadi fondasi alur ini.

---

## 5. Arsitektur bisnis: satu katalog, dua kanal, satu ledger stok

### Sumber kebenaran yang direkomendasikan

Untuk seluruh merchant, **Katalog Merchant** adalah tempat membuat dan mengelola produk master:

- identitas produk, foto, kategori, SKU, barcode, varian, dan informasi jual dibuat dari katalog Merchant;
- merchant tanpa POS menggunakan katalog tersebut langsung untuk halaman marketplace dan pesanan online;
- inbox pesanan marketplace tidak boleh membutuhkan `pos_tenant`, subscription POS, atau status operasional POS.

Untuk merchant yang memakai POS:

- **Produk master:** identitas produk, SKU, barcode, varian, harga dasar, dan HPP.
- **POS catalog projection:** salinan operasional yang menunjuk kembali ke produk master Merchant; bukan produk baru yang dibuat ulang.
- **POS stock:** stok fisik per outlet; ini sumber kebenaran operasional.
- **Marketplace stock:** projection dari stok POS yang tersedia untuk dijual online.
- **Reservation ledger:** reservasi stok online yang sedang menunggu pembayaran/konfirmasi.
- **Sales ledger:** transaksi POS dan transaksi marketplace yang sudah final.
- **Cash/payment ledger:** pembayaran aktual, settlement, retur, dan mutasi kas.

Untuk merchant marketplace-only:

- katalog dan stok marketplace tetap dapat berjalan tanpa tenant POS.
- Jika merchant kemudian berlangganan POS, produk yang sama harus diproyeksikan atau di-link secara terkontrol ke katalog/stok POS.
- Sistem tidak boleh membuat produk duplikat hanya karena merchant mengaktifkan POS.

### Aturan penting integrasi katalog

1. Satu produk memiliki satu identitas lintas kanal.
2. SKU dan barcode harus unik di dalam tenant, kecuali ada aturan varian yang jelas.
3. Perubahan produk di marketplace harus menjelaskan apakah perubahan itu juga memengaruhi POS.
4. Produk yang sudah terhubung POS tidak boleh mengubah stoknya dari dua tempat.
5. Harga online dan harga toko boleh berbeda, tetapi sumber aturan harga harus terlihat.
6. Nonaktif di marketplace tidak boleh otomatis menghapus histori POS.
7. Unlink produk memerlukan konfirmasi dan aturan stok yang jelas.
8. Setiap kegagalan sinkronisasi harus terlihat oleh merchant dan dapat direkonsiliasi.
9. Status subscription POS tidak boleh menjadi syarat untuk membuat produk atau menerima order marketplace.
10. Katalog yang belum diproyeksikan ke POS tetap sah untuk marketplace dan tidak boleh dianggap gagal hanya karena merchant belum memilih POS.

Fondasi projection `pos_stock` ke `products.stock`, mapping `pos_marketplace_sync`, dan reservasi stok marketplace sudah searah dengan prinsip ini. Yang perlu dipastikan selanjutnya adalah idempotensi, monitoring, dan pengalaman merchant ketika mapping gagal.

### Kontrak kanal pesanan

- **Marketplace order:** dibuat dari toko publik atau marketplace, tidak membutuhkan POS, dan masuk ke inbox pesanan Merchant gratis.
- **POS sale:** dibuat oleh kasir atau alur operasional POS, membutuhkan entitlement POS aktif dan outlet yang valid.
- **Table order:** dibuat setelah QR meja POS berhasil diverifikasi; memakai toko/katalog yang sama, tetapi membawa konteks meja dan outlet.

Ketiga kanal tersebut boleh menggunakan produk master dan ledger stok yang sama, tetapi sumber order, hak akses, status fulfillment, dan metriknya harus dapat dibedakan. Menonaktifkan POS hanya menghentikan POS sale dan table order baru; marketplace order tetap diterima sesuai aturan marketplace.

---

## 6. POS Offline-First dan Cara Kerja Online

### Keputusan offline

POS **boleh digunakan offline**, tetapi tidak semua operasi boleh dilakukan tanpa koneksi. Batasan ini diperlukan agar merchant tetap bisa berjualan tanpa memberi kesempatan pada transaksi ganda, stok negatif, atau laporan palsu.

| Operasi | Saat offline | Aturan |
|---|---|---|
| Membuka layar kasir | Boleh | Harus memakai tenant, outlet, dan user yang sudah tersimpan di perangkat |
| Melihat katalog | Boleh | Menampilkan waktu terakhir sinkronisasi dan status data stale |
| Penjualan tunai | Boleh | Masuk antrean lokal dengan idempotency key |
| Cetak struk | Boleh | Struk diberi penanda offline/pending bila belum tersinkron |
| Hold/resume bill | Boleh | Hanya pada perangkat dan outlet yang sama |
| Pembayaran QRIS/transfer online | Tidak | Memerlukan validasi provider/server |
| Order marketplace | Tidak | Marketplace memerlukan koneksi dan reservation server |
| Perubahan harga massal | Tidak | Harus online dan memiliki otorisasi |
| Penyesuaian stok besar | Tidak | Harus online agar tercatat atomic dan diaudit |
| Tutup shift final | Sebaiknya online | Dapat membuat draft offline, tetapi finalisasi memerlukan rekonsiliasi |
| Laporan final | Tidak | Offline hanya menampilkan ringkasan lokal sementara |

### Syarat agar offline aman

- Cache katalog dan stok dipisahkan berdasarkan `tenant_id` dan `outlet_id`.
- Cache memiliki waktu kedaluwarsa dan indikator “terakhir diperbarui”.
- Setiap transaksi offline memiliki ID unik yang tidak berubah saat retry.
- Transaksi tidak boleh dikirim dua kali ketika perangkat reconnect atau halaman dibuka ulang.
- Harga dan status produk divalidasi ulang oleh server saat sinkronisasi.
- Transaksi offline tidak boleh memaksa stok server menjadi negatif.
- Semua konflik masuk ke daftar yang bisa ditinjau merchant, bukan hilang atau otomatis diabaikan.
- Queue lokal harus dibersihkan secara aman setelah transaksi benar-benar tersimpan di server.
- Perangkat yang logout, hilang, atau berganti outlet tidak boleh membaca antrean tenant/outlet lain.
- Data lokal sensitif perlu dilindungi dan memiliki kebijakan penghapusan perangkat.

Fondasi proyek saat ini sudah mengarah ke model ini melalui cache katalog per tenant/outlet, antrean transaksi lokal, `processAtomicPOSSale`, serta sinkronisasi ketika koneksi kembali. Fondasi tersebut perlu diselesaikan dengan rekonsiliasi konflik, indikator stale data, pemulihan perangkat, dan pengujian kehilangan koneksi sebelum dipasarkan sebagai offline POS.

### Saat online

Alur POS:

1. Kasir memilih produk dari katalog tenant dan outlet aktif.
2. Server memvalidasi harga, diskon, pajak, stok, hak kasir, dan status subscription.
3. Checkout atomic membuat transaksi, item, pengurangan stok, dan audit.
4. Jika produk terhubung marketplace, projection stok diperbarui.
5. Jika ada order marketplace, reservation ledger mencegah overselling.

Alur marketplace:

1. Pembeli melihat projection stok yang tersedia.
2. Saat checkout, server membuat reservation dengan expiry.
3. Pembayaran/konfirmasi menentukan apakah reservation dikonsumsi atau dilepas.
4. Order marketplace tidak boleh hanya mengandalkan angka stok dari browser.

Alur order meja:

1. Merchant POS membuat QR untuk outlet dan meja yang aktif.
2. Pelanggan memindai QR dan server memverifikasi token tenant, outlet, meja, serta status POS.
3. Pelanggan melihat katalog toko yang sama dalam konteks meja.
4. Saat checkout, server membuat reservation dan order dengan sumber `table_qr`.
5. POS/outlet menerima order meja melalui inbox operasional yang sesuai; status meja tidak mengubah perilaku toko publik.

### Saat offline

Offline hanya untuk operasi yang memang aman ditunda:

- transaksi kasir lokal;
- pembayaran tunai;
- cetak struk lokal;
- membaca katalog dan stok cache;
- menyimpan antrean transaksi terenkripsi/terisolasi per tenant dan outlet.

Offline tidak boleh mengklaim secara langsung bahwa:

- pembayaran online sudah berhasil;
- stok marketplace sudah berkurang;
- settlement sudah terjadi;
- order marketplace sudah diterima;
- laporan keuangan final sudah tersinkron.

### Saat tersambung kembali

1. Cek identitas tenant, outlet, dan kasir.
2. Kirim transaksi berdasarkan idempotency key.
3. Server memvalidasi harga dan aturan saat transaksi dibuat.
4. Jika harga/produk berubah, tandai konflik; jangan diam-diam mengubah total.
5. Jika stok online dan offline berbenturan, gunakan aturan server dan tampilkan konflik.
6. Simpan status `queued`, `synced`, `failed`, atau `conflict`.
7. Merchant dapat melihat dan menyelesaikan konflik.
8. Setelah sync, projection marketplace dijalankan ulang dan hasilnya dicatat.

Implementasi antrean offline dan `processAtomicPOSSale` sudah menyediakan arah teknis yang baik. Sebelum dianggap siap komersial, tambahkan rekonsiliasi konflik, batas umur cache, indikator stale data, dan prosedur pemulihan perangkat rusak/hilang.

### Kebijakan konflik stok

Prioritas yang disarankan:

1. Transaksi online yang sudah memiliki reservation valid.
2. Transaksi POS yang sudah tersimpan server.
3. Transaksi offline yang baru diantrekan.

Transaksi offline yang datang terlambat tidak boleh memaksa stok menjadi negatif. Sistem harus menandainya sebagai konflik untuk keputusan merchant, misalnya:

- batalkan item;
- ganti jumlah;
- ubah menjadi hutang/pesanan;
- tandai sebagai transaksi manual yang perlu rekonsiliasi.

---

## 7. Peran admin dan super admin

### Admin operasional

- menyetujui dan menonaktifkan merchant;
- mengatur kuota marketplace;
- mengelola paket, harga, trial, grace period, dan modul;
- menangani refund/kompensasi sesuai kewenangan;
- melihat kegagalan sinkronisasi;
- membantu onboarding dan support.

### Super admin

- mengubah katalog paket dan harga;
- memberi override entitlement dengan alasan dan tanggal berakhir;
- mengatur rule global marketplace;
- mengelola admin dan audit;
- melihat metrik pendapatan, churn, penggunaan, dan kesehatan sinkronisasi;
- menyetujui kebijakan diskon desa/koperasi;
- tidak mengubah histori transaksi secara langsung.

### Guardrail admin

Setiap perubahan berikut wajib memiliki actor, alasan, waktu, nilai sebelum, nilai sesudah, dan expiry bila relevan:

- perubahan harga paket;
- pemberian trial/discount/override;
- suspend/reaktivasi POS;
- perubahan kuota merchant;
- koreksi saldo;
- perubahan rekening payout;
- pembatalan atau koreksi transaksi.

### Panel admin yang disarankan

Dashboard admin sebaiknya menjadi **control tower operasional**, bukan hanya halaman KPI. Admin perlu dapat melihat antrean yang membutuhkan tindakan, dampak bisnisnya, dan siapa yang bertanggung jawab:

1. **Lifecycle merchant**
   - antrean pendaftaran, verifikasi identitas/usaha, aktivasi, merchant yang belum memasang produk, dan merchant yang belum menerima order pertama;
   - checklist onboarding dan alasan merchant berhenti di setiap tahap;
   - kemampuan meminta perbaikan data tanpa menghapus draft merchant.
2. **Moderasi katalog dan toko**
   - review foto, kategori, harga tidak wajar, produk terlarang, duplikasi, dan konten spam;
   - status `draft`, `pending_review`, `published`, `rejected`, `suspended` dengan alasan yang dapat dipahami merchant;
   - bulk action harus memiliki preview, batas scope, dan audit.
3. **Order control tower**
   - order baru yang belum diterima, terlambat diproses, dibatalkan, direfund, atau berpotensi sengketa;
   - filter berdasarkan kanal marketplace, POS, dan QR meja;
   - admin membantu perubahan status melalui action resmi, bukan mengedit histori transaksi langsung.
4. **Entitlement dan billing POS**
   - trial yang akan berakhir, pembayaran tertunda, grace period, suspend, reaktivasi, limit outlet/pengguna, dan add-on;
   - setiap override wajib memiliki alasan, tanggal mulai, tanggal berakhir, dan actor.
5. **Category and pricing builder**
   - admin dapat membuat/mengarsipkan kategori dan subkategori;
   - admin memilih template listing, atribut wajib, tipe order, fulfillment, SLA, aturan pembatalan, dan status moderasi;
   - admin mengatur paket gratis/berbayar, komisi, biaya tetap, minimum/maksimum fee, siapa yang menanggung biaya, dan tanggal efektif;
   - setiap perubahan memiliki preview dampak, approval, versi, dan rollback.
6. **Operasional outlet dan QR meja**
   - daftar tenant, outlet, meja, QR aktif, QR dicabut, dan order meja yang belum ditangani;
   - kemampuan menonaktifkan QR tertentu tanpa menutup toko publik atau menghapus histori.
7. **Payout, refund, dan dispute**
   - saldo tertahan, payout gagal, refund yang menunggu persetujuan, sengketa pembeli, dan aging penyelesaian;
   - aturan agar payout tidak dilepas sebelum order memenuhi status fulfillment dan periode risiko yang ditetapkan.
8. **Trust, abuse, dan keamanan**
   - lonjakan order palsu, refund berulang, akun merchant ganda, penggunaan promo yang tidak wajar, QR yang dipindai terlalu sering, dan login/perangkat mencurigakan;
   - flag risiko harus dapat ditinjau tanpa langsung menghapus data atau memblokir merchant secara permanen.
9. **Support dan insiden**
   - tiket dengan SLA, sinkronisasi gagal, stale projection, konflik POS offline, dan insiden pembayaran;
   - incident timeline, owner, status, komunikasi ke merchant, dan postmortem untuk masalah berulang.

### Pemisahan peran admin

Minimal gunakan pemisahan berikut:

- **Admin operasional:** onboarding, moderasi, order, support, dan monitoring sinkronisasi;
- **Admin keuangan:** payout, refund, kompensasi, dan rekonsiliasi saldo;
- **Admin produk/POS:** kategori, template listing, paket, modul, limit, trial, promo, fee engine, dan QR/table-order policy;
- **Super admin:** akses lintas area, approval tindakan berisiko, konfigurasi global, dan audit.

Refund besar, koreksi saldo, perubahan payout, penghapusan merchant, override entitlement, dan perubahan aturan tarif sebaiknya memakai **maker-checker**: satu admin mengajukan, admin lain yang berwenang menyetujui. Ini mengurangi risiko kesalahan tunggal tanpa memperlambat tindakan rutin.

### Alur merchant dan order yang disarankan

#### A. Onboarding marketplace gratis

1. Merchant mendaftar dan melengkapi profil usaha.
2. Merchant dapat membuat draft produk dan memperbaiki data sebelum publikasi.
3. Sistem memeriksa kualitas minimum dan aturan konten.
4. Produk yang lolos tampil di toko publik; merchant memperoleh checklist menuju order pertama.
5. Order masuk ke inbox marketplace merchant tanpa memerlukan tenant atau subscription POS.
6. Merchant menerima, menyiapkan, menyerahkan/mengirim, dan menyelesaikan order.
7. Setelah order selesai, sistem mengatur payout, ulasan, dan metrik merchant.

#### B. Konversi ke POS

1. Merchant menerima edukasi berbasis masalah, misalnya stok outlet, kasir, barcode, atau laporan; bukan dipaksa membayar untuk menerima order marketplace.
2. Merchant memilih trial atau paket POS.
3. Sistem memproyeksikan katalog Merchant ke POS tanpa membuat produk kedua.
4. Merchant menyelesaikan setup outlet, kasir, stok awal, dan bila perlu meja.
5. Aktivasi POS dihitung setelah setup selesai dan transaksi pertama berhasil, bukan hanya setelah subscription dibuat.

#### C. QR meja

1. Merchant POS membuat outlet, meja, dan QR yang aktif.
2. Pelanggan memindai QR; server membuat sesi konteks meja yang memiliki expiry.
3. Pelanggan memilih menu dari katalog Merchant yang sama.
4. Order diberi source `table_qr`, outlet, meja, dan status fulfillment yang jelas.
5. Outlet menerima dan memproses order; perubahan status terlihat oleh pelanggan bila fitur tersebut diaktifkan.
6. Sesi meja ditutup setelah order selesai, dibatalkan, atau melewati expiry; order lama tetap tersimpan.

#### D. POS berhenti berlangganan

1. Sistem mengirim peringatan sebelum trial atau grace berakhir.
2. Saat suspend, POS sale dan QR/table-order baru dihentikan sesuai kebijakan.
3. Marketplace tetap aktif: produk, toko, inbox order, fulfillment, dan histori tidak dihapus.
4. Merchant dapat membaca/mengekspor data dan mengaktifkan kembali POS tanpa duplikasi tenant, outlet, produk, atau order.

Alur ini membuat marketplace menjadi pintu masuk yang bernilai sejak hari pertama, sementara POS memiliki momen upgrade yang jelas ketika merchant sudah merasakan kebutuhan operasional.

---

## 8. KPI bisnis yang harus diukur

### Marketplace

- merchant aktif mingguan/bulanan;
- jumlah produk aktif;
- jumlah order berhasil;
- GMV marketplace;
- conversion rate halaman produk ke checkout;
- merchant activation rate;
- waktu dari pendaftaran ke produk pertama terbit;
- merchant yang menerima order pertama;
- acceptance rate dan fulfillment-on-time rate;
- cancellation, refund, dispute, dan repeat-order rate;
- umur payout tertunda dan payout failure rate;
- merchant yang tetap aktif setelah 30/90 hari.

### POS

- jumlah trial dimulai;
- activation rate: setup selesai dan transaksi pertama;
- trial-to-paid conversion;
- MRR/ARR;
- churn bulanan;
- jumlah transaksi per tenant;
- jumlah outlet dan kasir aktif;
- attach rate: merchant marketplace yang membeli POS;
- penggunaan modul berbayar;
- QR scan-to-order conversion dan table-order completion rate;
- persentase merchant POS yang memakai lebih dari satu modul;
- waktu dari signup sampai transaksi pertama.

### Multi-vertikal dan monetisasi

- merchant aktif per kategori dan template;
- waktu dari onboarding ke listing/order pertama per kategori;
- GMV, jumlah order, booking, rental, dan jasa selesai per kategori;
- gross take rate, net take rate, revenue platform, dan contribution margin per kategori;
- biaya pembayaran, support, refund, fraud, delivery, dan payout per kategori;
- average order value, repeat order, cancellation, no-show, dan dispute per kategori;
- conversion dari marketplace gratis ke POS, featured listing, atau layanan berbayar;
- fee rule yang aktif, merchant terdampak perubahan tarif, dan hasil eksperimen harga;
- jumlah merchant yang menerima fee baru dengan sukses versus yang churn atau mengajukan dispute.

### Kesehatan operasional

- persentase sync sukses;
- jumlah konflik offline;
- jumlah stock mismatch;
- checkout failure rate;
- waktu pemulihan saat POS offline;
- selisih kas saat tutup shift;
- refund/retur rate;
- laporan yang gagal generate/export.
- waktu antrean approval merchant dan moderasi katalog;
- waktu penyelesaian dispute dan tiket berdasarkan SLA;
- jumlah QR/table order invalid atau berulang;
- jumlah merchant marketplace yang terdampak insiden POS.
- jumlah listing pending moderasi dan umur antreannya;
- jumlah perubahan tarif tanpa approval atau tanpa notifikasi;
- payout tertahan berdasarkan alasan dan umur;
- dispute terbuka berdasarkan kategori, status, dan SLA;
- kategori dengan order tinggi tetapi margin kontribusi negatif.

**North Star metric yang disarankan:** merchant aktif yang berhasil mencatat transaksi valid pada bulan berjalan, dengan kanal marketplace atau POS. Jumlah signup saja tidak cukup.

**Guardrail metric yang wajib dipantau:** cancellation rate, refund/dispute rate, payout aging, fulfillment terlambat, stock mismatch, dan merchant yang kehilangan akses marketplace karena kesalahan status POS.

---

## 9. Roadmap implementasi

### Fase 0 — Keputusan produk dan aturan komersial

**Tujuan:** semua pihak memahami perbedaan marketplace dan POS.

- [x] tetapkan definisi gratis, trial, active, grace, suspended, cancelled;
- [x] tetapkan paket awal dan harga uji;
- [x] tetapkan kuota marketplace;
- [x] tetapkan modul POS per paket;
- [x] tetapkan refund, upgrade, downgrade, dan grace period;
- [x] tetapkan marketplace tetap dapat upload produk dan menerima pesanan tanpa POS;
- [x] tetapkan POS sebagai pilihan berbayar yang memproyeksikan katalog Merchant, bukan membuat katalog kedua;
- [x] tetapkan QR meja sebagai fitur POS yang hanya aktif setelah scan dan validasi konteks meja;
- [x] tetapkan marketplace sebagai platform multi-vertikal dengan template kategori dan order;
- [x] tetapkan jenis monetisasi yang dapat dikonfigurasi per kategori, kanal, merchant, dan tanggal efektif;
- [x] tetapkan bahwa perubahan tarif tidak retroaktif dan harus menyimpan snapshot fee pada order;
- [x] buat halaman pricing dan FAQ;
- [x] sepakati KPI dan dashboard admin.

**Kriteria selesai:** admin dapat menjelaskan kapan merchant boleh memakai marketplace, kapan POS aktif, dan apa yang terjadi saat pembayaran terlambat.

**Status saat ini:** **Selesai secara teknis di repository.** Aturan produk dan harga uji terdokumentasi di halaman `/pricing`, FAQ menjelaskan lifecycle marketplace/POS, trial, grace, suspend, dan offline, sedangkan dashboard admin menampilkan North Star metric, activation rate, order completion, GMV periode, serta gap metrik billing yang belum memiliki agregat canonical. Harga di halaman diberi label harga uji dan belum dianggap konfigurasi produksi.

### Fase 1 — Entitlement dan billing yang dapat dipercaya

**Tujuan:** akses berbayar tidak hanya dikontrol oleh frontend.

- [x] jadikan subscription/entitlement sebagai sumber izin server-side;
- [x] pisahkan status merchant marketplace dari status POS;
- [x] dukung trial, paid, grace, suspended, cancelled pada model entitlement POS;
- [x] simpan riwayat perubahan harga/paket;
- [x] pastikan suspend tidak menghapus data POS maupun marketplace;
- [x] sediakan export data subscription dan reaktivasi idempotent yang lengkap;
- [x] batasi operasi POS berdasarkan entitlement dan role;
- [x] tambahkan audit untuk override admin.

**Status saat ini:** **Selesai secara teknis di repository.** Perubahan yang sudah diterapkan:

- migration `19_20260907050000_pos_entitlement_lifecycle.sql` menambahkan `grace_ends_at`, status `grace`, resolver entitlement, dan validasi subscription pada `is_pos_tenant_active`;
- migration `20_20260907060000_pos_subscription_history_export_audit.sql` menambahkan snapshot riwayat paket/harga, export subscription, audit lifecycle admin, dan reaktivasi/approval idempotent;
- edit paket admin menggunakan RPC server-side atomik yang menyimpan alasan perubahan pada history dan audit log;
- merchant dapat mengunduh export data subscription dalam format JSON;
- jalur mutasi POS yang memakai guard tenant, termasuk checkout atomic, tidak lagi hanya mempercayai status tenant dari browser;
- approval/reactivation/extension admin mengatur kembali status tenant dan membersihkan masa tenggang;
- UI langganan menampilkan status masa tenggang dan tanggal akhirnya;
- marketplace tetap terpisah dari status operasional POS ketika POS suspended/cancelled.

**Kriteria selesai fase:** tercapai untuk implementasi teknis di repository. Migration database perlu diterapkan dan diuji di staging sebelum dinyatakan siap produksi.

### Fase 2 — Katalog terpadu dan sinkronisasi stok

**Tujuan:** mencegah produk ganda dan overselling.

- [x] tetapkan mapping produk marketplace–POS;
- [x] gunakan satu SKU/barcode per tenant;
- [x] tampilkan status linked/synced/error di UI;
- [x] gunakan POS outlet stock sebagai sumber operasional merchant POS;
- [x] gunakan reservation ledger untuk order online;
- [x] buat rekonsiliasi manual dan otomatis;
- [x] tambahkan alert jika projection gagal;
- [x] tambahkan alert jika projection terlalu lama/stale;
- [x] selesaikan definisi stok varian dan multi-outlet.
- [ ] pastikan inbox pesanan marketplace dapat digunakan tanpa `pos_tenant` atau entitlement POS;
- [ ] implementasikan QR per outlet/meja dengan token yang scoped, dapat dicabut, dan tervalidasi server-side;
- [ ] bedakan toko publik biasa dari table-order context; URL toko biasa tidak boleh mengaktifkan mode meja;
- [ ] masukkan order meja ke pipeline reservation/stock yang sama dengan kanal lain, dengan source dan fulfillment state yang berbeda;
- [ ] dukung template listing dan atribut berbeda untuk produk, makanan, jasa, sewa, dan pengalaman;
- [ ] bedakan state machine order, booking, rental, dan service request tanpa menggandakan payment/dispute ledger;

**Status saat ini:** **Sebagian selesai secara teknis di repository.** Migration `21_20260907070000_pos_stock_reconciliation_alerts.sql` menambahkan alert projection durable, retry metadata, safe sync wrapper, dan RPC rekonsiliasi stok. Migration `22_20260907080000_pos_catalog_identity_stale_projection.sql` menambahkan keunikan SKU/barcode lintas produk-varian, validasi tenant/outlet/varian, dan deteksi alert stale berbasis umur. Bootstrap `23_20260907100000_pos_variant_outlet_stock_contract.sql` sekarang menetapkan identitas stok sebagai `(produk POS, varian POS opsional, outlet)`, membuat mapping varian marketplace–POS, memastikan satu row stok per identitas dan outlet, memproyeksikan stok varian ke marketplace, serta memakai allocation/reservation lintas outlet tanpa fallback ke stok parent. Test kontrak aplikasi juga memverifikasi isolasi varian, reservasi, dan alokasi deterministik. Kontrak katalog dan stok sudah tersedia, tetapi inbox marketplace yang benar-benar mandiri dari POS, QR/table-order, penerapan bundle, dan pengujian konflik nyata di staging masih terbuka.

**Kriteria selesai:** tercapai untuk implementasi teknis di repository; penjualan POS dan order marketplace memakai identitas varian/outlet yang sama, guard/reservation/ledger, dan stale projection dapat ditandai. Fase belum dinyatakan siap produksi sampai bundle diterapkan serta skenario konflik multi-outlet diverifikasi di staging.

### Fase 3 — POS online/offline yang aman

**Tujuan:** kasir tetap dapat bekerja saat internet tidak stabil tanpa merusak ledger.

- [x] cache katalog per tenant/outlet;
- [x] queue transaksi offline dengan idempotency key;
- [x] validasi ulang di server saat sync;
- [x] deteksi dan tampilkan konflik harga, produk/stok, serta subscription melalui status conflict/dead-letter;
- [x] tampilkan usia cache dan jumlah transaksi belum tersinkron;
- [x] sediakan retry, dead-letter/conflict queue, dan conflict center untuk rekonsiliasi manual;
- [x] uji recovery durable untuk perangkat/tab ditutup, browser refresh, listrik mati, dan koneksi putus di tengah checkout;
- [ ] jalankan uji fisik pada device/PWA staging dan pilot merchant;
- [x] bedakan receipt POS dengan invoice marketplace.

**Status saat ini:** **Selesai secara teknis di repository untuk alur offline dasar dan simulasi recovery.** Cache sekarang diganti sebagai snapshot tenant/outlet dan membawa varian beserta stok outlet; antrean menyimpan status `queued`, `syncing`, `failed`, `conflict`, atau `synced`, memakai lease agar klaim yang macet dapat dipulihkan, dan merangkum dead-letter/conflict untuk kasir. Checkout menulis checkpoint durable sebelum RPC, lalu memulihkannya ke queue dengan request key yang sama setelah tab/perangkat ditutup, refresh, listrik mati, atau koneksi putus. Test recovery mencakup keempat skenario tersebut dan memastikan transaksi yang sudah tersinkron tidak diputar ulang. Build, lint, 39 file test, dan workflow preview terakhir berhasil. Uji fisik device/PWA, konflik lintas kanal, serta penerapan migration di staging tetap menjadi prasyarat pilot.

**Kriteria selesai:** kasir dapat bekerja offline secara terbatas dan merchant selalu tahu transaksi mana yang sudah final dan mana yang masih menunggu sync.

### Fase 4 — Laporan yang layak dipercaya

**Tujuan:** merchant tidak mengambil keputusan dari angka yang salah.

- [x] samakan definisi omzet, diskon, pajak, retur, HPP, beban, dan settlement di kontrak laporan server-side;
- [x] gunakan payment ledger dan transaksi canonical sebagai dasar cashflow, tanpa menjumlahkan penjualan dua kali dari mutasi `sales_cash`;
- [x] hubungkan hutang/piutang ke pembayaran dan kas melalui RPC atomic dan mutasi kas canonical;
- [x] scope laporan berdasarkan tenant dan outlet aktif;
- [x] pastikan posting jurnal memvalidasi debit=kredit dan laporan mendeteksi jurnal tidak seimbang;
- [x] tandai laporan pajak sebagai estimasi sampai memenuhi kebutuhan resmi;
- [x] export laporan laba-rugi dan cashflow memakai state dataset yang sama dengan layar;
- [x] tambahkan snapshot audit dan rekonsiliasi harian yang menjelaskan selisih sesi, mutasi, pembayaran supplier, dan jurnal.

**Status saat ini:** **Selesai secara teknis di repository; siap diuji di staging.** Bundle `24_20260907110000_phase4_canonical_reporting.sql` dan `25_20260907130000_phase4_debt_reconciliation.sql` menyediakan kontrak laporan canonical tenant/outlet-scoped, pembayaran hutang/piutang atomic yang membuat mutasi kas, pembayaran supplier berdasarkan tanggal pembayaran aktual, jurnal posted server-side, dan snapshot rekonsiliasi harian. Halaman laba-rugi, cashflow, akuntansi, hutang/piutang, dan Kas memakai alur canonical tersebut. Laporan pajak tetap estimasi; bundle belum diterapkan dan rekonsiliasi nyata belum diuji di staging/production.

**Kriteria selesai:** merchant dapat menutup shift, merekonsiliasi kas, dan memahami mengapa angka laporan berbeda atau sama dengan saldo aktual. **Tercapai secara teknis di repository; status resmi tetap menunggu staging.**

### Fase 5 — Pertumbuhan dan monetisasi lanjutan

**Status saat ini:** **Sebagian selesai secara teknis di repository; migration dan verifikasi staging masih terbuka.** Fase ini dimulai setelah fondasi Fase 4 dan menambahkan kontrol komersial yang dapat ditegakkan server-side, bukan sekadar label paket di UI.

- [x] paket multi-outlet;
- [x] add-on pengguna/kasir;
- [x] loyalty lanjutan;
- [x] analitik lanjutan;
- [x] integrasi printer/perangkat;
- [x] integrasi akuntansi setelah jurnal canonical stabil;
- [x] program partner desa/koperasi;
- [x] promo onboarding dengan expiry — admin dapat membuat kode partner berkuota, merchant dapat preview dan redeem satu kali, dan kode ditolak setelah expiry;
- [x] dukungan prioritas — tiket merchant paket prioritas mendapat target SLA 4 jam, tiket standar 24 jam, dan admin dapat melihat status SLA/overdue.
- [ ] category builder untuk template listing, atribut, fulfillment, SLA, dan kebijakan pembatalan;
- [ ] fee engine untuk komisi, biaya tetap, booking fee, featured listing, dan siapa yang menanggung biaya;
- [ ] simulasi dampak tarif sebelum publish serta snapshot fee pada setiap order/payout;
- [ ] checklist onboarding merchant sampai produk pertama dan order pertama;
- [ ] control tower admin untuk antrean merchant, katalog, order, payout, dispute, entitlement, dan QR meja;
- [ ] maker-checker untuk refund besar, koreksi saldo, perubahan payout, penghapusan merchant, dan override entitlement;
- [ ] aturan payout berdasarkan fulfillment dan periode risiko yang dapat dikonfigurasi;
- [ ] flag abuse untuk order palsu, refund berulang, promo tidak wajar, dan QR yang disalahgunakan.

**Perubahan teknis yang sudah tersedia:** bundle `26_20260908100000_phase5_commercial_entitlements.sql` menambahkan limit `max_outlets` dan `max_users`, harga add-on pengguna, flag dukungan prioritas, konfigurasi diskon onboarding ber-expiry, tabel promosi onboarding, entitlement summary, serta RPC guard untuk membuat outlet dan pengguna. Bundle `27_20260908120000_partner_promotions_priority_support.sql` menambahkan preview dan redemption promo yang atomic/idempotent, pencatatan nominal asli dan diskon pada subscription, program partner desa/koperasi di admin, serta schema dan RPC SLA support. Form admin menampilkan paket dan promo partner; halaman langganan merchant menghitung harga setelah promo; tiket baru otomatis mendapat prioritas dan due time berdasarkan paket.

**Kriteria selesai sementara:** paket dapat menjelaskan kapasitas outlet/pengguna dan harga add-on, operasi create outlet/user menolak limit melalui RPC, promo partner memiliki redemption serta audit end-to-end, dan SLA support tersimpan pada tiket. Fase belum dinyatakan siap produksi sampai bundle diterapkan di staging dan alur pembayaran/add-on/support diuji.

### Fase 6 — Validasi staging dan pilot merchant

**Status saat ini:** Belum dimulai; ini menjadi gate sebelum fitur pertumbuhan dipasarkan.

- [ ] terapkan bundle Fase 2–5 ke project Supabase staging;
- [ ] uji upgrade/downgrade paket, limit outlet/pengguna, add-on, dan promo expired;
- [ ] uji loyalty, analitik, printer, dan ekspor akuntansi pada merchant dengan data nyata sintetis;
- [ ] uji konflik lintas outlet dan pemulihan POS offline pada perangkat fisik;
- [ ] pilot minimal satu merchant dari barang retail, makanan/minuman, jasa terjadwal, dan jasa panggilan/sewa/wisata;
- [ ] uji template listing, booking slot, deposit sewa, no-show, pembatalan, dan settlement per kategori;
- [ ] uji perubahan marketplace gratis menjadi berkomisi dengan aturan efektif, notifikasi, snapshot fee, rollback, dan order lama;
- [ ] hitung unit economics per kategori sebelum memperluas gelombang peluncuran;
- [ ] uji merchant marketplace-only: upload produk, order masuk, fulfillment, payout, refund, dan dispute tanpa tenant POS;
- [ ] uji transisi marketplace-only ke POS tanpa produk, tenant, outlet, atau histori order duplikat;
- [ ] uji suspend POS: marketplace tetap menerima order, sedangkan transaksi POS dan QR meja mengikuti kebijakan suspend;
- [ ] uji QR meja lintas outlet, QR dicabut, sesi expired, scan berulang, dan order yang sudah berjalan;
- [ ] uji approval maker-checker serta audit untuk refund, payout, moderasi, dan entitlement;
- [ ] jalankan pilot 10–20 merchant dan catat activation, transaksi pertama, sync success, konflik, serta churn awal;
- [ ] dokumentasikan rollback dan prosedur support.

### Fase 7 — Partner, dukungan, dan rollout bertahap

**Status saat ini:** Sebagian selesai secara teknis di repository; rollout tetap menunggu Fase 6.

- [x] program partner desa/koperasi dengan eligibility, tanggal berakhir, kuota, dan audit redemption;
- [x] redemption promo onboarding yang idempotent dan tidak dapat dipakai lintas merchant;
- [x] dukungan prioritas berbasis paket dengan SLA 4 jam dan indikator overdue untuk admin;
- [x] dashboard attach rate, trial-to-paid, MRR, churn, dan kesehatan sync;
- [ ] rollout bertahap berdasarkan hasil pilot, bukan hanya halaman yang sudah tersedia.

Dashboard Fase 7 menggunakan subscription berstatus `PAID`, tenant POS yang memiliki `merchant_id`, dan RPC kesehatan integrasi sebagai sumber metrik. MRR dan churn tetap merupakan metrik operasional sampai migration diterapkan dan angka direkonsiliasi dengan pembayaran nyata di staging.

---

## 10. Risiko yang harus dihindari

### Jangan menyamakan “menu tersedia” dengan “produk siap”

Menu POS sudah luas, tetapi modul laporan, stok, audit, dan pembayaran harus dinilai dari atomicity, sumber data, dan rekonsiliasi—bukan hanya dari adanya halaman.

### Jangan menutup marketplace saat POS berhenti berlangganan

Marketplace adalah produk gratis dan kanal akuisisi. POS yang tidak aktif seharusnya menghentikan operasi POS baru, bukan menghapus etalase atau histori merchant.

### Jangan menjadikan POS sebagai syarat marketplace

Merchant harus dapat upload produk, menerima pesanan, mengonfirmasi fulfillment, dan mengelola toko tanpa membeli POS. Upgrade POS harus menjual efisiensi operasional, bukan membuka akses dasar marketplace yang sebelumnya sudah dijanjikan gratis.

### Jangan membiarkan dua sumber stok diedit bebas

Jika merchant POS boleh mengubah stok melalui `products` dan `pos_stock` sekaligus, integrasi akan kehilangan makna. Arah yang dipilih harus konsisten: POS outlet stock sebagai sumber operasional, marketplace sebagai projection.

### Jangan menyebut simulasi sebagai laporan resmi

Laporan pajak estimasi, cashflow perkiraan, atau ekspor yang tidak mengambil transaksi aktual harus diberi label yang jujur sampai formula dan sumber datanya benar.

### Jangan membuat offline tanpa rekonsiliasi

Offline adalah fitur keandalan, bukan izin untuk melewati aturan server. Semua transaksi offline harus punya status pending/synced/conflict yang dapat diaudit.

### Jangan menyamakan URL toko dengan konteks meja

Toko yang dibuka dari marketplace tetap harus menjadi toko publik biasa. Konteks meja hanya boleh dibuat dari QR POS yang valid, scoped ke outlet/meja, dan diverifikasi server.

### Jangan membayar payout sebelum order cukup aman

Payout terlalu cepat meningkatkan risiko fraud, refund, dan sengketa. Tetapkan status fulfillment, periode penahanan, rule pengecualian, dan jalur dispute sebelum saldo dianggap tersedia.

### Jangan membuat admin sebagai database editor

Admin harus bekerja melalui action bisnis yang terkontrol—approve, reject, refund, suspend, reaktivasi, rekonsiliasi—bukan mengubah row transaksi secara langsung. Koreksi harus menghasilkan adjustment dan audit trail.

### Jangan mengoptimalkan signup saja

Signup yang tidak menghasilkan produk terbit, order pertama, fulfillment, atau transaksi POS tidak menciptakan bisnis yang sehat. Funnel harus diukur sampai nilai nyata diterima merchant dan pelanggan.

### Jangan menambah fitur paid sebelum fondasi operasional siap

Paket tambahan tidak akan memperbaiki marketplace yang order-nya terlambat, payout tidak jelas, atau stok tidak dipercaya. Prioritaskan inbox order, fulfillment, payout, support, dan rekonsiliasi sebelum ekspansi modul.

### Jangan memakai satu alur order untuk semua kategori

Barang, makanan, jasa terjadwal, jasa panggilan, sewa, dan wisata memiliki kebutuhan status, jadwal, kapasitas, deposit, pembatalan, dan bukti selesai yang berbeda. Gunakan template dan state machine per kategori, tetapi jangan menggandakan payment, fee, dispute, dan audit ledger.

### Jangan mengubah tarif secara retroaktif

Admin boleh mengubah marketplace gratis menjadi berkomisi atau mengubah tarif kategori, tetapi order yang sudah dibuat harus memakai snapshot aturan sebelumnya. Perubahan baru memerlukan tanggal efektif, notifikasi, preview dampak, dan audit.

### Jangan memperluas kategori sebelum unit economics terlihat

GMV besar tidak selalu berarti bisnis sehat. Ukur take rate bersih setelah payment, support, refund, fraud, delivery, payout, dan biaya operasional. Kategori dengan order tinggi tetapi margin kontribusi negatif harus diperbaiki atau dibatasi sebelum diperluas.

### Jangan memperlakukan jasa, sewa, dan wisata seperti stok biasa

Jasa membutuhkan jadwal dan kapasitas provider, sewa membutuhkan kalender dan deposit, sedangkan wisata membutuhkan kapasitas, operator, titik temu, dan kebijakan no-show. Kesalahan model dapat menyebabkan double booking, aset hilang, atau sengketa keselamatan.

### Jangan mengumpulkan data kategori tanpa kebijakan privasi

Jasa panggilan, pijat, wisata, transportasi, dan booking dapat memerlukan alamat, jadwal, kontak, atau data peserta. Ambil data minimum yang diperlukan, batasi akses, simpan consent, dan tetapkan retensi serta penghapusan.

---

## 11. Rekomendasi keputusan sekarang

1. **Setujui model bisnis:** marketplace gratis, POS berbayar, POS memiliki trial terbatas.
2. **Gunakan satu katalog lintas kanal:** jangan membuat produk baru saat merchant mengaktifkan POS jika produk lama dapat di-link.
3. **Tetapkan POS stock sebagai sumber stok merchant POS:** `products.stock` hanya projection marketplace.
4. **Pisahkan status dan hak akses:** merchant marketplace tetap aktif meskipun POS suspended.
5. **Prioritaskan kualitas ledger sebelum menambah fitur:** order state machine, stock adjustment atomic, payment/cash ledger, dan laporan canonical.
6. **Mulai dengan satu atau dua paket POS:** terlalu banyak paket akan membingungkan merchant dan admin.
7. **Gunakan trial sebagai onboarding, bukan sekadar masa gratis:** ukur setup selesai dan transaksi pertama.
8. **Lakukan pilot terbatas:** 10–20 merchant dengan tipe usaha berbeda sebelum membuka POS secara luas.
9. **Jangan mengiklankan laporan keuangan/pajak sebagai resmi sebelum rekonsiliasi selesai.**
10. **Jadikan status sinkronisasi terlihat:** merchant harus tahu produk/stok/transaksi mana yang gagal atau menunggu.
11. **Pertahankan inbox pesanan marketplace sebagai fitur gratis:** POS hanya menambah kanal kasir, stok outlet, dan automasi operasional.
12. **Bangun QR meja sebagai mode order terpisah:** gunakan katalog dan stok bersama, tetapi simpan source, konteks meja, dan fulfillment state secara eksplisit.
13. **Jadikan QR dapat dicabut dan diaudit:** merchant harus dapat menonaktifkan meja/outlet atau mengganti QR tanpa memutus toko publik.
14. **Bangun onboarding sampai nilai pertama:** ukur produk pertama terbit, order pertama, fulfillment pertama, dan transaksi POS pertama.
15. **Jadikan admin control tower:** tampilkan antrean tindakan, SLA, risiko, payout, dispute, dan dampak status POS terhadap marketplace.
16. **Pisahkan kewenangan admin:** gunakan role operasional, keuangan, produk/POS, dan super admin dengan maker-checker untuk tindakan berisiko.
17. **Tahan payout secara terukur:** lepaskan dana berdasarkan status fulfillment dan aturan risiko, bukan hanya karena order dibuat.
18. **Jadikan kualitas dan keamanan sebagai fitur bisnis:** moderasi katalog, deteksi abuse, QR yang dapat dicabut, audit, dan pemulihan harus masuk prioritas produk.
19. **Gunakan template kategori:** jangan memaksa kaos, makanan, jasa, sewa, dan wisata memakai form atau state machine yang sama.
20. **Bangun fee engine sebagai konfigurasi bisnis:** admin dapat mengatur komisi, biaya booking, biaya tetap, dan siapa yang membayar tanpa deploy kode.
21. **Mulai dari kategori dengan supply dan demand nyata:** perluas vertikal hanya setelah order, fulfillment, dispute, payout, dan margin kontribusinya terbukti.
22. **Jaga kepercayaan saat monetisasi berubah:** tarif baru harus transparan, terjadwal, tidak retroaktif, dapat diaudit, dan tidak menghukum order yang sudah dibuat.

## Kesimpulan

Strategi terbaik bukan memilih antara online atau offline. Bangun **marketplace multi-vertikal sebagai pintu masuk**, **POS omnichannel berbayar sebagai mesin operasional**, dan **fee engine yang dapat dikonfigurasi sebagai mesin monetisasi**. Keduanya memakai identitas merchant, payment, fee, dispute, dan audit ledger yang konsisten, tetapi memiliki aturan transaksi yang berbeda:

- marketplace mengutamakan jangkauan dan reservasi stok;
- POS mengutamakan kecepatan kasir dan ketahanan offline;
- QR POS menambahkan konteks order meja tanpa membuat toko kedua;
- barang memakai stok dan fulfillment;
- makanan memakai kesiapan produksi dan delivery/pickup;
- jasa memakai jadwal, provider, dan bukti selesai;
- sewa memakai kalender, deposit, dan kondisi aset;
- wisata/ojek memakai kapasitas, rute, operator, dan no-show policy;
- admin mengatur kategori, fee, dan monetisasi dengan tanggal efektif serta audit;
- server menjadi sumber kebenaran;
- admin mengendalikan entitlement, harga, dan kualitas;
- merchant selalu dapat melihat status data dan rekonsiliasinya.

Dengan urutan ini, SaDesa dapat bertumbuh dari marketplace komunitas menjadi SaaS operasional UMKM tanpa memaksa semua merchant membayar sejak awal dan tanpa mengorbankan integritas stok maupun keuangan.