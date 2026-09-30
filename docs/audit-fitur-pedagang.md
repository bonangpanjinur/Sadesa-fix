# Audit UI/UX Fitur Pedagang

**Tanggal audit:** 30 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Cakupan:** inspeksi statis source React/TypeScript, route merchant, komponen layout, state data, navigasi, status pesanan, serta konsistensi ikon. Audit ini belum menggantikan usability test dengan pedagang nyata di perangkat fisik.

## Ringkasan

Workspace pedagang sudah **cukup matang secara fitur** dan beberapa temuan audit sebelumnya sudah diperbaiki di branch aktif. Fondasi yang sudah kuat:

- Sidebar sudah dikelompokkan berdasarkan pekerjaan: Pesanan & Fulfillment, Produk & Stok, Promosi & Pelanggan, Laporan & Keuangan, dan Pengaturan.
- Search menu, state menu aktif, accordion group, drawer mobile, `aria-current`, `aria-expanded`, dan label aksesibilitas sudah tersedia.
- Status/filter pesanan sudah mencakup status operasional tambahan seperti `READY`, `ASSIGNED`, `COURIER_ASSIGNED`, `COURIER_ACCEPTED`, `PICKED_UP`, `ON_DELIVERY`, serta tipe pengiriman `EXPEDITION`.
- Ringkasan pesanan sudah mencoba memakai summary server-side/RPC, bukan hanya array halaman yang sedang tampil.
- Badge realtime pesanan dan ulasan sudah di-scope ke `merchant_id`; badge refund dihitung ulang berdasarkan order milik merchant.
- Pengaturan COD sekarang menyatakan secara eksplisit bahwa COD belum tersedia dan selalu disimpan nonaktif.
- Detail pesanan dan laporan keuangan sudah memiliki loading, error, dan retry state.
- Penyesuaian stok sudah diarahkan melalui `merchant_adjust_stock_atomic`.

Masih ada pekerjaan penting pada **prioritas aksi**, **ketepatan cakupan angka laporan**, **mobile usability**, serta **konsistensi ikon/CTA**.

## Matriks status fitur pedagang

| Area | Status | Yang sudah ada | Yang masih perlu diperbaiki |
|---|---|---|---|
| Dashboard toko | Sebagian | Status buka/tutup, ringkasan pending order, statistik, chart, alert stok, ulasan, QR toko, shortcut | Prioritaskan “Pesanan perlu tindakan” di viewport pertama; ringkas kartu yang tumpang tindih; bedakan data realtime, periode aktif, dan data historis |
| Pesanan | Sebagian besar sudah | Filter status lengkap, filter `EXPEDITION`, summary server-side, detail order, pembayaran, pengiriman, cetak, retry item/payment proof | CTA utama masih banyak tersembunyi di menu tiga titik; badge “Live” perlu merepresentasikan status channel realtime, bukan hanya koneksi browser; audit ulang agregasi omzet vs rentang tanggal |
| Fulfillment | Sudah | Jalur internal delivery, pickup, ekspedisi, tracking/serah-terima tersedia | Tampilkan next action langsung di row/card agar pedagang tidak perlu membuka menu untuk aksi berulang |
| Produk/katalog | Sudah | CRUD produk, kategori, gambar, varian, topping, bundle, galeri, pre-order, grosir/B2B | Mode kartu mobile; helper text gunakan bahasa operasional; konsistensi ikon produk/galeri/bundle perlu diperjelas |
| Stok | Sebagian besar sudah | Daftar stok, low-stock badge, riwayat, export, RPC adjustment atomik | Pastikan pesan sukses hanya muncul setelah RPC + invalidasi query selesai; tambahkan empty state yang membedakan stok kosong vs gagal memuat |
| Promo & pelanggan | Sudah | Promo, flash sale, jadwal promo, voucher, loyalty, ulasan, chat, notifikasi WA, iklan | Sediakan “Aksi cepat” untuk promo, balas ulasan, dan chat; konsistenkan label Indonesia/Inggris seperti `Loyalty Rules`, `Price Book`, `Insight Bisnis` |
| Laporan & keuangan | Sebagian | Analitik, statistik pengunjung, insight, laporan keuangan, pajak, import/export, penarikan, iuran, kuota; error/retry finance sudah ada | Audit ulang semua angka agregat agar server-side dan konsisten dengan periode/filter; ekspor perlu helper CSV bersama dengan escaping RFC 4180 dan feedback gagal |
| Pembayaran | Sebagian | Transfer Bank & QRIS, upload QRIS, copy yang menjelaskan COD belum tersedia | Jika COD belum tersedia, sebaiknya tampilkan disabled control tunggal yang informatif; setelah simpan tampilkan ringkasan metode aktif yang benar-benar tersimpan |
| Pengaturan toko | Sudah | Profil, cover, jam operasional, lokasi, rekening, QRIS, notifikasi, status halal | Hilangkan potensi label ganda; pastikan semua switch punya label semantik dan deskripsi singkat |
| Navigasi | Sebagian besar sudah | Taxonomy baru, search, accordion, mobile drawer, active state, icon label/tooltip pada tombol ikon | Sidebar tetap padat; tambahkan “Aksi cepat” dan pisahkan fitur inti dari fitur lanjutan agar pengguna baru tidak kewalahan |
| POS | Tersedia tetapi disembunyikan dari menu merchant | Banyak route dan permission POS tetap ada; subscription/setup tersedia | `POS_UI_ENABLED = false`; definisikan dengan jelas kapan POS muncul di navigasi agar route tidak terasa hilang |

## Temuan prioritas

### P0 — Kepercayaan terhadap angka

1. **Pastikan semua kartu ringkasan menggunakan sumber data yang sama.** Dashboard sudah memakai summary pending server-side dan halaman order sudah punya `serverSummary`, tetapi chart dashboard masih mengambil hingga 500 order. Beri label periode/scope pada setiap angka.
2. **Jangan menyamakan “belum ada data” dengan “data gagal dimuat”.** Finance sudah memiliki error state; pola yang sama perlu diaudit pada analytics, visitor stats, insight, pajak, dues, withdrawal, dan import/export.
3. **Satukan helper export CSV.** Semua kolom teks harus di-escape untuk koma, tanda kutip, dan baris baru; tampilkan toast sukses/gagal.

### P1 — Kecepatan kerja pesanan

1. Tampilkan satu CTA utama di row/card berdasarkan status: **Terima**, **Verifikasi**, **Proses**, **Kirim**, **Siap diambil**, atau **Selesaikan**.
2. Menu tiga titik tetap dipakai untuk aksi sekunder: cetak, chat, lihat detail, batalkan.
3. Ganti indikator realtime menjadi tiga state: **Live**, **Menghubungkan ulang**, **Offline**. Tooltip menjelaskan bahwa Live berarti channel realtime aktif.
4. Pada mobile, gunakan kartu order dengan urutan: ID/waktu, pelanggan, total, status, CTA utama, lalu aksi sekunder.

### P1 — Struktur navigasi

Tambahkan blok **Aksi cepat** di atas group, berisi maksimal lima item:

- Pesanan baru
- Tambah produk
- Stok menipis
- Buat promo
- Laporan keuangan

Group lanjutan seperti pajak, iuran, iklan, import/export, dan kuota dapat tetap tersedia tetapi tidak mendominasi navigasi utama.

## Arah ikon yang direkomendasikan

Proyek sudah menggunakan `lucide-react`, sehingga tidak perlu menambah library ikon lain. Pertahankan aturan berikut:

- **Satu gaya:** Lucide outline, ukuran `16px` untuk item sidebar, `18–20px` untuk heading/kartu, `14px` untuk aksi sekunder.
- **Satu makna satu ikon:** jangan memakai `Package` sekaligus untuk Katalog, Bundle, dan group Produk & Stok.
- **Warna hanya untuk status:** ikon navigasi default muted; aktif menggunakan `sidebar-primary`; merah/amber hanya untuk badge/peringatan.
- **Ikon saja wajib punya** `aria-label` dan `title`; teks + ikon tidak perlu tooltip tambahan.
- **Jangan memakai emoji sebagai ikon UI utama.** Emoji boleh hanya di copy notifikasi yang memang ditujukan untuk WhatsApp.

### Mapping ikon yang lebih jelas

| Area | Ikon saat ini/yang disarankan | Catatan |
|---|---|---|
| Dashboard | `LayoutDashboard` | Sudah tepat |
| Pesanan | `ReceiptText` atau `ClipboardList` | Lebih jelas sebagai daftar order daripada `Receipt` generik |
| Fulfillment | `Truck` | Sudah tepat |
| Refund | `RotateCcw` | Sudah tepat |
| Chat | `MessageCircle` | Sudah tepat |
| Katalog Produk | `PackageSearch` | Bedakan dari group stok |
| Manajemen Stok | `Boxes` | Lebih representatif daripada `Layers` |
| Bundle Produk | `Layers3` | Bedakan dari stok |
| Galeri Toko | `Images` | Sudah tepat |
| Promo | `BadgePercent` | Lebih komunikatif daripada `Percent` |
| Flash Sale | `Zap` | Sudah tepat |
| Voucher | `TicketPercent` | Bedakan dari group Promosi |
| Ulasan | `Star` | Sudah tepat |
| Analitik | `ChartNoAxesCombined` atau `BarChart3` | Pilih satu dan konsisten |
| Statistik Pengunjung | `Footprints` atau `Eye` | `Eye` sudah cukup jika ingin minim perubahan |
| Laporan Keuangan | `ChartCandlestick` atau `TrendingUp` | Gunakan `TrendingUp` jika tidak ingin konteks saham |
| Penarikan | `WalletCards` | Lebih spesifik daripada `Wallet` |
| Pengaturan Toko | `StoreCog` | Lebih spesifik daripada `Settings` |
| Aksi kembali | `ArrowLeft` | Lebih umum daripada `ChevronLeft` untuk navigasi keluar |

> Rekomendasi utama: lakukan penggantian ikon secara bertahap pada **sidebar** terlebih dahulu. Jangan mengubah ikon di seluruh halaman sekaligus karena dapat membuat visual tidak konsisten selama migrasi.

## Definition of Done untuk fase berikutnya

- [ ] Semua ringkasan angka memiliki label periode/scope dan tidak bergantung pada jumlah row yang kebetulan sudah ter-load.
- [ ] CTA utama order terlihat langsung di desktop dan mobile.
- [ ] Tabel order/product memiliki mode kartu pada breakpoint mobile.
- [ ] Status realtime memiliki state channel yang sebenarnya.
- [ ] Semua halaman laporan membedakan loading, empty, error, dan data valid.
- [ ] Export CSV memakai satu helper escaping dan memiliki toast sukses/gagal.
- [ ] Sidebar memiliki Aksi cepat maksimal lima item.
- [ ] Ikon sidebar memakai satu set Lucide, tidak ada duplikasi makna, dan seluruh ikon-only control berlabel.

## Kesimpulan

**Fitur pedagang yang paling kritis sudah tersedia dan beberapa masalah audit lama sudah ditangani.** Fokus berikutnya sebaiknya bukan menambah banyak menu baru, melainkan memperpendek jalur kerja pedagang: angka harus dapat dipercaya, order harus bisa ditindaklanjuti sekali klik, mobile harus nyaman, dan ikon harus memberi orientasi yang cepat tanpa menambah dekorasi berlebihan.
