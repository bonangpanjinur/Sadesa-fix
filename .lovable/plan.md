# Rencana Perapihan Sidebar Merchant & POS

## Tujuan
Membuat sidebar lebih ringkas, mudah dipindai, dan nyaman dipakai untuk operasional harian tanpa menghapus fitur atau mengubah hak akses pengguna.

## Temuan Saat Ini
- Ada 30 menu merchant yang tampil sebagai satu daftar panjang tanpa pengelompokan.
- Area POS menambahkan 42 menu bertingkat, panel tenant/outlet, langganan, badge jumlah, dan beberapa accordion di dalam sidebar yang sama.
- Navigasi utama dan POS memakai gaya visual berbeda; banyak border, kartu bertumpuk, dan jumlah menu membuat lokasi halaman aktif sulit dikenali.
- Tombol kembali berada di bawah, tetapi pada layar pendek berisiko kalah menonjol dari area menu yang panjang.

## Desain yang Dipilih
- **Arah:** Clean grouped sidebar.
- **Palet:** Putih & Emerald — `#FFFFFF`, `#F1F5F3`, `#087F5B`, `#111827` melalui token tema.
- **Tipografi:** Sora untuk judul/label utama dan Manrope untuk isi menu.
- **Struktur:** Sidebar berkelompok dengan hanya kelompok aktif terbuka otomatis.

## Perubahan
1. **Susun ulang menu merchant menjadi kelompok kerja**
   - Ringkasan: Dashboard.
   - Penjualan: Pesanan, fulfillment, refund, chat.
   - Produk & stok: Produk, stok, price book, galeri, bundle, preorder, grosir.
   - Promosi & pelanggan: Promo, flash sale, jadwal promo, voucher, loyalty, ulasan, notifikasi WA, iklan.
   - Analitik & keuangan: Analitik, statistik pengunjung, insight, laporan keuangan, pajak, import/export, penarikan, iuran, kuota.
   - Pengaturan tetap mudah dijangkau di bagian bawah.

2. **Sederhanakan area POS**
   - Jadikan POS satu kelompok utama yang setara dengan kelompok merchant, bukan kartu bertingkat di dalam kartu.
   - Tampilkan informasi tenant/outlet sebagai baris ringkas; pemilih outlet muncul hanya jika memang ada lebih dari satu outlet.
   - Pertahankan kategori POS yang sudah ada dan filter berbasis peran.
   - Hanya kategori POS aktif yang terbuka otomatis; kategori lain tertutup.

3. **Perjelas hierarki dan status aktif**
   - Lebar sidebar stabil sekitar 272–288 px.
   - Gunakan label kelompok kecil, ikon konsisten, jarak baris ringkas namun tetap nyaman diklik, dan indikator emerald di sisi kiri untuk item aktif.
   - Hilangkan border/kartu dekoratif berlapis; gunakan latar lembut hanya untuk grup atau item aktif.
   - Badge pesanan, stok, ulasan, refund, dan jumlah POS tetap ada tetapi dibuat lebih kecil dan konsisten.

4. **Perbaiki perilaku navigasi**
   - Simpan status grup yang dibuka, tetapi selalu buka grup yang berisi halaman aktif.
   - Tutup kelompok lain saat satu kelompok dibuka agar tinggi sidebar terkendali.
   - Pertahankan tampilan drawer di layar kecil dan sediakan tombol tutup yang jelas.
   - Pastikan “Kembali ke Aplikasi” selalu berada di footer yang tetap terlihat.

5. **Terapkan gaya secara konsisten**
   - Tambahkan token sidebar Putih & Emerald serta font Sora/Manrope ke sistem desain yang ada.
   - Gunakan komponen tombol yang sudah tersedia untuk kontrol accordion dan drawer.
   - Pertahankan mode terang/gelap melalui token semantik, tanpa warna mentah di komponen.

6. **Validasi**
   - Uji halaman merchant biasa dan halaman POS untuk status aktif, accordion, badge, pemilih outlet, serta pembatasan menu berdasarkan peran.
   - Uji layar desktop dan mobile agar teks tidak terpotong, sidebar tidak bertumpuk dengan isi, dan footer tetap dapat dijangkau.
   - Periksa hasil visual, navigasi, error runtime, serta hasil build setelah perubahan.

## Batasan
- Tidak menghapus atau mengganti tujuan menu yang sudah ada.
- Tidak mengubah database, logika transaksi, perhitungan badge, atau hak akses.
- Perubahan hanya pada struktur, tampilan, dan interaksi sidebar merchant/POS.

## Detail Teknis
- Refactor utama pada sidebar merchant dan penyesuaian kecil pada layout merchant.
- Data menu dipindahkan ke konfigurasi grup agar mudah dirawat dan tidak mengulang markup.
- Kategori POS yang sudah menjadi sumber bersama tetap digunakan agar menu merchant dan halaman POS tidak berbeda.
