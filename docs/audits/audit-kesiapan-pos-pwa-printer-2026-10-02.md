# Audit Kesiapan POS PWA dan Printer Browser — 2 Oktober 2026

## Kesimpulan eksekutif

**POS belum boleh diklaim siap produksi lintas perangkat hanya karena fitur print sudah tersedia.** Jalur paling stabil untuk operasional adalah:

> **PWA/browser → Print Bridge lokal di komputer kasir → printer thermal LAN/WiFi atau USB-serial**

Browser tidak menyediakan satu API universal untuk printer thermal. Web Serial hanya cocok untuk perangkat yang benar-benar tampil sebagai serial/CDC, Web Bluetooth tidak mendukung Bluetooth Classic/SPP, dan `window.print()` selalu bergantung pada dialog serta driver OS.

Setelah audit, Print Bridge diperkuat untuk pemulihan antrean dan retry job gagal, dan UI readiness check sekarang menjalankan test print nyata untuk jalur WiFi/LAN.

## Matriks dukungan

| Jalur | Status teknis | Rekomendasi operasional | Batasan penting |
|---|---|---|---|
| LAN/WiFi raw TCP 9100 + Print Bridge | **Preferred / siap validasi staging** | Gunakan sebagai standar pilot | Printer dan komputer bridge harus berada di jaringan yang sama; IP sebaiknya reservasi DHCP |
| USB printer via Print Bridge `serialport` | **Siap validasi per model** | Pilihan kedua untuk kasir tetap | Hanya jika OS mengenali printer sebagai serial; banyak printer USB adalah USB printer class |
| USB langsung dari browser Web Serial | **Eksperimental / device-specific** | Jangan jadikan default | Memerlukan Chrome/Edge, HTTPS, izin perangkat, port tetap terbuka; koneksi hilang saat tab/PWA ditutup atau USB dicabut |
| Bluetooth BLE langsung dari browser | **Eksperimental / device-specific** | Tidak untuk operasi utama | Web Bluetooth tidak mendukung Bluetooth Classic/SPP; profil GATT/vendor berbeda-beda |
| Bluetooth melalui Print Bridge | **Validasi per adapter/model** | Dapat dipakai jika bridge/driver OS sudah membuktikan perangkat | Konfigurasi bridge tetap diperlukan; jangan menyamakan paired OS dengan raw ESC/POS siap cetak |
| Browser `window.print()` | **Fallback manual** | Sediakan sebagai fallback | Dialog printer OS, ukuran kertas, margin, popup, dan pembatalan tidak dapat dikonfirmasi secara authoritative oleh web app |

## Temuan dan status

### P0/P1 yang diperbaiki

1. **Print Bridge kehilangan job saat restart.**
   - Sebelumnya job persisted berstatus `queued`/`printing` dimuat ke memory tetapi tidak dikembalikan ke queue.
   - Sekarang job `printing` dinormalisasi ke `queued`, seluruh job tertunda dimasukkan kembali ke queue, dan queue diproses segera setelah startup.

2. **Job `failed` tidak dapat di-retry.**
   - Sebelumnya POST dengan `jobId` yang sama selalu mengembalikan job gagal lama sehingga tombol retry tidak pernah mengirim ulang.
   - Sekarang retry eksplisit mengubah job kembali ke `queued` dan memprosesnya ulang.
   - Retry dapat mencetak ganda jika printer sudah menerima data tetapi acknowledgement hilang. Ini harus tetap menjadi tindakan kasir yang sadar, bukan retry otomatis tanpa batas.

3. **CORS bridge sebelumnya wildcard (`*`).**
   - Website lain dapat mengirim request ke localhost dan berpotensi mengeluarkan cetak tidak sah.
   - Default sekarang dibatasi ke `https://www.sadesa.id`, `https://sadesa.id`, dan `http://localhost:5173`; staging wajib mengatur `ALLOWED_ORIGIN` sendiri.
   - Bridge tetap harus bind `127.0.0.1`; jangan bind ke LAN/public interface.

4. **Cek WiFi/LAN hanya memeriksa konfigurasi, bukan printer.**
   - Sekarang tombol cek koneksi mengirim test job dan menunggu status final `printed`/`failed`.

5. **Kasir dapat melihat bridge “siap” meski tidak ada printer default.**
   - Readiness check pada kasir sekarang mensyaratkan satu printer `isDefault: true`.

### Risiko tersisa yang harus dipahami

1. **Status `printed` adalah acknowledgement dari bridge/driver, bukan sensor kertas.** Printer tanpa status balik dapat kehabisan kertas atau macet setelah socket/serial write sukses.
2. **Browser fallback tidak dapat mengetahui apakah dialog print dibatalkan.** Receipt dibuka melalui dialog OS dan job lokal dianggap handed-off oleh browser; kasir harus memeriksa hasil fisik.
3. **Antrean receipt masih memakai `localStorage`, bukan IndexedDB.** Ukurannya cukup untuk receipt pendek, tetapi raw ESC/POS/base64 dan 100 job memiliki batas storage browser. Jangan mengandalkan queue lokal sebagai satu-satunya ledger transaksi.
4. **PWA service worker tidak mencetak sendiri.** Background Sync hanya menyegarkan metadata; printer tetap memerlukan tab/PWA aktif untuk memanggil bridge atau koneksi Web Serial. Untuk recovery, kasir harus membuka POS dan menekan retry bila diperlukan.
5. **Printer fisik, kualitas encoding, QR, cut, dan layout belum terbukti tanpa UAT perangkat nyata.** `TextEncoder` mengirim UTF-8; printer murah dengan code page non-UTF-8 dapat mencetak karakter Bahasa Indonesia secara salah.
6. **Multiple copies dan retry memiliki risiko duplikasi.** Uji satu salinan dulu; gunakan reprint dengan job ID berbeda hanya bila memang ingin mencetak ulang secara sadar.

## Runbook onboarding kasir

1. Gunakan **Chrome/Edge terbaru** pada Windows/macOS/Linux untuk komputer bridge, atau Android Chrome untuk skenario Web Serial yang memang sudah diuji.
2. Pastikan aplikasi dibuka melalui **HTTPS**. Jangan menjalankan POS produksi dari HTTP biasa.
3. Untuk standar pilot, pasang printer thermal LAN/WiFi dan buat DHCP reservation.
4. Jalankan Print Bridge sebagai service auto-start.
5. Edit `print-bridge/data/config.json` dan tandai tepat satu printer sebagai `isDefault: true`.
6. Pastikan `ALLOWED_ORIGIN` berisi origin aplikasi yang tepat; jangan gunakan wildcard pada produksi.
7. Buka `http://127.0.0.1:18181/health`; respons harus `ok: true`.
8. Di **POS → Pengaturan → Printer**, simpan IP/port yang sama dengan konfigurasi bridge.
9. Jalankan **Test Print** dan pastikan kertas benar-benar keluar.
10. Lakukan transaksi tunai kecil, cetak otomatis, cetak manual, dan reprint.
11. Matikan bridge, lakukan satu transaksi yang sesuai kebijakan offline, hidupkan kembali bridge, lalu verifikasi antrean dan hasil cetak.
12. Jika job gagal setelah printer mungkin sudah menerima data, periksa printer secara fisik sebelum menekan retry.

## UAT wajib sebelum pilot

| Skenario | Expected evidence |
|---|---|
| 58 mm dan 80 mm | Struk tidak terpotong, kolom total terbaca |
| Nama produk panjang dan karakter `é`, `–`, `Rp`, Bahasa Indonesia | Tidak ada karakter rusak/terpotong |
| QR receipt | QR dapat dipindai dari jarak normal |
| 1 dan 2 copies | Jumlah kertas tepat |
| Bridge restart saat queue berisi job | Job queued/printing dipulihkan dan diproses |
| Printer offline lalu online | Job failed dapat di-retry setelah kasir memeriksa status fisik |
| Cabut listrik/kabel USB | Tidak ada transaksi baru yang dibuat hanya karena retry print |
| Browser fallback cancel popup | UI tidak mengklaim printer thermal sudah mengeluarkan kertas |
| PWA reload/close/reopen | Konfigurasi, transaksi, dan antrean tetap scoped ke tenant/outlet |
| Dua komputer kasir | Masing-masing bridge dan printer default tidak tertukar |
| Windows, Android Chrome, macOS/Linux | Hasil dicatat per model printer dan browser |

## Keputusan readiness

- **Default pilot:** LAN/WiFi raw TCP + Print Bridge lokal.
- **USB browser langsung:** tidak disetujui sebagai baseline; hanya daftar kompatibilitas yang sudah diuji.
- **Bluetooth:** tidak disetujui sebagai baseline kecuali model BLE/bridge sudah lulus test fisik.
- **Browser print:** fallback manual, bukan pengganti Print Bridge untuk struk thermal otomatis.
- **Offline POS:** perlakukan sebagai beta/internal sampai bukti UAT perangkat, recovery, printer, dan rekonsiliasi tercatat.

## File yang diaudit / diubah

- `src/lib/thermalPrinter.ts`
- `src/lib/printBridgeClient.ts`
- `src/lib/receiptPrintContract.ts`
- `src/lib/printOutbox.ts`
- `src/hooks/usePOSReceipt.ts`
- `src/pages/pos/POSPengaturanPage.tsx`
- `src/sw.ts`
- `print-bridge/src/server.mjs`
- `print-bridge/README.md`
