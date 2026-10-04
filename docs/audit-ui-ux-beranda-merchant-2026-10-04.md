# Audit UI/UX Halaman Beranda Merchant

**Tanggal audit:** 4 Oktober 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Cakupan:** hierarki informasi, prioritas tindakan, kepadatan dashboard, konsistensi metrik, state data, responsif mobile, aksesibilitas, dan rekomendasi implementasi.

## Ringkasan

Halaman Beranda merchant sudah memiliki fondasi yang kuat: status toko, pesanan yang menunggu, statistik server-side, grafik 14 hari, stok menipis, ulasan, kuota, kas kelompok, dan jam operasional. Masalah utamanya bukan kekurangan informasi, melainkan **terlalu banyak informasi penting yang tampil bersamaan**.

Saat ini Beranda lebih terasa sebagai kumpulan laporan daripada ruang kerja operasional. Untuk merchant, urutan ideal seharusnya:

1. Apa yang harus saya kerjakan sekarang?
2. Apakah toko sedang siap menerima pesanan?
3. Bagaimana performa hari ini?
4. Apa yang perlu saya optimalkan setelah pekerjaan utama selesai?

## Struktur Beranda saat ini

Urutan komponen yang dianalisis:

1. Hero greeting + shortcut ke pesanan.
2. Status buka/tutup toko + lihat toko + QR toko.
3. Alert kuota jika kritis.
4. Tiga kartu: kuota, kelompok dagang, iuran kas.
5. Ringkasan hari ini.
6. Enam kartu statistik status pesanan.
7. Tab Overview, Pesanan, Stok, Lainnya.
8. Pada Overview: pesanan menunggu, grafik pendapatan/pesanan, stok menipis, ulasan.
9. Pada Lainnya: jam operasional dan shortcut fitur.

## Temuan prioritas

### P0 — Tindakan utama terlalu jauh dari awal halaman

Hero memiliki CTA `Tinjau X pesanan`, tetapi panel detail pesanan menunggu baru muncul setelah beberapa blok informasi lain dan tab Overview. Merchant yang membuka Beranda untuk menangani order harus menggulir cukup jauh.

**Rekomendasi:** pindahkan panel **Perlu tindakan sekarang** tepat setelah header/hero dan status toko. Jika ada pesanan menunggu, panel ini menjadi elemen paling dominan di viewport pertama.

### P0 — Metrik berulang dan berpotensi membingungkan

`DailySummaryCard` menampilkan pendapatan hari ini, jumlah pesanan, dan pesanan menunggu. `QuickStats` kembali menampilkan pesanan hari ini, menunggu proses, selesai, batal, dan pendapatan hari ini. Pengulangan ini menghabiskan ruang dan membuat merchant harus membandingkan dua kelompok angka.

**Rekomendasi:**

- Jadikan satu blok **Ringkasan hari ini** sebagai sumber metrik utama.
- Gunakan maksimal 4 KPI di viewport utama: pesanan perlu tindakan, pesanan hari ini, pendapatan selesai hari ini, dan stok menipis.
- Pindahkan breakdown `diproses`, `selesai`, dan `batal` ke tab/detail `Pesanan` atau grafik.
- Hindari menampilkan pendapatan hari ini dua kali.

### P1 — Status toko penting, tetapi terlalu bersaing dengan hero

Hero greeting dan kartu status toko sama-sama besar. Status buka/tutup adalah kontrol operasional utama, tetapi saat ini posisinya sejajar dengan greeting sehingga fokus visual terbagi.

**Rekomendasi:** jadikan status toko sebagai compact control di header dashboard atau card kecil yang jelas:

- status dot + `Buka` / `Tutup`;
- switch;
- jam operasional hari ini;
- CTA `Lihat toko` sebagai aksi sekunder.

QR toko tetap tersedia, tetapi tidak perlu mengambil bobot visual setara dengan status buka/tutup.

### P1 — Informasi kuota muncul dua kali

`QuotaAlertBanner` muncul sebagai banner ketika kuota kritis/peringatan, lalu `QuotaStatusCard` tetap muncul di grid status. Pada kondisi kritis, merchant menerima dua pesan dengan CTA upgrade yang sangat mirip.

**Rekomendasi:**

- Jika kuota kritis, banner menjadi satu-satunya alert utama dan kartu kuota berubah menjadi ringkasan kecil tanpa CTA kedua.
- Jika kuota normal, tampilkan kartu kuota dalam bagian `Bisnis & akun`, bukan di atas metrik operasional.
- Copy harus menyebut dampak langsung dan satu CTA utama.

### P1 — Klaim realtime belum konsisten

Hero menyatakan “Data diperbarui otomatis”, tetapi tidak semua card diperbarui dengan mekanisme yang sama. `QuickStats` memiliki subscription realtime, sementara ringkasan harian, stok, ulasan, kuota, dan iuran memiliki pola refresh berbeda atau hanya fetch awal.

**Rekomendasi:**

- Ganti copy global menjadi `Terakhir diperbarui [waktu]`.
- Tampilkan status realtime hanya pada blok pesanan yang memang berlangganan channel.
- Tambahkan tombol refresh kecil untuk card non-realtime atau invalidasi query terpusat.
- Jangan menjanjikan seluruh dashboard realtime bila hanya sebagian data yang live.

### P1 — Stok menipis belum cukup actionable

`StockAlerts` menampilkan tombol `Kelola stok` pada setiap baris yang semuanya menuju route sama. Jika banyak produk menipis, pengulangan CTA membuat card panjang tanpa memberi prioritas produk paling kritis.

**Rekomendasi:**

- Urutkan produk berdasarkan rasio stok terhadap minimum atau produk yang stoknya 0 terlebih dahulu.
- Tampilkan status singkat: `Habis`, `Kritis`, atau `Menipis`.
- Gunakan satu CTA card: `Kelola stok`, lalu jadikan row dapat diklik.
- Batasi preview 3–5 produk dan tambahkan `Lihat semua (X)`.

### P1 — Ulasan terlalu berat untuk dashboard

`CustomerReviews` memuat daftar ulasan lengkap, filter, form balasan, avatar, dan gambar. Ini baik untuk halaman khusus ulasan, tetapi terlalu berat jika diletakkan di Beranda bersama grafik dan stok.

**Rekomendasi:** di Beranda tampilkan preview ringkas:

- rating rata-rata;
- jumlah ulasan belum dibalas;
- 1–2 ulasan terbaru;
- CTA `Balas ulasan`.

Pindahkan daftar lengkap dan lightbox ke halaman `Ulasan`.

### P2 — Tab di Beranda menyembunyikan fungsi penting

Tab `Overview`, `Pesanan`, `Stok`, dan `Lainnya` memang mengurangi panjang halaman, tetapi juga membuat fitur penting tidak terlihat sampai merchant memahami adanya tab. `Stok` dan `Pesanan` pada tab juga berpotensi menduplikasi menu utama.

**Rekomendasi:**

- Pertahankan satu Overview yang fokus pada tindakan dan KPI.
- Hapus tab `Pesanan`/`Stok` dari Beranda jika sudah ada navigasi global yang jelas, atau ubah menjadi shortcut card.
- Gunakan `Lainnya` hanya untuk pengaturan operasional ringan, bukan sebagai tempat menyembunyikan fitur utama.

### P2 — Export terlalu menonjol di ringkasan harian

Tombol Export berada di header `Ringkasan Hari Ini`, padahal kebutuhan utama saat membuka Beranda adalah membaca dan menindaklanjuti data, bukan export.

**Rekomendasi:** pindahkan export ke halaman Laporan Keuangan atau menu overflow pada card.

## Rekomendasi struktur Beranda baru

### Viewport pertama

```text
Header: Beranda + notifikasi + status koneksi pesanan

[Perlu tindakan sekarang]
- 3 pesanan baru       [Tinjau pesanan]
- 2 stok kritis        [Kelola stok]
- 4 ulasan belum dibalas [Balas ulasan]

[Status toko]
- Toko sedang buka • sampai 21.00
- Switch buka/tutup   [Lihat toko]

[KPI hari ini]
- Pesanan hari ini
- Pendapatan selesai
- Pesanan selesai
- Stok menipis
```

### Setelah viewport pertama

```text
Performa 14 hari       | Ringkasan pesanan
Preview stok kritis    | Preview ulasan terbaru
Bisnis & akun: kuota, iuran kas, kelompok dagang
Jam operasional dan shortcut lanjutan
```

## Rekomendasi visual

- Gunakan satu card dominan untuk `Perlu tindakan sekarang` dengan border warning hanya saat ada pekerjaan.
- Saat tidak ada pekerjaan, tampilkan empty state positif yang ringkas: `Semua pekerjaan utama selesai`.
- Kurangi gradient besar pada hero agar CTA operasional lebih menonjol.
- Gunakan satu skala radius dan padding yang konsisten; card dashboard saat ini mencampur beberapa kepadatan.
- Pada mobile, KPI memakai horizontal scroll atau grid 2 kolom dengan angka besar, bukan enam card panjang berturut-turut.
- Pastikan CTA utama minimal 44px tinggi dan dapat dijangkau tanpa presisi tinggi.
- Gunakan label yang konsisten: `Pendapatan selesai` lebih jelas daripada `Pendapatan hari ini` bila hanya order `DONE` yang dihitung.

## Rekomendasi teknis pendukung UX

1. Buat satu hook ringkasan merchant yang mengembalikan KPI utama agar `DailySummaryCard` dan `QuickStats` tidak menghitung metrik yang sama secara terpisah.
2. Tambahkan `lastUpdatedAt` per sumber data, bukan klaim global `Data diperbarui otomatis`.
3. Pastikan metrik uang memakai definisi yang sama: `subtotal` atau `total` harus konsisten dan diberi label.
4. Gunakan server-side summary/RPC untuk chart dan KPI yang berpotensi melewati row cap.
5. Batasi jumlah review/stok yang di-render di Beranda agar performa mobile tetap ringan.
6. Tambahkan test untuk kondisi: ada order baru, tidak ada order, kuota kritis, stok habis, dan error pada salah satu card.

## Prioritas implementasi

| Prioritas | Perubahan | Dampak |
|---|---|---|
| P0 | Pindahkan panel Perlu tindakan ke viewport pertama | Mempercepat respons order |
| P0 | Gabungkan metrik Daily Summary + QuickStats | Mengurangi kebingungan dan scroll |
| P1 | Ringkas preview stok dan ulasan | Mengurangi beban dashboard |
| P1 | Satukan perilaku alert kuota | Menghindari pesan/CTA ganda |
| P1 | Perbaiki klaim realtime menjadi last updated | Meningkatkan kepercayaan data |
| P2 | Sederhanakan tab Beranda | Mengurangi duplikasi navigasi |
| P2 | Pindahkan export dari Beranda | Fokus ke pekerjaan harian |

## Definition of Done

- Merchant melihat pekerjaan paling penting tanpa scroll pada layar 360px.
- Tidak ada pendapatan/pesanan yang ditampilkan dua kali tanpa konteks berbeda.
- CTA utama setiap alert dapat dikenali dalam kurang dari 3 detik.
- Empty, loading, dan error state konsisten di semua card.
- Copy realtime mencerminkan sumber data sebenarnya.
- Beranda tetap nyaman dipakai dengan satu tangan pada mobile.
