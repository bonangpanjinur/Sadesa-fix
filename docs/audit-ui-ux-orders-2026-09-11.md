# Audit UI/UX Halaman Pesanan Merchant

**Tanggal:** 11 September 2026  
**Ruang lingkup:** Halaman `MerchantOrdersPage`, komponen `DataTable`, dan tampilan pada screenshot yang diberikan.

## Kesimpulan

Halaman pesanan memang terlalu boros secara vertikal dan terlalu berat secara visual untuk tugas operasional yang berulang. Masalah utamanya bukan satu komponen, melainkan penumpukan beberapa lapisan: empat kartu statistik, baris status realtime, panel filter tanggal, toolbar pencarian, dua filter dropdown, tombol ekspor, lalu tabel dengan padding besar. Akibatnya, area kerja utama—daftar pesanan—terdorong terlalu jauh ke bawah dan hanya menampilkan sedikit baris pada viewport laptop.

Rekomendasi utama adalah mengubah halaman menjadi **task-first order workspace**. Ringkasan statistik harus dipadatkan menjadi satu baris metrik kecil, filter tanggal harus menjadi kontrol ringkas yang dapat dibuka saat diperlukan, dan toolbar pencarian/filter harus digabung dalam satu baris. Tabel perlu menggunakan tinggi baris yang lebih rapat tanpa mengurangi keterbacaan.

## Temuan pada screenshot

| ID | Temuan | Dampak | Prioritas |
|---|---|---|---|
| UX-01 | Area filter tanggal tampil sebagai kartu besar dengan judul, deskripsi, dua field tanggal, dan ruang kosong horizontal. | Filter yang jarang digunakan mengambil tinggi layar utama dan memisahkan pengguna dari tabel. | P0 |
| UX-02 | Empat kartu statistik berada di atas tabel, tetapi pada screenshot hanya bagian bawahnya yang terlihat. | Statistik mengonsumsi ruang tanpa memberi konteks operasional yang proporsional. | P1 |
| UX-03 | Status `Live` dan tombol refresh berada pada baris terpisah dari toolbar tabel. | Kontrol data tersebar dan meningkatkan beban pencarian visual. | P1 |
| UX-04 | Toolbar berisi search, dua dropdown dengan label `Semua...`, dan ekspor dengan lebar besar. | Kontrol tampak generik dan tidak menjelaskan filter yang sedang dipilih. | P1 |
| UX-05 | Tabel menggunakan banyak padding horizontal serta tinggi baris yang besar. | Hanya tiga baris terlihat; scanning pesanan menjadi lambat. | P0 |
| UX-06 | Kolom ID, pelanggan, total, pembayaran, pengiriman, status, tanggal, dan dua aksi ditampilkan sekaligus. | Semua informasi memiliki bobot visual hampir sama, padahal status dan aksi lebih penting daripada metadata sekunder. | P1 |
| UX-07 | Status, metode pembayaran, dan metode pengiriman ditampilkan sebagai pill terpisah. | Tampilan menjadi penuh ornamen; status utama tidak cukup dominan. | P2 |

## Temuan pada implementasi

### 1. Penumpukan vertikal berasal dari struktur halaman

`MerchantOrdersPage.tsx` merender empat kartu statistik dalam grid dengan `gap-4` dan `mb-6`. Setelah itu, halaman merender baris jumlah pesanan dan koneksi realtime dengan `mb-4`. Panel filter tanggal berikutnya menggunakan `mb-4`, padding `p-3 sm:p-4`, judul, deskripsi, serta dua field tanggal.

Secara praktis, sebelum tabel dimulai halaman sudah memiliki tiga blok konteks berturut-turut. Struktur ini cocok untuk dashboard analitik, tetapi kurang cocok untuk halaman operasi pesanan yang membutuhkan daftar padat dan tindakan cepat.

### 2. Filter tanggal terlalu dominan

Panel tanggal saat ini selalu terbuka. Kontrol tersebut menggunakan label terpisah, ikon kalender, dua input tanggal, serta teks penjelasan. Filter tanggal sebaiknya tetap tersedia, tetapi tidak selalu mengambil ruang. Pola yang lebih efisien adalah satu tombol `Tanggal` dengan ringkasan rentang aktif dan popover/drawer ketika dibuka.

### 3. DataTable menambah kepadatan toolbar

`DataTable.tsx` merender search, seluruh filter, reset, dan ekspor secara bersamaan dalam satu toolbar. Pada lebar desktop, dua filter masing-masing memiliki lebar tetap `w-[140px]`, sementara tombol ekspor memakai label penuh. Pada lebar menengah, toolbar berpotensi pecah ke baris berikutnya dan menambah tinggi layout.

Selain itu, tabel memakai header `px-4 py-3` dan sel `px-4 py-3.5`. Untuk tabel operasional, nilai tersebut dapat dirapatkan menjadi header `px-3 py-2` dan sel `px-3 py-2.5`, dengan tetap mempertahankan target klik minimum pada kolom aksi.

### 4. Hierarki kolom belum optimal

Kolom utama seharusnya adalah pelanggan, total, status, dan tanggal. ID pesanan dapat dibuat sebagai teks sekunder yang lebih kecil. Nomor telepon tidak perlu mengambil ruang tambahan di tabel karena dapat tetap ditampilkan pada detail pesanan atau tooltip. Pembayaran dan pengiriman dapat digabung menjadi satu kolom `Fulfillment` pada breakpoint desktop yang sempit.

### 5. Nilai filter kurang informatif

Dua trigger yang sama-sama menampilkan `Semua...` membuat pengguna harus membuka dropdown untuk mengetahui filter yang aktif. Trigger harus menampilkan label ringkas, misalnya `Status: Semua` dan `Bayar: Semua`, atau memakai label yang lebih spesifik seperti `Status` dan `Pembayaran`.

## Rekomendasi desain target

### Prioritas P0 — kurangi tinggi layar awal

1. Ubah empat kartu statistik menjadi satu baris metrik ringkas. Gunakan label kecil, angka utama, dan pemisah vertikal tanpa ikon besar atau card background terpisah.
2. Pindahkan filter tanggal ke popover yang dibuka melalui tombol `Tanggal`. Saat aktif, tombol menampilkan rentang, misalnya `1–10 Sep 2026`.
3. Gabungkan jumlah pesanan, status realtime, refresh, dan filter utama dalam header/toolbar yang lebih pendek.
4. Rapatkan padding tabel dan gunakan `leading-tight` pada konten sekunder.

### Prioritas P1 — tingkatkan scanning dan pemahaman

1. Jadikan status pesanan sebagai elemen paling menonjol setelah nama pelanggan.
2. Tampilkan nomor telepon sebagai teks sekunder hanya jika ruang mencukupi; sembunyikan pada breakpoint sempit.
3. Ganti label filter generik menjadi label yang menjelaskan domain.
4. Pertahankan tombol ekspor sebagai ikon dengan tooltip pada lebar sempit dan label penuh pada desktop lebar.
5. Sediakan preset tanggal umum seperti `Hari ini`, `7 hari`, dan `Bulan ini` agar pengguna tidak harus mengisi dua field.

### Prioritas P2 — konsistensi visual

1. Gunakan satu jenis treatment untuk status: warna lembut, teks singkat, dan radius konsisten.
2. Kurangi penggunaan border-radius besar dan background berwarna pada setiap elemen.
3. Gunakan satu aksen hijau untuk status aktif; warna amber hanya untuk status yang membutuhkan perhatian.
4. Pastikan ikon hanya digunakan jika mempercepat pengenalan fungsi, bukan sebagai dekorasi.

## Struktur layout yang disarankan

```text
Judul halaman                         [Live] [Refresh]
Ringkasan: 3 pesanan · 1 baru        [Tanggal] [Ekspor]
[ Cari pesanan... ] [Status] [Pembayaran] [Reset]
────────────────────────────────────────────────────
Tabel pesanan padat
```

Statistik dapat ditampilkan sebagai baris kecil di antara judul dan toolbar:

```text
Baru 0   Diproses 0   Selesai 3   Pendapatan produk Rp118.963
```

Dengan struktur ini, tabel dapat naik sekitar 120–180 piksel pada viewport desktop tanpa menghilangkan fungsi yang sudah ada.

## Acceptance criteria perbaikan

| Area | Kriteria |
|---|---|
| Viewport desktop 1366×768 | Header tabel mulai terlihat tanpa harus menggulir melewati kartu statistik besar. |
| Filter tanggal | Tidak mengambil ruang vertikal saat tidak aktif; rentang aktif tetap terlihat pada tombol. |
| Toolbar | Search, status, pembayaran, refresh, dan ekspor tetap dapat digunakan tanpa toolbar pecah pada lebar ≥1024 px. |
| Tabel | Minimal lima baris pesanan dapat terlihat pada viewport desktop umum, bergantung pada tinggi browser. |
| Keterbacaan | Nama pelanggan, total, status, dan tanggal tetap terbaca dalam satu scanning horizontal. |
| Mobile | Tabel memiliki horizontal scroll yang disengaja atau berubah menjadi kartu ringkas; tidak ada clipping tersembunyi. |
| Aksesibilitas | Semua tombol ikon memiliki `aria-label` atau tooltip; target klik aksi minimal 44×44 px. |
| Responsivitas | Toolbar tidak menghasilkan overflow horizontal pada lebar 320–375 px. |

## Rencana implementasi bertahap

Tahap pertama sebaiknya hanya mengubah layout tanpa menyentuh kontrak data: padatkan statistik, jadikan filter tanggal collapsible, rapatkan DataTable, dan perjelas label filter. Tahap kedua dapat menyederhanakan kolom berdasarkan breakpoint dan menambahkan preset tanggal. Tahap ketiga perlu memverifikasi tampilan pada lebar 320, 375, 768, 1024, dan 1440 piksel serta memastikan interaksi dialog, ekspor, refresh, dan filter tetap berfungsi.

Perubahan sebaiknya diuji dengan screenshot comparison sebelum dan sesudah. Target keberhasilan bukan sekadar tampilan lebih kecil, tetapi **lebih banyak pesanan dapat dipindai dan ditindaklanjuti dalam satu viewport tanpa mengorbankan informasi penting**.

## References

[1]: https://github.com/bonangpanjinur/Sadesa-fix "Repository Sadesa-fix — source implementation audited"
[2]: https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html "Web Content Accessibility Guidelines 2.2 — Target Size Minimum"
[3]: https://www.w3.org/WAI/WCAG22/Understanding/reflow.html "Web Content Accessibility Guidelines 2.2 — Reflow"

**Dokumen ini disusun oleh Manus AI berdasarkan screenshot pengguna dan pemeriksaan source code repository.**
