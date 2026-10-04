# Rancangan UI/UX Laporan & Analitik Penjualan Merchant

**Tanggal:** 4 Oktober 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Status:** rancangan produk dan UI/UX, belum implementasi kode

## 1. Tujuan desain

Halaman laporan dan analitik harus membantu merchant menjawab tiga pertanyaan dengan cepat:

1. **Bagaimana performa toko saya sekarang?**
2. **Apa penyebab perubahan penjualan?**
3. **Tindakan apa yang harus saya lakukan berikutnya?**

Saat ini informasi tersebar di beberapa halaman:

- `/merchant/analytics` — KPI global, grafik penjualan, performa produk;
- `/merchant/insight` — tren, jam ramai, pelanggan, kategori, produk terbaik/terlemah;
- `/merchant/finance` — omzet, biaya platform, pendapatan bersih, laporan bulanan;
- statistik pengunjung — views toko/produk dan pengunjung unik;
- `/merchant/pajak` — estimasi PPN/PPh dan ekspor PDF.

Rancangan ini menyatukan pengalaman navigasinya, tetapi tetap memisahkan konteks **operasional**, **insight**, dan **keuangan resmi** agar angka tidak tercampur.

## 2. Prinsip pengalaman

### Satu konteks periode

Semua kartu dan grafik pada satu tampilan harus mengikuti periode yang sama. Gunakan date range global:

```text
[7 hari terakhir] [30 hari] [90 hari] [Bulan ini] [Bulan lalu] [Pilih tanggal]
```

Jangan menampilkan KPI 7 hari berdampingan dengan laporan 12 bulan tanpa label yang sangat jelas.

### Satu definisi metrik

- **Omzet kotor:** nilai penjualan dari order selesai, sebelum biaya platform.
- **Pendapatan bersih:** omzet kotor dikurangi biaya platform yang benar-benar tercatat.
- **Pesanan selesai:** hanya status `DONE`/`DELIVERED` sesuai aturan bisnis.
- **AOV:** omzet kotor dibagi jumlah pesanan selesai.
- **Konversi produk:** order count dibagi views produk; labeli sebagai estimasi bila sumbernya adalah counter produk, bukan funnel order unik.
- **Pengunjung unik:** berdasarkan `viewer_id`; jelaskan bahwa pengunjung anonim mungkin tidak terhitung.

Setiap metrik keuangan penting memiliki tooltip definisi dan sumber data.

### Berorientasi keputusan

Setiap grafik harus menjawab pertanyaan, bukan hanya menampilkan data. Contoh:

- bukan hanya `Tren Penjualan`, tetapi `Omzet naik 18% dibanding periode sebelumnya`;
- bukan hanya `Produk Terlaris`, tetapi `Produk terlaris menyumbang 42% omzet`;
- bukan hanya `Jam Ramai`, tetapi `Siapkan stok tambahan pada 18.00–20.00`.

## 3. Arsitektur informasi yang direkomendasikan

Di sidebar, kelompok `Laporan & Keuangan` disederhanakan menjadi:

```text
Laporan & Analitik
├── Ringkasan penjualan      /merchant/analytics
├── Insight bisnis           /merchant/insight
├── Laporan keuangan        /merchant/finance
├── Pengunjung & konversi   /merchant/visitor-stats
└── Pajak                   /merchant/pajak
```

Label utama yang disarankan:

- **Ringkasan penjualan**, bukan hanya `Analitik`, agar tujuan halaman jelas;
- **Insight bisnis** untuk penjelasan tren dan rekomendasi;
- **Laporan keuangan** untuk omzet, fee, dan bersih;
- **Pengunjung & konversi** untuk traffic-to-order;
- **Pajak** tetap terpisah karena memiliki konteks kepatuhan dan disclaimer.

Pada mobile bottom navigation, jangan menambah tab baru. Akses laporan melalui `Menu` atau shortcut `Analitik` dari Beranda.

## 4. Halaman utama: Ringkasan Penjualan

### Header

```text
Ringkasan Penjualan
Pantau performa toko dan temukan peluang perbaikan

[30 hari terakhir ▼] [Bandingkan periode sebelumnya ✓] [Export ▼] [Refresh]
Terakhir diperbarui 4 Okt 2026, 22.30
```

`Export` membuka pilihan format dan cakupan:

- CSV ringkasan;
- CSV detail transaksi;
- PDF ringkasan.

### KPI hero

Gunakan empat KPI yang paling berguna untuk keputusan harian:

```text
Omzet kotor              Pesanan selesai
Rp 12.450.000            86 pesanan
↑ 18,4%                  ↑ 12,7%

Pendapatan bersih        Nilai rata-rata order
Rp 12.076.500            Rp 144.767
↑ 16,8%                  ↑ 5,1%
```

Aturan visual:

- angka utama besar dan mudah dipindai;
- delta dibanding periode sebelumnya selalu memiliki label periode;
- gunakan hijau hanya untuk perubahan positif yang memang baik;
- perubahan negatif ditampilkan merah, tetapi copy tidak menyalahkan merchant;
- jika periode sebelumnya nol, tampilkan `Belum ada pembanding` alih-alih `0%`.

### Insight banner

Di bawah KPI, tampilkan satu atau dua insight paling relevan:

```text
Peluang utama
Omzet paling tinggi terjadi Jumat pukul 18.00–20.00.
Pertimbangkan menambah stok produk terlaris sebelum jam tersebut.
[Lihat jam ramai]
```

Jika tidak ada cukup data:

```text
Kumpulkan lebih banyak data
Insight jam ramai akan muncul setelah ada minimal 7 hari transaksi.
```

### Grafik utama

Card `Tren omzet dan pesanan` dengan:

- area/line omzet;
- bar tipis jumlah pesanan sebagai metrik sekunder;
- toggle `Omzet | Pesanan | Keduanya`;
- tooltip berisi tanggal, omzet, pesanan, dan AOV;
- state no-data per periode;
- opsi granularitas otomatis: harian untuk ≤90 hari, mingguan untuk periode lebih panjang.

Jangan menumpuk dua chart besar untuk data yang sama seperti halaman sekarang. Satu grafik utama cukup; chart detail berada di tab/section lanjutan.

### Dua kolom keputusan

```text
Produk terlaris                         Produk yang perlu perhatian
1. Sambal ...   Rp 3,2 jt               Keripik ...   1,2% konversi
2. Kopi ...     Rp 2,8 jt               Anyaman ...   stok 2
3. Keripik ...  Rp 1,9 jt               Kopi ...      views tinggi, order rendah
[Lihat semua produk]                    [Buka katalog]
```

Produk “perlu perhatian” sebaiknya menggabungkan sinyal:

- banyak views tetapi order rendah;
- order tinggi tetapi stok menipis;
- aktif tetapi tidak ada views;
- penjualan turun dibanding periode sebelumnya.

### Funnel ringkas

```text
Dilihat       Ditambahkan / dipesan       Selesai
4.820         286                         214
               5,9%                        74,8%
```

Gunakan copy `estimasi` jika metrik berasal dari counter produk dan order global yang tidak memiliki join funnel langsung.

## 5. Tab Insight Bisnis

Halaman Insight tidak perlu mengulang KPI hero dan grafik utama. Fokus pada alasan dan peluang.

### Layout desktop

```text
[Periode global] [Bandingkan] [Refresh]

[Jam ramai] [Hari terbaik] [Repeat buyer] [Produk aktif]

Tren omzet mingguan          Jam ramai
Grafik area                   Heatmap hari × jam

Kategori penyumbang omzet     Produk terlaris vs perhatian
Donut/bar horizontal          Tabel ranking dengan insight

Pelanggan baru vs repeat      Rekomendasi tindakan
```

### Heatmap jam ramai

Heatmap lebih mudah dipindai daripada bar 24 jam yang panjang:

- sumbu X: Sen–Min;
- sumbu Y: 06.00–22.00;
- warna lebih pekat berarti lebih banyak order;
- tooltip: jumlah order, omzet, dan AOV.

Untuk mobile, ubah menjadi dropdown `Pilih hari` + bar jam agar tidak terlalu padat.

### Produk

Ganti tabel sederhana menjadi dua mode:

- **Peluang omzet:** ranking berdasarkan omzet/order;
- **Peluang konversi:** views tinggi dengan order rendah.

Kolom yang disarankan:

| Produk | Dilihat | Pesanan | Konversi | Omzet | Stok | Aksi |
|---|---:|---:|---:|---:|---:|---|
| Nama + thumbnail | 1.240 | 84 | 6,8% | Rp... | Aman | Lihat produk |

Gunakan badge:

- `Terlaris`;
- `Konversi tinggi`;
- `Perlu foto/deskripsi`;
- `Stok kritis`.

## 6. Tab Laporan Keuangan

Pertahankan konteks finansial yang sudah ada, tetapi tingkatkan hierarki dan transparansi.

### Header

```text
Laporan Keuangan
Rekap omzet, biaya platform, dan pendapatan bersih

[Periode] [Export CSV] [Export PDF]
```

### KPI

```text
Omzet kotor       Biaya platform       Pendapatan bersih       Pesanan selesai
Rp ...            -Rp ...               Rp ...                  ...
```

Jika tarif platform tidak selalu 3%, jangan menulis `3%` secara global. Tampilkan tarif yang benar-benar terhitung dari data atau label `Biaya tercatat`.

### Waterfall sederhana

```text
Omzet kotor
− Biaya platform
− Diskon/voucher yang ditanggung merchant
= Pendapatan bersih
```

Beri tooltip untuk menjelaskan apakah shipping, voucher, dan fee termasuk dalam perhitungan. Ini penting karena implementasi saat ini menggunakan `subtotal` untuk omzet bulanan tetapi halaman lain menggunakan `total`.

### Tabel bulanan

Tetap pertahankan tabel rincian per bulan, tetapi tambahkan:

- sticky header pada mobile horizontal scroll;
- kolom `AOV`;
- badge `Bulan ini`;
- tombol buka detail transaksi pada desktop;
- total footer yang jelas.

## 7. Tab Pengunjung & Konversi

Satukan statistik visitor dengan konteks penjualan, bukan hanya total views.

### KPI

```text
Views toko       Views produk      Pengunjung unik       Konversi estimasi
4.820            3.960             2.740                5,9%
```

### Grafik

- line views toko vs produk;
- funnel views → order → selesai;
- top viewed products;
- tabel `views tinggi, order rendah`.

Tambahkan disclaimer ringkas:

> Pengunjung unik dihitung dari viewer yang dapat dikenali. Data anonim dapat menyebabkan angka lebih rendah dari jumlah pengunjung sebenarnya.

## 8. Filter dan interaksi

### Filter global

Filter harus berada di satu toolbar konsisten dan sticky pada desktop:

```text
[30 hari terakhir ▼] [Bandingkan periode ✓] [Semua produk ▼] [Semua kategori ▼]
```

Filter produk/kategori hanya ditampilkan pada section yang mendukungnya agar toolbar tidak terlalu penuh.

### Perbandingan periode

Default aktif untuk periode yang mendukung perbandingan. Copy yang digunakan:

- `↑ 18,4% vs 30 hari sebelumnya`;
- `↓ 7,2% vs bulan lalu`;
- `Belum ada pembanding`;
- `Data belum cukup`.

### Export

Jangan membuat tombol export terpisah di setiap card. Gunakan satu menu export di header dengan pilihan:

```text
Export ringkasan
Export detail transaksi
Export data produk
Jadwalkan laporan ke WhatsApp/email
```

## 9. Responsif mobile

### Aturan layout

- KPI menjadi 2 kolom dengan angka minimum 20px;
- toolbar periode dapat horizontal scroll, tidak wrap menjadi empat baris;
- chart tinggi 240–280px;
- tabel diubah menjadi ranking card atau horizontal scroll dengan kolom pertama sticky;
- insight banner selalu full width;
- tombol export dan refresh tetap mudah dijangkau, tetapi tidak mendominasi header;
- tab menggunakan horizontal scroll dengan label singkat: `Ringkasan`, `Insight`, `Keuangan`, `Pengunjung`.

### Mobile wireframe

```text
Ringkasan Penjualan
[30 hari ▼] [Export]
Terakhir diperbarui ...

[Omzet]              [Pesanan]
[ Bersih ]           [AOV ]

Insight utama
Omzet naik ...

Tren penjualan
[Omzet | Order]
           chart

Produk terlaris
1. ...  Rp ...
2. ...  Rp ...
[Lihat semua]

Perlu perhatian
[Stok] [Konversi]
```

## 10. Visual direction

### Hierarki warna

- Primary/emerald: omzet dan performa positif;
- blue: volume pesanan;
- violet: pelanggan/retensi;
- amber: peluang/peringatan;
- red: biaya, pembatalan, atau stok habis;
- muted background: area filter dan metadata.

Hindari setiap card memiliki warna kuat berbeda. Warna digunakan untuk makna, bukan dekorasi.

### Komponen

- gunakan card utama dengan padding 16–20px;
- radius konsisten dengan token aplikasi;
- gunakan icon hanya sebagai penanda, bukan pengganti label;
- chart memiliki grid tipis, tooltip dengan format Rupiah, dan legend maksimal 2–3 series;
- angka besar harus memiliki label periode atau definisi di bawahnya;
- semua chart memiliki tabel/ringkasan alternatif untuk aksesibilitas.

## 11. State wajib

### Loading

Gunakan skeleton yang mengikuti bentuk akhir:

- skeleton empat KPI;
- skeleton grafik dengan axis placeholder;
- skeleton tabel tiga baris.

### Empty

```text
Belum ada penjualan pada periode ini
Pilih periode yang lebih panjang atau mulai bagikan katalog Anda.
[Lihat katalog]
```

### Insufficient data

Bedakan dari zero:

```text
Belum cukup data untuk insight
Minimal diperlukan 7 hari transaksi untuk membaca pola jam ramai.
```

### Error

Error harus per-card bila memungkinkan, bukan membuat seluruh halaman kosong:

```text
Tren penjualan gagal dimuat
Data KPI masih tersedia.
[Coba lagi]
```

### Stale data

Tampilkan `Terakhir diperbarui` dan tombol refresh. Jangan menyebut semua data realtime jika sumbernya berbeda-beda.

## 12. Rekomendasi implementasi bertahap

### Tahap 1 — Fondasi navigasi dan definisi

- Satukan toolbar periode dan compare mode.
- Selaraskan definisi omzet, order selesai, AOV, dan net revenue.
- Tambahkan `lastUpdatedAt`.
- Pisahkan KPI global dari KPI keuangan.

### Tahap 2 — Redesign Ringkasan Penjualan

- KPI hero;
- insight banner;
- satu chart gabungan omzet/order;
- ranking produk terlaris dan perlu perhatian;
- empty/loading/error states.

### Tahap 3 — Redesign Insight

- heatmap jam ramai;
- kategori penyumbang omzet;
- customer repeat/new;
- product opportunity table.

### Tahap 4 — Redesign Keuangan dan export

- waterfall omzet → fee → bersih;
- detail biaya;
- export menu terpusat;
- PDF/CSV dengan nama file dan periode konsisten.

### Tahap 5 — Optimasi data

- pindahkan agregasi besar ke RPC/server-side;
- hindari mengambil semua order 12 bulan ke browser;
- cache query berdasarkan merchant + periode;
- gunakan count/agregasi server-side untuk dashboard besar.

## 13. Acceptance criteria

- Merchant dapat memahami omzet, pesanan, bersih, dan AOV dalam kurang dari 5 detik.
- Semua KPI yang terlihat mengikuti periode yang sama.
- Perbandingan selalu menyebut periode pembanding secara eksplisit.
- Laporan keuangan tidak mencampur definisi `total` dan `subtotal` tanpa penjelasan.
- Chart utama tidak duplikatif dan memiliki insight/action pendamping.
- Mobile tidak membutuhkan zoom atau horizontal scroll untuk KPI utama.
- Empty, insufficient data, loading, error, dan stale state memiliki tampilan berbeda.
- Export dapat dilakukan dari satu lokasi dengan pilihan cakupan yang jelas.
- Data besar tidak seluruhnya diambil ke browser untuk sekadar menghitung agregat.
