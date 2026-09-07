# Rencana Bisnis Marketplace Gratis + POS Berbayar

> **Status implementasi — 7 September 2026:** Fase 1 **selesai secara teknis di repository**. Fase 2 **sebagian selesai**: mapping katalog, projection stok, reservation ledger, rekonsiliasi server-side, alert kegagalan/stale projection, constraint database identitas SKU/barcode tenant-scoped, dan validasi aplikasi untuk form katalog sudah tersedia; validasi di staging/production, pengujian konflik, dan pemetaan stok marketplace untuk varian masih terbuka. Fase 3 **selesai secara teknis di repository untuk alur offline dasar**: cache tenant/outlet, antrean IndexedDB idempotent, retry/dead-letter, indikator usia cache, serta conflict center sudah tersedia. Uji perangkat nyata, konflik lintas kanal, dan validasi staging/production masih terbuka. Migration baru belum diterapkan ke staging/production.

## 0. Analisis kesiapan saat ini

| Area | Status | Catatan |
|---|---|---|
| Fondasi aplikasi | **Siap untuk development** | SPA Vite/React/TypeScript, halaman merchant dan POS, serta bootstrap Supabase sudah tersedia. |
| Entitlement POS | **Siap diuji di staging** | Guard server-side, lifecycle trial/paid/grace/suspended/cancelled, audit, export, dan reaktivasi sudah ada di repository. |
| Katalog dan stok non-varian | **Siap diuji di staging** | POS outlet stock menjadi sumber operasional, marketplace menjadi projection, reservation ledger dan rekonsiliasi sudah tersedia. |
| Identitas katalog | **Siap setelah migration diterapkan** | Constraint database dan validasi form untuk SKU/barcode unik per tenant sudah tersedia; validasi konsistensi produk–varian–outlet tetap perlu staging. |
| Projection stale | **Siap setelah migration diterapkan** | Alert warning berbasis umur sinkronisasi dipindai saat halaman Integrasi POS dibuka dan tampil bersama alert error. |
| POS offline | **Siap untuk uji staging/pilot terbatas** | Queue, retry/dead-letter, conflict center, cache stale, dan receipt offline sudah ada; skenario perangkat ditutup, refresh, listrik mati, dan konflik stok masih perlu diuji menyeluruh. |
| Laporan resmi | **Belum siap dipasarkan sebagai laporan resmi** | Rekonsiliasi shift, payment ledger, jurnal canonical, dan audit harian masih menjadi Fase 4. |
| Produksi | **Belum siap** | Migration harus diterapkan dan diuji di staging; variabel Supabase publik, Edge Functions, Auth redirect, dan pilot merchant masih perlu dikonfigurasi. |

**Prioritas kerja:** terapkan migration ke staging, validasi Fase 2, lalu uji perangkat dan konflik Fase 3 sebelum membuka POS secara luas. Jangan menandai fase sebagai siap produksi hanya karena halaman atau RPC sudah ada di repository.

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
- audit log dan kontrol akses.

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

Untuk merchant yang memakai POS:

- **Produk master:** identitas produk, SKU, barcode, varian, harga dasar, dan HPP.
- **POS stock:** stok fisik per outlet; ini sumber kebenaran operasional.
- **Marketplace stock:** projection dari stok POS yang tersedia untuk dijual online.
- **Reservation ledger:** reservasi stok online yang sedang menunggu pembayaran/konfirmasi.
- **Sales ledger:** transaksi POS dan transaksi marketplace yang sudah final.
- **Cash/payment ledger:** pembayaran aktual, settlement, retur, dan mutasi kas.

Untuk merchant marketplace-only:

- `products` tetap menjadi sumber stok marketplace.
- Jika merchant kemudian berlangganan POS, produk yang sama harus di-link atau dimigrasikan secara terkontrol ke katalog POS.
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

Fondasi projection `pos_stock` ke `products.stock`, mapping `pos_marketplace_sync`, dan reservasi stok marketplace sudah searah dengan prinsip ini. Yang perlu dipastikan selanjutnya adalah idempotensi, monitoring, dan pengalaman merchant ketika mapping gagal.

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

---

## 8. KPI bisnis yang harus diukur

### Marketplace

- merchant aktif mingguan/bulanan;
- jumlah produk aktif;
- jumlah order berhasil;
- GMV marketplace;
- conversion rate halaman produk ke checkout;
- merchant activation rate;
- merchant yang menerima order pertama;
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
- waktu dari signup sampai transaksi pertama.

### Kesehatan operasional

- persentase sync sukses;
- jumlah konflik offline;
- jumlah stock mismatch;
- checkout failure rate;
- waktu pemulihan saat POS offline;
- selisih kas saat tutup shift;
- refund/retur rate;
- laporan yang gagal generate/export.

**North Star metric yang disarankan:** merchant aktif yang berhasil mencatat transaksi valid pada bulan berjalan, dengan kanal marketplace atau POS. Jumlah signup saja tidak cukup.

---

## 9. Roadmap implementasi

### Fase 0 — Keputusan produk dan aturan komersial

**Tujuan:** semua pihak memahami perbedaan marketplace dan POS.

- tetapkan definisi gratis, trial, active, grace, suspended, cancelled;
- tetapkan paket awal dan harga uji;
- tetapkan kuota marketplace;
- tetapkan modul POS per paket;
- tetapkan refund, upgrade, downgrade, dan grace period;
- buat halaman pricing dan FAQ;
- sepakati KPI dan dashboard admin.

**Kriteria selesai:** admin dapat menjelaskan kapan merchant boleh memakai marketplace, kapan POS aktif, dan apa yang terjadi saat pembayaran terlambat.

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
- [ ] selesaikan definisi stok varian dan multi-outlet.

**Status saat ini:** **Sebagian selesai.** Migration `21_20260907070000_pos_stock_reconciliation_alerts.sql` menambahkan alert projection durable, retry metadata, safe sync wrapper, dan RPC rekonsiliasi stok. Migration `22_20260907080000_pos_catalog_identity_stale_projection.sql` menambahkan keunikan SKU/barcode lintas produk-varian, validasi tenant/outlet/varian, dan deteksi alert stale berbasis umur; halaman Integrasi POS sekarang memindai dan menampilkan alert stale. Validasi aplikasi katalog kini menolak benturan identitas sebelum request penyimpanan. Definisi projection stok varian marketplace dan pengujian staging untuk multi-outlet/conflict masih terbuka.

**Kriteria selesai:** sebagian tercapai untuk stok produk non-varian yang terhubung. Penjualan POS dan order marketplace sudah memakai guard/reservation/ledger, dan stale projection kini dapat ditandai. Fase belum ditutup sampai cakupan varian, multi-outlet, dan pengujian konflik diverifikasi.

### Fase 3 — POS online/offline yang aman

**Tujuan:** kasir tetap dapat bekerja saat internet tidak stabil tanpa merusak ledger.

- [x] cache katalog per tenant/outlet;
- [x] queue transaksi offline dengan idempotency key;
- [x] validasi ulang di server saat sync;
- [x] deteksi dan tampilkan konflik harga, produk/stok, serta subscription melalui status conflict/dead-letter;
- [x] tampilkan usia cache dan jumlah transaksi belum tersinkron;
- [x] sediakan retry, dead-letter/conflict queue, dan conflict center untuk rekonsiliasi manual;
- [ ] uji perangkat ditutup, browser refresh, listrik mati, dan koneksi putus di tengah checkout;
- [x] bedakan receipt POS dengan invoice marketplace.

**Status saat ini:** **Selesai secara teknis di repository untuk alur offline dasar.** Cache sekarang diganti sebagai snapshot tenant/outlet agar produk yang dihapus/nonaktif tidak tertinggal; antrean menyimpan status `queued`, `syncing`, `failed`, `conflict`, atau `synced`, memakai lease agar klaim yang macet dapat dipulihkan, dan merangkum dead-letter/conflict untuk kasir. Kasir menampilkan usia cache, jumlah antrean, dan tautan ke Conflict Center. Reconnect memulai sync setelah state online benar-benar terpasang, sehingga tidak melewati sync karena timing event browser. Uji perangkat nyata, konflik lintas kanal, serta penerapan migration di staging tetap menjadi prasyarat pilot.

**Kriteria selesai:** kasir dapat bekerja offline secara terbatas dan merchant selalu tahu transaksi mana yang sudah final dan mana yang masih menunggu sync.

### Fase 4 — Laporan yang layak dipercaya

**Tujuan:** merchant tidak mengambil keputusan dari angka yang salah.

- samakan definisi omzet, diskon, pajak, retur, HPP, beban, dan settlement;
- gunakan payment ledger sebagai dasar cashflow;
- hubungkan hutang/piutang ke pembayaran dan kas;
- buat laporan multi-outlet yang tenant/outlet scoped;
- pastikan jurnal debit=kredit;
- tandai laporan pajak sebagai estimasi sampai memenuhi kebutuhan resmi;
- export memakai dataset dan filter yang sama dengan layar;
- tambahkan audit dan rekonsiliasi harian.

**Kriteria selesai:** merchant dapat menutup shift, merekonsiliasi kas, dan memahami mengapa angka laporan berbeda atau sama dengan saldo aktual.

### Fase 5 — Pertumbuhan dan monetisasi lanjutan

- paket multi-outlet;
- add-on pengguna/kasir;
- loyalty lanjutan;
- analitik lanjutan;
- integrasi printer/perangkat;
- integrasi akuntansi setelah jurnal canonical stabil;
- program partner desa/koperasi;
- promo onboarding dengan expiry;
- dukungan prioritas.

---

## 10. Risiko yang harus dihindari

### Jangan menyamakan “menu tersedia” dengan “produk siap”

Menu POS sudah luas, tetapi modul laporan, stok, audit, dan pembayaran harus dinilai dari atomicity, sumber data, dan rekonsiliasi—bukan hanya dari adanya halaman.

### Jangan menutup marketplace saat POS berhenti berlangganan

Marketplace adalah produk gratis dan kanal akuisisi. POS yang tidak aktif seharusnya menghentikan operasi POS baru, bukan menghapus etalase atau histori merchant.

### Jangan membiarkan dua sumber stok diedit bebas

Jika merchant POS boleh mengubah stok melalui `products` dan `pos_stock` sekaligus, integrasi akan kehilangan makna. Arah yang dipilih harus konsisten: POS outlet stock sebagai sumber operasional, marketplace sebagai projection.

### Jangan menyebut simulasi sebagai laporan resmi

Laporan pajak estimasi, cashflow perkiraan, atau ekspor yang tidak mengambil transaksi aktual harus diberi label yang jujur sampai formula dan sumber datanya benar.

### Jangan membuat offline tanpa rekonsiliasi

Offline adalah fitur keandalan, bukan izin untuk melewati aturan server. Semua transaksi offline harus punya status pending/synced/conflict yang dapat diaudit.

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

## Kesimpulan

Strategi terbaik bukan memilih antara online atau offline. Bangun **marketplace online gratis sebagai pintu masuk** dan **POS omnichannel berbayar sebagai mesin operasional**. Keduanya memakai identitas produk dan ledger yang sama, tetapi memiliki aturan transaksi yang berbeda:

- marketplace mengutamakan jangkauan dan reservasi stok;
- POS mengutamakan kecepatan kasir dan ketahanan offline;
- server menjadi sumber kebenaran;
- admin mengendalikan entitlement, harga, dan kualitas;
- merchant selalu dapat melihat status data dan rekonsiliasinya.

Dengan urutan ini, SaDesa dapat bertumbuh dari marketplace komunitas menjadi SaaS operasional UMKM tanpa memaksa semua merchant membayar sejak awal dan tanpa mengorbankan integritas stok maupun keuangan.