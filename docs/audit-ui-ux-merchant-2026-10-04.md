# Audit UI/UX Merchant

**Tanggal:** 4 Oktober 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Cakupan:** navigasi merchant, struktur menu, alur pesanan, responsif mobile, CTA operasional, aksesibilitas dasar, dan validasi build.

## Ringkasan eksekutif

Workspace merchant sudah matang secara fitur: terdapat dashboard, pesanan, fulfillment, produk, stok, promosi, pelanggan, analitik, keuangan, pengaturan, serta modul POS. Tantangan utamanya bukan kekurangan fitur, melainkan **kepadatan navigasi dan jarak menuju tindakan paling penting**.

Prioritas pengalaman merchant adalah:

1. Melihat pesanan yang perlu ditindaklanjuti.
2. Menerima, memproses, mengirim, atau menyelesaikan pesanan.
3. Menambah produk dan mengatasi stok menipis.
4. Memahami angka operasional tanpa tertukar antara data sementara, periode, dan ringkasan server.

## Temuan audit

### P0 — Kepercayaan terhadap angka

- Dashboard sudah membedakan beberapa sumber data, tetapi setiap angka perlu tetap memiliki label periode/scope yang konsisten.
- Halaman laporan/analitik harus selalu membedakan state **loading**, **empty**, **error**, dan data valid.
- Export CSV sebaiknya terus menggunakan satu helper bersama dengan escaping RFC 4180 dan feedback sukses/gagal.

### P1 — Kecepatan kerja pesanan

- CTA utama pada tabel desktop sebelumnya hanya tampil untuk sebagian kondisi dan beberapa aksi masih berada di menu tiga titik.
- Pada status `NEW`/`PENDING_CONFIRMATION`, tindakan utama adalah **Terima**.
- Pada status `PROCESSED`, tindakan utama adalah **Kirim** dan perlu membuka detail untuk memilih metode pengiriman.
- Pada status `DELIVERING`, tindakan utama adalah **Sampai**.
- Mobile sudah memiliki kartu pesanan dan CTA, sehingga perilaku desktop perlu disamakan.

### P1 — Struktur navigasi

- Sidebar memiliki banyak grup dan menu lanjutan. Search dan accordion sudah tersedia, tetapi pengguna baru masih perlu memindai banyak item.
- Tugas yang paling sering dilakukan perlu dipisahkan dari menu administrasi dan fitur lanjutan.
- Label seperti `Loyalty Rules` dan `Price Book` masih bisa dilokalkan agar lebih operasional untuk merchant Indonesia.

### P2 — Konsistensi visual

- Fondasi visual sudah menggunakan token warna, Lucide icons, border radius, dan state aktif yang cukup konsisten.
- Ikon navigasi sebaiknya mempertahankan satu gaya outline; warna merah/amber hanya dipakai untuk status/peringatan.
- `Katalog Produk`, `Manajemen Stok`, dan `Bundle Produk` sebaiknya memakai ikon yang maknanya berbeda agar lebih mudah dipindai.

## Perubahan yang diterapkan

### 1. Blok Aksi cepat di sidebar

Menambahkan lima shortcut inti di bawah Dashboard:

- Pesanan baru
- Tambah produk
- Stok menipis
- Buat promo
- Laporan keuangan

Blok ini hanya tampil saat search menu tidak aktif sehingga tidak mengganggu mode pencarian dan tidak menghapus menu lanjutan.

### 2. CTA pesanan langsung di tabel desktop

Tabel pesanan kini menampilkan aksi utama secara langsung:

- `NEW` / `PENDING_CONFIRMATION` → **Terima**
- `PROCESSED` → **Kirim**
- `DELIVERING` → **Sampai**

Menu tiga titik tetap dipertahankan untuk aksi sekunder seperti detail, chat, cetak, verifikasi pembayaran, dan penolakan.

## Validasi

- `pnpm lint` — lulus tanpa error; terdapat 4 warning Fast Refresh lama pada `artifacts/mockup-sandbox`.
- Vitest untuk komponen merchant terkait — lulus.
- `pnpm build` — lulus; asset produksi berhasil dibuat dan service worker berhasil digenerate.

## Backlog rekomendasi berikutnya

1. Tambahkan CTA `Verifikasi pembayaran` sebagai aksi utama untuk status `PENDING_PAYMENT` ketika bukti pembayaran tersedia.
2. Tambahkan indikator realtime dengan state visual yang lebih tegas: **Live**, **Menghubungkan ulang**, dan **Offline**.
3. Audit ulang agregasi semua halaman laporan agar periode dan scope selalu tampak di dekat angka.
4. Lokalkan label menu lanjutan: `Loyalty Rules` → `Aturan Loyalti`, `Price Book` → `Daftar Harga`.
5. Lakukan usability test singkat pada merchant nyata di layar 360px, 768px, dan desktop 1280px.
