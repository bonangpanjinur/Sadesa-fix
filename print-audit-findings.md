# Temuan audit pencetakan POS

## Implementasi saat ini

- `src/lib/thermalPrinter.ts` sudah memiliki builder ESC/POS dan driver USB melalui Web Serial serta Bluetooth melalui Web Bluetooth.
- `WiFiPrinter.testConnection()` dan `WiFiPrinter.send()` selalu melempar error; jalur WiFi belum benar-benar diimplementasikan.
- `POSKasirPage.tsx` menyimpan transaksi lalu hanya membuka modal sukses. `printerSettings.autoPrint` belum dipakai untuk mencetak otomatis.
- `connectThermalPrinter()` untuk WiFi hanya menandai status terhubung berdasarkan IP, tanpa koneksi atau pengiriman data nyata.
- `printReceipt()` mencoba ESC/POS hanya jika `thermalConnected`; jika gagal, otomatis jatuh ke `printReceiptBrowser()` yang membuka popup dan memanggil `window.print()`.
- `POSPengaturanPage.tsx` menampilkan koneksi USB/Bluetooth/WiFi, tetapi USB/Bluetooth bergantung pada Web Serial/Web Bluetooth dan WiFi menjanjikan kemampuan yang belum ada.
- `POSTransaksiPage.tsx` masih memakai `window.print()` untuk cetak ulang, sehingga tidak konsisten dengan thermal printer.
- `invoicePrint.ts` juga memakai popup + `window.print()`.
- PWA di `vite.config.ts` hanya memakai manifest `display: standalone` dan caching; belum ada bridge lokal/native atau service worker printer.

## Batasan platform terverifikasi

- MDN Web Serial: API hanya tersedia pada secure context (HTTPS) dan dukungannya terbatas.
- MDN Web Bluetooth: API hanya untuk Bluetooth Low Energy, secure context, izin eksplisit, dan `requestDevice()` memerlukan transient user activation; dukungan browser terbatas.
- Kesimpulan: PWA murni tidak dapat menjamin pencetakan otomatis ke semua printer dan tidak dapat menghilangkan seluruh ketergantungan browser untuk akses perangkat.

## Arah solusi

Solusi paling andal adalah aplikasi pendamping lokal (desktop tray/service) yang menerima job ESC/POS dari PWA melalui localhost/WebSocket/HTTP dan mengirimkannya ke printer via USB, TCP/IP, atau Bluetooth OS. PWA tetap menjadi UI kasir, tetapi printer tidak lagi diakses dari browser.

Alternatif lebih ringan adalah mode kiosk Chrome dengan silent printing, tetapi tetap merupakan Chrome/browser dan hanya cocok untuk printer yang terpasang di sistem operasi.

Alternatif terbatas adalah mempertahankan Web Serial/Bluetooth dan menghapus fallback popup; ini tetap memerlukan dukungan browser, HTTPS, dan interaksi izin.

## Opsi arsitektur yang diteliti

- Electron menyediakan `webContents.print` dengan mode silent dan pemilihan printer sistem melalui `deviceName`, sehingga UI dapat tampil sebagai aplikasi desktop tanpa preview browser; tetap perlu menangani layout thermal dan status callback.
- Kebijakan Chrome Enterprise `SilentPrintingEnabled` dapat menutup preview dan mencetak ke printer default, tetapi pendekatan ini tetap menjalankan Chrome dan membutuhkan deployment kiosk/managed policy.
- Karena target pengguna secara eksplisit tidak ingin tampilan browser, bridge lokal/native menjadi rekomendasi utama; kiosk Chrome hanya alternatif transisi.

## Sumber

1. https://developer.mozilla.org/en-US/docs/Web/API/Web_Serial_API — Web Serial API, secure context dan keterbatasan dukungan.
2. https://developer.mozilla.org/en-US/docs/Web/API/Web_Bluetooth_API — Web Bluetooth API, BLE, secure context, izin eksplisit, transient activation, dan keterbatasan dukungan.
3. https://www.electronjs.org/docs/latest/api/web-contents — Electron `webContents` dan API printing.
4. https://chromeenterprise.google/policies/silent-printing-enabled/ — kebijakan SilentPrintingEnabled Chrome Enterprise.
