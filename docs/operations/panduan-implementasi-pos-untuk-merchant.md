# Panduan Implementasi dan Operasional POS untuk Merchant

**Versi:** 1.0
**Tanggal:** 2 Oktober 2026
**Pembaca:** pemilik usaha, manager outlet, kasir, staff stok, dan finance merchant.

Panduan ini menjelaskan cara menyiapkan POS SaDesa dan menjalankan uji operasional terbatas sebelum dipakai rutin. Nama menu mengikuti workspace merchant saat ini; fitur yang terlihat bergantung pada role, entitlement, outlet aktif, dan modul yang diaktifkan.

- Untuk status fitur dan risiko yang ditemukan, baca [Audit Operasional POS untuk Merchant](../audits/audit-operasional-pos-merchant-2026-10-02.md).
- Untuk onboarding pilot yang didampingi, baca [SOP onboarding merchant pilot](sop-onboarding-merchant-pilot.md).
- Untuk prosedur dan bukti cetak terbaru, baca [Hasil uji E2E pembayaran dan kesiapan print](../audits/hasil-uji-e2e-pos-payment-print-2026-10-02.md).

## 1. Siapkan informasi sebelum mulai

Siapkan hal berikut sebelum membuka setup:

- Nama usaha, alamat/nomor kontak, zona waktu, mata uang dan data outlet.
- Daftar produk/menu aktif, harga jual, kategori, varian/SKU/barcode jika dipakai, serta stok awal per outlet.
- Daftar staf dan role yang diperlukan; tentukan siapa yang bertanggung jawab membuka/menutup kas dan menyetujui retur.
- Perangkat yang akan dipakai, akses internet cadangan, serta spesifikasi printer bila akan mencetak struk.
- Metode pembayaran yang benar-benar diterima toko dan cara memverifikasi pembayaran pada kanal bank/acquirer/EDC merchant.

**Akses POS:** profil merchant perlu berstatus disetujui dan aktif, dan entitlement trial/langganan POS harus aktif. Jika setup gagal atau diarahkan ke halaman paket, minta admin/owner memeriksa status profil, entitlement, role, dan modul. Jangan membagikan kata sandi atau PIN kepada support melalui chat.

## 2. Aktifkan workspace, pilih modul, dan buat outlet pertama

1. Buka **Siapkan POS** (`/merchant/pos/setup`).
2. Pilih jenis usaha yang sesuai. Pilihan jenis usaha memberi rekomendasi modul; bukan pengganti pengaturan produk dan outlet.
   - **Hanya online:** bukan alur aktivasi POS outlet; pilihan ini mengarahkan kembali ke workspace merchant.
   - **Toko retail:** cocok untuk produk fisik, barcode/varian, stok, pembelian, retur dan beberapa outlet bila dibutuhkan.
   - **Kafe/restoran:** rekomendasi meja, menu QR, KDS, bahan baku/resep dan shift.
   - **Beberapa outlet:** rekomendasi outlet, transfer stok, pembelian, laporan dan shift.
   - **Usaha sederhana:** alur minimum kasir, stok outlet dan laporan penjualan.
3. Tinjau modul yang disarankan. **Modul Kasir wajib dipilih.** Pilih hanya fitur yang akan diuji/dijalankan saat ini; beberapa rute tidak akan terbuka jika modul tidak diaktifkan atau entitlement tidak mencakupnya.
4. Katalog produk/pelanggan/promo tetap memakai workspace merchant yang sama; produk yang sudah tersedia tidak perlu dibuat ulang hanya agar muncul di kasir.
5. Isi nama usaha dan outlet pertama dengan identitas lokasi yang mudah dikenali oleh kasir dan finance. Simpan alamat/telepon bila digunakan pada struk atau komunikasi.
6. Setelah aktivasi, pastikan workspace dan outlet yang benar tampil. Untuk usaha multi-outlet, buat outlet tambahan dari pengaturan operasional dan validasi konteks outlet sebelum mengisi stok atau transaksi.

### Pilihan modul awal yang disarankan

| Jenis usaha | Mulai dengan | Tambahkan setelah alur dasar lulus |
|---|---|---|
| Retail satu outlet | Kasir, Stok Outlet, Laporan Penjualan | Barcode, Varian, Pembelian/Supplier, Retur |
| Kafe/restoran | Kasir, Laporan, Meja | Menu QR, KDS, Bahan Baku, Resep, Shift |
| Multi-outlet | Kasir, Stok Outlet, Laporan | Transfer Stok, Pembelian, Shift, laporan outlet |
| Usaha sederhana | Kasir, Stok Outlet, Laporan | Tambahkan sesuai kebutuhan nyata |

Daftar ini adalah urutan implementasi praktis, bukan konfigurasi teknis wajib. Modul Kasir diperlukan untuk transaksi POS.

## 3. Siapkan katalog, harga, dan stok

1. Buka **Katalog Pedagang** (`/merchant/products`) untuk menambah atau memeriksa produk. Pastikan produk yang hendak dijual aktif.
2. Gunakan **Kategori Produk** untuk membantu pencarian kasir. Untuk produk dengan ukuran/warna/pilihan, periksa varian, barcode dan harga tiap varian.
3. Untuk outlet dengan stok terpisah, buka **Stok Outlet** (`/merchant/pos/stok`) dan masukkan jumlah awal sesuai hasil hitung fisik. Pastikan outlet aktif yang dipilih benar.
4. Bila mengelola lebih dari satu outlet, uji **Transfer Stok** dan konfirmasi jumlah asal/tujuan sebelum transaksi outlet tujuan.
5. Lakukan uji pencarian produk di halaman kasir. Periksa harga, varian, satuan, ketersediaan, dan apakah barang dengan stok habis ditangani sesuai kebijakan toko.

**Kontrol merchant:** gunakan hitung fisik sebagai baseline. Jangan mengisi stok berdasarkan angka perkiraan lalu menganggap laporan stok sebagai bukti stok fisik.

## 4. Daftarkan pengguna dengan akses minimum

Buka **Pengguna & Kasir** (`/merchant/pos/pengguna`), lalu:

1. Buat satu akun/pengguna per staf; pilih role sesuai tugas dan outlet yang benar.
2. Role yang disediakan mencakup owner, manager, kasir, staff gudang, purchasing, finance, dan auditor. Ikuti prinsip akses minimum; kasir operasional tidak otomatis membutuhkan akses owner/finance.
3. Jika memakai PIN kasir, buat PIN individual yang tidak mudah ditebak, jangan ditulis di dekat kasir, jangan dipakai bersama, dan ubah/nonaktifkan akses ketika staf pindah/berhenti.
4. Minta tiap staf masuk melalui mekanisme akun resmi. Jangan menaruh kredensial dalam dokumen operasional, tiket, atau chat grup.
5. Uji dengan masing-masing role: buka hanya menu dan outlet yang memang dibutuhkan. Bila ada akses yang keliru, jangan lanjutkan penggunaan luas sebelum diperbaiki.

## 5. Atur struk dan printer (opsional, tetapi wajib diuji bila dipakai)

Printer tidak diperlukan untuk menuntaskan onboarding POS inti; browser print dapat menjadi fallback. Jika toko akan memakai printer thermal:

1. Buka **Pengaturan Operasional** (`/merchant/pos/pengaturan`) dan isi header/footer struk, nomor kontak/alamat, zona waktu, serta mata uang.
2. Pilih jalur yang didukung perangkat: USB, Bluetooth, Wi-Fi/LAN melalui Print Bridge, atau Android Print Service yang disiapkan untuk perangkat tersebut.
3. Untuk printer Wi-Fi/LAN, pastikan IP/port printer sama dengan konfigurasi Print Bridge. Service/bridge harus aktif pada perangkat/jaringan yang dapat dijangkau oleh browser kasir.
4. Simpan pengaturan, sambungkan printer jika jalur tersebut memerlukan pairing, lalu gunakan **Test Print**.
5. Periksa kertas keluar secara fisik: nama outlet, waktu, nama barang/varian, subtotal/diskon/pajak/total, metode bayar, karakter rupiah, lebar kertas 58/80 mm, keterbacaan dan potongan kertas.
6. Jalankan transaksi uji yang disetujui, cetak sekali, lalu uji **cetak ulang** dari detail transaksi. Periksa agar retry/refresh tidak mencetak salinan tak disengaja.
7. Tetapkan fallback: buka/cetak struk melalui browser atau simpan nomor transaksi bila perangkat cetak gagal.

Status `connected`, health check atau job yang berstatus berhasil bukan bukti fisik bahwa kertas sudah keluar. Jangan menyatakan printer siap dipakai merchant sebelum tes pada perangkat dan model printer yang benar-benar akan digunakan.

## 6. Latih satu transaksi kasir dan pembayaran

Lakukan pada outlet dan perangkat uji yang benar. Bila ini sudah lingkungan produksi, gunakan proses/nominal uji yang telah disepakati merchant; jangan melakukan otorisasi/pembayaran riil tanpa persetujuan pihak yang bertanggung jawab.

1. Buka **Kasir** (`/merchant/pos/kasir`), pastikan nama outlet di konteks sesuai.
2. Cari barang atau pindai barcode, pilih varian yang tepat, periksa kuantitas dan stok. Tambahkan pelanggan/promo/voucher/poin hanya jika aturan merchant telah dikonfigurasi dan diuji.
3. Buka pembayaran. Pastikan total dan setiap diskon benar sebelum menekan proses.
4. Untuk **tunai**, masukkan uang yang diterima; kasir harus mencukupi total dan sistem menghitung kembalian.
5. Untuk **QRIS/transfer/debit**, pastikan notifikasi/pembayaran sukses pada aplikasi/acquirer/bank/EDC merchant sebelum transaksi dianggap telah dibayar. Pilihan metode di POS tidak sendirinya mengonfirmasi settlement.
6. Untuk split payment, pastikan jumlah dua metode sama persis dengan total dan verifikasi kedua bagian pembayarannya.
7. Setelah sukses, simpan nomor transaksi, cek **Transaksi Toko**, pastikan stok berkurang sesuai, lihat struk/riwayat, dan cocokkan dengan laporan kas.
8. Jika layar macet atau status tidak jelas, periksa riwayat dan status antrean dulu. Jangan tekan proses berkali-kali atau membuat transaksi kedua untuk transaksi yang mungkin sudah tercatat.

## 7. Jalankan kas harian dan rekonsiliasi

Buka **Kas Harian** (`/merchant/pos/kas`). Kebijakan toko dapat berbeda; prosedur berikut adalah baseline kontrol:

### Awal sesi

- Hitung uang awal di laci dan masukkan jumlah aktual pada **Buka Sesi Kasir**.
- Catat nama kasir yang bertanggung jawab dan catatan awal yang diperlukan.
- Jangan menggunakan saldo awal sebagai angka perkiraan atau saldo penjualan.

### Selama sesi

- Catat setoran/kas masuk dan kas keluar pada kategori yang benar beserta nominal, deskripsi dan referensi.
- Simpan bukti pengeluaran/pembelian sesuai prosedur pembukuan merchant.
- Bedakan penjualan tunai dan non-tunai; uang non-tunai bukan uang fisik di laci.

### Akhir sesi

- Hitung uang fisik sebelum menutup sesi, masukkan saldo akhir aktual dan beri catatan bila ada selisih.
- Bandingkan ekspektasi kas dengan uang terhitung. Tinjau penjualan tunai, saldo awal, kas masuk/keluar, retur tunai, serta transaksi yang statusnya belum pasti.
- Tinjau kartu **Rekonsiliasi Harian**. Jika tertulis **Perlu ditinjau** atau **Jurnal tidak seimbang**, cari penyebab dan minta manager/finance memeriksa sebelum menandai rekonsiliasi selesai.
- Simpan/ekspor ringkasan sesi sesuai prosedur internal. Untuk pembayaran non-tunai, cocokkan laporan POS dengan laporan acquirer/bank.

Tombol menandai rekonsiliasi bukan pengganti pemeriksaan selisih. Jika selisih material atau tidak dapat dijelaskan, tahan penutupan operasional sesuai kebijakan merchant dan eskalasi ke manager/finance.

## 8. Retur, koreksi, dan cetak ulang

- Untuk barang yang dikembalikan, buka **Retur Toko** (`/merchant/pos/retur`) dan cari nomor transaksi asal.
- Pilih barang serta jumlah yang benar, masukkan alasan, pilih metode refund, dan tentukan apakah barang layak masuk stok lagi.
- Alur ini mengajukan retur untuk approval; ikuti otorisasi yang berlaku sebelum menjanjikan refund kepada pelanggan.
- Jangan menghapus transaksi asal atau membuat retur palsu untuk mengoreksi salah input. Gunakan jalur koreksi/approval yang berlaku dan catat referensi.
- Jika hanya struk yang hilang, buka detail transaksi pada **Transaksi Toko** dan pilih cetak ulang. Pastikan tidak membuat penjualan kedua.

## 9. Operasi ketika internet terputus

POS offline hanya didukung bila perangkat memenuhi seluruh prasyarat aplikasi: koneksi melalui HTTPS/konteks aman, IndexedDB aktif, dan service worker/PWA tersedia. Periksa indikator di **Offline Conflict Center** (`/merchant/pos/offline-conflicts`) pada perangkat yang akan dipakai.

- Kemampuan offline yang dinyatakan: **penjualan tunai**, katalog yang sudah tersimpan di cache, dan struk lokal.
- Tetap memerlukan online: pembayaran non-tunai, order marketplace, laporan final dan settlement.
- Lakukan uji putus/sambung koneksi lebih dulu dengan data uji yang disepakati. Perangkat lain atau browser baru mungkin belum memiliki cache katalog.
- Setelah koneksi pulih, biarkan aplikasi terbuka/online dan pantau jumlah antrean, proses sync, dead-letter dan conflict.
- Buka item conflict, simpan ID/waktu/nominal/kode kesalahan, lalu coba lagi sesuai arahan manager setelah memastikan tidak ada transaksi duplikat.
- **Jangan** reset data perangkat, clear browser/site data, uninstall PWA, atau berpindah perangkat ketika ada antrean yang belum sinkron. Reset dapat menghapus antrean lokal.
- Bila status/hasil pembayaran tidak pasti, jangan menjual ulang atau mencatat transaksi kompensasi sebelum rekonsiliasi.

## 10. Lihat transaksi dan laporan dengan batasan ekspor

### Riwayat transaksi

Pada **Transaksi Toko** (`/merchant/pos/transaksi`), gunakan filter tanggal, status, pencarian nomor/customer dan outlet yang benar. Ekspor CSV dari halaman ini berisi baris transaksi yang sedang dimuat dan sudah difilter. Cocokkan jumlah baris dan total dengan ringkasan sebelum menggunakannya.

### Laporan penjualan

**Laporan Penjualan** menyediakan ringkasan omzet, jumlah transaksi, rata-rata transaksi, diskon, tren dan produk teratas; tersedia rentang hari ini, minggu, bulan dan tahun. PDF saat ini berupa ringkasan dan produk teratas.

> **Peringatan penting:** tombol `Excel` pada halaman Laporan Penjualan saat ini membentuk CSV dari daftar produk teratas dan mengisi beberapa kolom transaksi dengan nilai placeholder. Jangan gunakan berkas itu sebagai detail transaksi, bukti pembayaran/settlement, rekonsiliasi invoice, atau pembukuan per transaksi.

Untuk detail transaksi, gunakan CSV pada **Transaksi Toko**, lalu verifikasi kelengkapan hasil/rentang karena halaman tersebut belum menampilkan pagination atau jumlah total server secara eksplisit. Untuk pajak, pembukuan resmi, atau settlement, cocokkan dengan sistem dan dokumen resmi merchant/acquirer; laporan POS bukan nasihat pajak atau bukti settlement provider.

## 11. Checklist sebelum mulai digunakan rutin

| Pemeriksaan | Lulus jika… |
|---|---|
| Akses & entitlement | Merchant aktif, POS operational, role dan modul yang diperlukan dapat membuka menu terkait. |
| Outlet & katalog | Outlet benar; produk, harga/varian, kategori dan stok fisik awal diverifikasi. |
| Pengguna | Owner/manager/kasir memiliki akun/role/outlet sesuai tugas; PIN tidak dibagi. |
| Pembayaran | Uji kas mencukupi/kembalian benar; QRIS/transfer/EDC dikonfirmasi pada provider; split sama dengan total. |
| Transaksi | Satu alur transaksi uji tampil satu kali di riwayat, harga/total/stok benar, dan nomor transaksi tercatat. |
| Kas | Sesi dapat dibuka/ditutup, saldo aktual dicatat, mutasi terdokumentasi dan selisih ditinjau. |
| Retur | Alur permintaan/approval, refund dan keputusan restock dipahami manager. |
| Printer (jika digunakan) | Test fisik transaksi dan reprint lulus; ada fallback yang diketahui semua kasir. |
| Offline (jika digunakan) | Policy perangkat lulus; antrean/sync/conflict diuji; pemilik mengetahui larangan reset data lokal. |
| Laporan | CSV riwayat dicocokkan dengan jumlah transaksi; tombol Excel pada Laporan Penjualan tidak dipakai sebagai ledger. |
| Support | Ada kontak owner/manager dan prosedur eskalasi; tiket mencatat waktu, outlet, nomor transaksi/request, gejala dan dampak tanpa credential. |

Jika ada kontrol kritis yang gagal, jalankan POS sebagai pilot terbatas atau tahan penggunaan fitur terkait sampai owner menyetujui perbaikan. Untuk pilot eksternal, ikuti gate GO/HOLD/STOP di SOP onboarding merchant pilot.

## 12. Pemecahan masalah cepat

| Gejala | Tindakan pertama |
|---|---|
| Tidak dapat membuka menu POS | Periksa login, status profil merchant, entitlement trial/langganan, role, outlet, dan apakah modul/permission mengizinkan menu. |
| Produk tidak muncul | Periksa produk aktif di katalog bersama, pencarian/kategori, varian, outlet aktif dan stok/cache pada perangkat. |
| Pembayaran non-tunai tidak bisa diproses | Periksa koneksi internet; POS memerlukan online untuk metode non-tunai. Verifikasi pembayaran pada kanal acquirer/EDC, bukan hanya status pilihan metode. |
| Printer tidak mencetak | Cek kertas/power/pairing/IP, health Print Bridge, antrean job, lalu lakukan test print fisik; gunakan fallback browser bila diizinkan. Simpan nomor transaksi. |
| Transaksi offline belum muncul di server | Jangan buat duplikat. Sambungkan kembali perangkat, buka Offline Conflict Center, cek queue/status, dan eskalasi bila status failed/conflict. Jangan reset perangkat. |
| Selisih saldo atau laporan | Tahan penandaan selesai; cocokkan outlet/tanggal, sesi, penjualan tunai/non-tunai, mutasi kas, retur/refund, dan laporan acquirer bersama manager/finance. |
| Ekspor Excel laporan tampak seperti invoice | Hentikan pemakaian file tersebut untuk ledger. Pakai CSV Transaksi Toko dan validasi jumlah/rentang; laporkan kepada owner/finance sampai ekspor laporan diperbaiki. |

## 13. Referensi teknis internal

Untuk operator merchant, gunakan menu aplikasi di atas. Referensi internal berikut membantu owner/admin/engineering saat melakukan konfigurasi atau eskalasi:

- Navigasi POS: `src/components/pos/posNavigation.tsx`
- Gate akses dan modul: `src/components/pos/posPermissions.tsx`, `src/lib/posFeatureGate.ts`
- Policy perangkat offline: `src/lib/posDevicePolicy.ts`
- Validasi pembayaran: `src/lib/posPaymentValidation.ts`
- Kontrak riwayat: `src/lib/posCanonicalReports.ts`, `src/lib/posTransactionHistory.ts`
- Ekspor laporan: `src/pages/pos/POSLaporanPage.tsx`, `src/lib/exportReport.ts`
- SOP pilot: `docs/operations/sop-onboarding-merchant-pilot.md`

Dokumen ini menjelaskan perilaku yang diaudit pada source per 2 Oktober 2026. Label/menu dan batas produk dapat berubah setelah rilis; sebelum onboarding merchant baru, owner operasional sebaiknya menjalankan ulang checklist pada perangkat dan environment sasaran.
