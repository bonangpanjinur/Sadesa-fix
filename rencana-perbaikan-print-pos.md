# Rencana Perbaikan Pencetakan POS Tanpa Browser

**Repository:** `bonangpanjinur/remix-of-umkm-sadesa`  
**Tanggal analisis:** 28 Agustus 2026  
**Status:** Analisis dan rencana; belum mengubah kode produksi.

## Ringkasan eksekutif

Target penggunaannya jelas: setelah transaksi berhasil, struk harus dikirim langsung ke printer thermal tanpa popup, preview, tab baru, atau tampilan browser. Berdasarkan audit repository, aplikasi sebenarnya sudah memiliki fondasi ESC/POS, tetapi lapisan akses perangkatnya masih berada di dalam browser. Karena itu, PWA `display: standalone` saja belum cukup untuk memenuhi target tersebut.

**Rekomendasi utama** adalah menambahkan **Print Bridge lokal** yang berjalan sebagai aplikasi pendamping di komputer kasir. PWA mengirim job struk ke bridge melalui `localhost`, kemudian bridge mengirim byte ESC/POS langsung ke printer USB, TCP/IP, atau Bluetooth melalui sistem operasi. Dengan pola ini, layar kasir tetap modern seperti aplikasi desktop, sedangkan browser tidak lagi menjadi jalur komunikasi printer.

## Hasil audit kode saat ini

| Area | Kondisi saat ini | Dampak operasional | Prioritas |
|---|---|---|---|
| Format struk | Builder ESC/POS sudah tersedia di `src/lib/thermalPrinter.ts`, termasuk ukuran 58/80 mm, total, diskon, footer, QR, dan cut | Fondasi dapat dipakai kembali | Rendah |
| USB | Menggunakan Web Serial dan meminta port dari browser | Bergantung pada Chrome/Edge, HTTPS/localhost, izin pengguna, dan sesi halaman | Tinggi |
| Bluetooth | Menggunakan Web Bluetooth BLE dengan picker perangkat | Tidak semua printer Bluetooth thermal adalah BLE; discovery memerlukan izin/interaksi pengguna | Tinggi |
| WiFi | `WiFiPrinter.testConnection()` dan `send()` belum diimplementasikan; selalu error | UI terlihat mendukung WiFi, tetapi cetak nyata tidak berjalan | Kritis |
| Status WiFi di kasir | `connectThermalPrinter()` hanya memeriksa IP lalu menganggap terhubung | Status bisa hijau walaupun tidak pernah mengirim data ke printer | Kritis |
| Auto print | `PrinterSettings.autoPrint` tersedia, tetapi tidak dipakai setelah pembayaran | Kasir masih harus menekan tombol cetak | Tinggi |
| Fallback | `printReceipt()` jatuh ke `printReceiptBrowser()` yang membuka popup dan memanggil `window.print()` | Inilah penyebab utama pengalaman masih bergantung pada browser | Kritis |
| Cetak ulang | `POSTransaksiPage.tsx` menggunakan `window.print()` | Cetak transaksi lama tidak konsisten dengan thermal printer | Tinggi |
| Modul lain | `invoicePrint.ts` dan beberapa laporan memakai popup/`window.print()` | Perlu dipisahkan antara cetak struk thermal dan cetak dokumen laporan | Sedang |

Dengan demikian, persoalan utamanya bukan desain modal transaksi berhasil, melainkan **arsitektur jalur cetaknya**. Tombol “Cetak Struk” saat ini memiliki dua perilaku berbeda: ESC/POS bila koneksi browser berhasil, lalu popup browser bila gagal. Fallback tersebut harus dihapus dari alur kasir setelah bridge siap.

## Mengapa PWA murni tidak cukup

Web Serial memang dapat berkomunikasi dengan perangkat serial, tetapi hanya tersedia dalam secure context dan dukungan browsernya terbatas.[1] Web Bluetooth lebih terbatas lagi karena berfokus pada Bluetooth Low Energy, membutuhkan secure context dan izin eksplisit; pemanggilan pencarian perangkat memerlukan transient user activation.[2] Artinya, PWA tidak dapat menjamin koneksi otomatis lintas komputer kasir, printer USB, serta printer Bluetooth Classic/SPP.

> **Kesimpulan teknis:** PWA dapat menjadi antarmuka kasir, tetapi akses printer yang benar-benar langsung dan konsisten memerlukan komponen di luar sandbox browser.

## Opsi arsitektur

| Pendekatan | Trade-off | Biaya | Kompleksitas setup |
|---|---|---:|---:|
| **Print Bridge lokal + PWA** (direkomendasikan) | Tidak menampilkan browser dan dapat menangani USB, TCP/IP, serta Bluetooth melalui OS. Membutuhkan instalasi satu aplikasi kecil di setiap komputer kasir. | Rendah setelah dikembangkan; tanpa biaya layanan per transaksi | Sedang |
| **Aplikasi desktop berbasis Electron/Tauri** | Memberi kontrol penuh atas printer dan dapat membuka POS dalam jendela aplikasi. Distribusi, update, signing, dan packaging Windows/Linux perlu dikelola. Electron mendukung silent print serta pemilihan printer sistem melalui `deviceName`.[3] | Sedang; ada biaya pemeliharaan aplikasi desktop | Sedang–tinggi |
| **Chrome kiosk + silent printing** | Paling cepat sebagai transisi dan dapat menghilangkan address bar/preview bila deployment dikelola. Namun tetap bergantung pada Chrome, kebijakan perangkat, printer default, serta konfigurasi kiosk. Kebijakan Chrome Enterprise dapat mengaktifkan silent printing.[4] | Rendah | Rendah–sedang |
| **Pertahankan Web Serial/Web Bluetooth** | Perubahan kode relatif kecil, tetapi tidak memenuhi target “tidak tergantung browser”. Masih ada permission, kompatibilitas perangkat, user gesture, dan masalah Bluetooth Classic. | Rendah | Rendah |

Saya menyarankan **Print Bridge lokal terlebih dahulu**, bukan langsung membungkus seluruh POS menjadi aplikasi desktop. PWA yang sudah ada dapat dipertahankan, deployment lebih ringan, dan bridge dapat dipakai juga oleh aplikasi lain di jaringan lokal. Jika kelak diperlukan mode full-screen tanpa browser sama sekali, PWA dapat dibungkus ke Electron/Tauri dengan kontrak API bridge yang sama.

## Arsitektur target yang disarankan

```text
PWA POS
  |
  | HTTP/WebSocket localhost, misalnya http://127.0.0.1:18181
  v
Print Bridge lokal
  |-- USB: driver OS / raw USB / serial
  |-- LAN: TCP socket ke port printer 9100
  |-- Bluetooth: Bluetooth OS, termasuk perangkat Classic/SPP bila didukung
  |
  v
Printer thermal ESC/POS
```

Bridge sebaiknya memiliki API sederhana dan idempotent. PWA mengirim `jobId`, `printerId`, `copies`, `paperWidth`, serta `bytes` atau payload receipt yang kemudian dikompilasi bridge. Untuk mencegah transaksi tercetak dua kali ketika jaringan lokal bermasalah, bridge menyimpan status job secara lokal: `queued`, `printing`, `printed`, atau `failed`. Job yang sama dengan `jobId` identik tidak boleh dicetak ulang tanpa perintah eksplisit.

Pemisahan ini juga memperbaiki keamanan. Bridge hanya mendengarkan pada loopback, memvalidasi origin/token pasangan aplikasi, membatasi ukuran payload, dan tidak membuka port printer ke internet. PWA tidak boleh menganggap job berhasil hanya karena request HTTP diterima; status “tercetak” harus berasal dari respons bridge setelah data berhasil ditulis ke device.

## Perubahan alur transaksi

Setelah `processAtomicPOSSale()` berhasil, aplikasi membuat satu objek receipt kanonik dan satu `printJobId` berdasarkan nomor transaksi. Bila pengaturan **Cetak otomatis** aktif, aplikasi mengirim job ke bridge tanpa menunggu kasir menekan tombol. Modal sukses langsung menampilkan status kecil seperti “Mengirim ke Printer Kasir…” kemudian “Struk tercetak” atau “Menunggu printer”. Transaksi tidak dibatalkan hanya karena printer sedang offline; kasir tetap dapat menyelesaikan penjualan dan job masuk antrean lokal.

Tombol utama modal sebaiknya berubah dari pola “coba browser lalu fallback” menjadi **Cetak Ulang** ketika status sudah tercetak, atau **Kirim ke Printer** ketika job gagal. Tombol ini mengirim ulang job yang sama dengan konfirmasi ringan, bukan membuat struk dari HTML baru. Opsi WhatsApp dan simpan PDF tetap dipertahankan sebagai distribusi digital, tetapi tidak boleh menjadi fallback diam-diam untuk kegagalan printer.

Auto print juga harus berlaku untuk penjualan offline. Ketika transaksi tunai disimpan di antrean offline, statusnya menjadi “Transaksi tersimpan — menunggu sinkronisasi”. Setelah transaksi memiliki nomor penjualan final dan payload receipt tersedia, sistem dapat mencetak satu kali dengan idempotency key. Aturan ini penting agar reconnect atau sync tidak menghasilkan dua struk.

## Desain tampilan yang lebih bagus

Modal pada gambar sudah memiliki hierarki yang baik: ikon sukses, nomor transaksi, total, dan aksi utama. Perbaikannya adalah menjadikan printer sebagai status sistem, bukan tombol sambungan teknis. Bagian bawah modal dapat memakai kartu status dengan indikator warna, nama printer, estimasi antrean, dan aksi kontekstual.

| Status | Teks utama | Aksi |
|---|---|---|
| Bridge tidak terpasang | “Printer belum disiapkan” | “Buka Pengaturan Printer” |
| Bridge online, printer siap | “Struk tercetak otomatis” | “Cetak Ulang” |
| Job sedang dikirim | “Mengirim ke Printer Kasir…” | Tidak perlu aksi; tampilkan progress ringan |
| Printer offline | “Printer tidak terhubung” | “Coba Lagi” dan “Pilih Printer Lain” |
| Kertas habis/cover terbuka | “Printer membutuhkan perhatian” | “Buka panduan perbaikan” |
| Gagal permanen | “Struk belum tercetak” | “Cetak Ulang” dan “Simpan PDF” |

Di halaman pengaturan, gunakan wizard tiga langkah: **Pasang bridge**, **Tambah printer**, dan **Test print**. Jangan lagi menampilkan “WiFi terhubung” hanya berdasarkan IP. Status harus berasal dari health check bridge dan uji kirim nyata. Sediakan pilihan printer default per outlet, paper width 58/80 mm, jumlah salinan, auto print, cut mode, encoding, template, dan timeout.

## Roadmap implementasi

### Fase 1 — Stabilkan domain receipt dan kontrak printer

Pindahkan pembentukan data struk ke modul bersama yang digunakan oleh checkout, cetak ulang, dan test print. Tambahkan `saleId`, `saleNumber`, `createdAt`, `outletId`, `jobId`, serta snapshot nama toko dan item. Hapus ketergantungan pada `new Date()` saat cetak ulang agar tanggal struk tidak berubah ketika dicetak kembali.

### Fase 2 — Bangun Print Bridge lokal

Buat service desktop kecil dengan tray icon, health endpoint, daftar printer, koneksi USB/LAN/Bluetooth, antrean job, logging, auto-start, dan installer. Prioritaskan USB serta TCP/IP karena paling stabil untuk printer thermal toko. Bluetooth dapat menyusul setelah tipe printer target diketahui. Bridge harus menyediakan test print dan status printer yang jelas.

### Fase 3 — Integrasikan PWA

Tambahkan client `printBridgeClient.ts` yang melakukan discovery `localhost`, handshake, health check, submit job, retry terbatas, dan polling status. Ganti `thermalConnected` dengan status yang bersumber dari bridge. `printReceiptBrowser()` tidak lagi dipanggil dalam alur POS. Untuk browser yang tidak memiliki bridge, tampilkan pesan instalasi, bukan popup cetak otomatis.

### Fase 4 — Otomatisasi dan cetak ulang

Hubungkan `autoPrint` ke keberhasilan pembayaran. Tambahkan outbox lokal dengan idempotency key, retry yang aman, riwayat job, serta cetak ulang dari `POSTransaksiPage.tsx` melalui bridge yang sama. Laporan dan PDF boleh tetap memiliki jalur dokumen, tetapi struk thermal harus selalu melewati printer service.

### Fase 5 — Packaging dan hardening

Sediakan installer Windows terlebih dahulu karena mayoritas komputer kasir biasanya menggunakan Windows, lalu siapkan Linux bila diperlukan. Tambahkan auto-update bridge, signed installer, diagnostic screen, log export, health indicator, dan fallback manual yang eksplisit. Uji crash recovery, printer dicabut saat mencetak, dua kasir berbagi printer, koneksi jaringan terputus, serta restart komputer.

## Kriteria penerimaan

| Skenario | Hasil yang harus terjadi |
|---|---|
| Pembayaran tunai berhasil dan auto print aktif | Struk tercetak tanpa popup, preview, tab baru, atau dialog browser |
| Printer mati saat transaksi | Transaksi tetap tercatat; status job gagal/tertunda terlihat; kasir dapat retry |
| Bridge direstart | PWA mendeteksi kembali bridge dan antrean job tidak menggandakan struk |
| Klik cetak ulang | Mengirim receipt job kanonik ke printer yang sama, bukan `window.print()` |
| WiFi printer | Health check dan test print benar-benar mengirim byte ke IP/port printer |
| USB printer | Printer dapat dipilih sebagai perangkat OS/bridge dan menerima ESC/POS |
| Printer 58 mm dan 80 mm | Lebar kolom, wrapping item, QR, dan cut command sesuai profil |
| Dua kali klik cetak | Tidak menghasilkan duplikasi tanpa konfirmasi cetak ulang |
| Browser refresh setelah transaksi | Status transaksi dan job tidak hilang; idempotency tetap aman |

## Keputusan yang perlu dikonfirmasi sebelum implementasi

Ada tiga informasi perangkat yang menentukan detail bridge: sistem operasi komputer kasir, model printer thermal yang dipakai, dan jenis koneksi aktualnya. Khusus Bluetooth, perlu dipastikan apakah printer menggunakan BLE atau Bluetooth Classic/SPP karena dukungan browser saat ini tidak setara. Setelah data itu tersedia, implementasi dapat memilih driver OS yang paling stabil dan menentukan apakah fase pertama cukup dengan USB plus TCP/IP.

## Kesimpulan

Kode saat ini sudah memiliki komponen berharga berupa formatter ESC/POS, tetapi arsitektur akses perangkat masih browser-centric dan jalur WiFi belum nyata. Perbaikan paling tepat adalah **memisahkan PWA sebagai UI dari Print Bridge sebagai akses hardware**. Hasil akhirnya dapat memberikan pengalaman seperti aplikasi kasir native: transaksi selesai, struk langsung keluar, layar tetap bersih tanpa browser, printer dapat dipantau, dan kegagalan cetak tidak mengganggu pencatatan transaksi.

### References

[1]: https://developer.mozilla.org/en-US/docs/Web/API/Web_Serial_API "MDN — Web Serial API"

[2]: https://developer.mozilla.org/en-US/docs/Web/API/Web_Bluetooth_API "MDN — Web Bluetooth API"

[3]: https://www.electronjs.org/docs/latest/api/web-contents "Electron — webContents"

[4]: https://chromeenterprise.google/policies/silent-printing-enabled/ "Chrome Enterprise — SilentPrintingEnabled"
