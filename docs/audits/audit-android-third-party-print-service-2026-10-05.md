# Audit Integrasi Android Third-Party Print Service

**Tanggal:** 5 Oktober 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Komponen:** `src/lib/androidPrintService.ts`, `src/pages/pos/POSPengaturanPage.tsx`

## Ringkasan

Integrasi menggunakan **ESCPOS Bluetooth Print Service** dari Looped Labs melalui Android app link dengan skema:

```text
print://escpos.org/escpos/bt/print
```

Kontrak app link di kode sesuai dokumentasi vendor: `srcTp=uri`, `srcObj=html`, `numCopies`, dan `src` berupa HTML data URL. Receipt dikirim sebagai HTML yang sudah di-escape, bukan sebagai URL publik.

Integrasi ini cocok untuk tablet Android yang sudah memasangkan printer Bluetooth dan mengonfigurasi printer di aplikasi pihak ketiga. Namun, browser tidak menerima acknowledgement dari aplikasi atau printer bahwa kertas benar-benar keluar.

## Temuan

| ID | Severity | Temuan | Status |
|---|---|---|---|
| AND-01 | P0 operasional | Browser tidak dapat membuktikan app pihak ketiga terpasang, printer sudah dipilih, atau kertas sudah keluar. Klik `print://` dapat selesai tanpa error walau handler tidak tersedia. | Dimitigasi di UI: status disebut **perintah dikirim**, bukan printer terhubung/tercetak. UAT fisik tetap wajib. |
| AND-02 | P1 kompatibilitas | App link vendor tersedia mulai versi 2.1.6; parameter `numCopies` tersedia mulai versi 2.3.2. Instalasi versi lama dapat gagal menerima alur atau jumlah salinan. | Dijelaskan di UI. |
| AND-03 | P1 setup | Printer harus dipasangkan di Android dan dipilih/diuji dari aplikasi pihak ketiga sebelum SaDesa digunakan. | Langkah setup ditambahkan ke kartu Android di Pengaturan Printer. |
| AND-04 | P1 platform | Jalur ini hanya Android dan harus dijalankan melalui browser yang dapat membuka app link, idealnya Chrome di HTTPS. | UI memberi peringatan jika perangkat bukan Android. |
| AND-05 | P2 ketergantungan vendor | Aplikasi pihak ketiga mempunyai model trial/premium dan dukungan printer bergantung pada model ESC/POS. | Dicatat sebagai risiko operasional; siapkan fallback browser atau Print Bridge. |
| AND-06 | P2 bukti pengujian | Unit test memvalidasi format link dan escaping HTML, tetapi tidak dapat memvalidasi Bluetooth, pairing, karakter printer, pemotong kertas, atau kertas fisik. | UAT perangkat nyata masih diperlukan. |

## Perilaku yang sudah diaudit

1. `buildAndroidPrintLink()` membuat app link resmi vendor.
2. `buildAndroidReceiptHtml()` melakukan escaping terhadap nama toko, item, invoice, metode pembayaran, dan footer.
3. Jumlah salinan dibatasi 1–10 sesuai parameter vendor.
4. `isAndroidPrintServiceSupported()` menolak pemanggilan dari perangkat non-Android.
5. Test print menggunakan receipt dummy dan tidak membuat transaksi.
6. UI Android sekarang menjelaskan instalasi, pairing, pemilihan printer, ukuran kertas, tipe ESC/POS, test print, serta keterbatasan acknowledgement.

## Cara penggunaan yang disarankan

1. Di tablet Android, instal **ESCPOS Bluetooth Print Service** dari Looped Labs.
2. Aktifkan Bluetooth dan pair printer melalui pengaturan Android.
3. Buka aplikasi pihak ketiga, pilih printer, ukuran kertas, tipe printer, dan lakukan test print dari aplikasi tersebut.
4. Buka SaDesa menggunakan Chrome melalui HTTPS.
5. Buka **Pengaturan Operasional → Printer** dan pastikan tenant/outlet aktif benar.
6. Pilih **ESC/POS Bluetooth Print Service**.
7. Simpan pengaturan, lalu tekan **Test Print**.
8. Jika perintah dikirim tetapi kertas tidak keluar, buka ulang aplikasi pihak ketiga, pastikan printer yang dipilih benar, dan cek status Bluetooth.
9. Jalankan satu transaksi uji yang disetujui merchant sebelum produksi.

## Sumber vendor yang diperiksa

- [Dokumentasi App Links ESC/POS BT Print Service](https://loopedlabs.com/esc-pos-bluetooth-print-service/app-links)
- [Halaman resmi ESC/POS Bluetooth Print Service](https://loopedlabs.com/esc-pos-bluetooth-print-service/)
- [Listing Google Play](https://play.google.com/store/apps/details?id=com.loopedlabs.escposprintservice&hl=en_US)

## Kesimpulan

Integrasi app link **secara kontrak sudah benar**, tetapi tidak boleh diperlakukan sebagai bukti hardware acknowledgement. UI kini menjelaskan prasyarat dan langkah penggunaan secara eksplisit. Sebelum menyatakan fitur siap produksi, lakukan UAT pada tablet Android, versi aplikasi pihak ketiga yang dipakai, model printer Bluetooth, ukuran kertas 58/80 mm, karakter bahasa Indonesia, jumlah salinan, dan kondisi app tidak terpasang.
