# Audit Fitur Print POS — 4 Oktober 2026

## 1. Ringkasan eksekutif

Audit ini hanya mencakup fitur print POS: cetak otomatis setelah transaksi, cetak manual, cetak ulang, Print Bridge, printer USB/Bluetooth/Android, browser fallback, dan antrean print lokal.

**Kesimpulan:** jalur dasar sudah memiliki fondasi yang baik—kontrak receipt tunggal, outbox lokal, retry manual, idempotensi job, dan test terarah. Namun fitur belum layak dinyatakan siap produksi untuk semua skenario printer karena ditemukan **2 temuan P1** dan **4 temuan P2**, ditambah batasan bahwa printer fisik belum diuji pada environment ini.

### Status pengujian saat audit

| Area | Hasil | Batasan |
|---|---:|---|
| Test terarah print | **13/13 lulus** | Semua printer/bridge dimock atau tidak memakai hardware nyata |
| TypeScript | **Lulus** | Tidak ada perubahan kode dilakukan dalam audit |
| Print Bridge `127.0.0.1:18181` | Belum diuji koneksi fisik | Service/printer tidak tersedia di sandbox |
| UAT printer nyata | Belum dilakukan | Belum dapat membuktikan kertas benar-benar keluar |

## 2. Cakupan yang diperiksa

- `src/pages/pos/POSKasirPage.tsx`
- `src/pages/pos/POSTransaksiPage.tsx`
- `src/pages/pos/POSPengaturanPage.tsx`
- `src/hooks/usePOSReceipt.ts`
- `src/lib/receiptDomain.ts`
- `src/lib/receiptPrintContract.ts`
- `src/lib/printOutbox.ts`
- `src/lib/printBridgeClient.ts`
- `src/lib/thermalPrinter.ts`
- `print-bridge/src/server.mjs`
- test receipt, outbox, bridge, Android print service, QR print, dan E2E pembayaran POS

## 3. Temuan

### P1 — Cetak ulang memakai `jobId` yang sama sehingga retry dapat menjadi no-op

**Lokasi:** `src/pages/pos/POSTransaksiPage.tsx:164–193`, `src/lib/printOutbox.ts:27–41`, `src/lib/receiptPrintContract.ts:31–35`

Cetak ulang membuat ID:

```ts
jobId: `receipt:reprint:${selected.id}:${selected.created_at}`
```

`enqueueReceiptData()` menolak menambahkan job jika `jobId` sudah ada. Jika cetak ulang pertama sudah berstatus `printed`, pemanggilan cetak ulang berikutnya tidak membuat job baru; `flushReceiptOutbox()` melewati job yang sudah `printed`, lalu kontrak mengembalikan `{ status: 'printed' }`. UI menampilkan toast sukses walaupun printer tidak menerima pekerjaan baru.

**Dampak:** kasir mengira salinan kedua tercetak padahal tidak ada perintah baru ke printer. Ini sangat relevan saat struk hilang atau printer mengalami paper jam.

**Rekomendasi:** gunakan ID unik per percobaan cetak ulang, misalnya `receipt:reprint:${saleId}:${crypto.randomUUID()}` atau counter monotonic. Tetap simpan `saleId` sebagai identitas transaksi, tetapi jangan gunakan status job lama untuk menyimpulkan status percobaan baru. Tambahkan test cetak ulang dua kali dan assert bridge menerima dua job.

### P1 — Konfigurasi printer global lintas tenant/outlet/perangkat

**Lokasi:** `src/lib/thermalPrinter.ts:35–59`

Pengaturan disimpan di satu key global:

```ts
const SETTINGS_KEY = "pos_printer_settings";
```

Pengaturan mencakup `connectionType`, IP, baud rate, paper width, jumlah salinan, dan auto print. Tidak ada `tenantId`, `outletId`, atau device scope. Pada komputer/tablet yang dipakai bergantian oleh beberapa outlet atau tenant, konfigurasi terakhir dapat dipakai oleh tenant/outlet berikutnya.

**Dampak:** transaksi dapat dikirim ke printer outlet yang salah, jumlah salinan/auto-print dapat terbawa antar akun, dan konfigurasi operasional tidak terisolasi sesuai boundary POS.

**Rekomendasi:** scope key minimal ke tenant dan outlet aktif, misalnya `pos_printer_settings:${tenantId}:${outletId}:${deviceId}`. Migrasikan key lama satu kali dengan indikator bahwa konfigurasi tersebut belum terverifikasi untuk outlet aktif. Jangan menyimpan secret/token bridge di `localStorage` bila nanti autentikasi bridge ditambahkan.

### P2 — Browser fallback selalu menggunakan layout 80 mm

**Lokasi:** `src/lib/thermalPrinter.ts:435–481`

`printReceiptBrowser()` menggunakan `@page { size: 80mm auto }`, body `80mm`, dan lebar teks 42/48 karakter tanpa membaca `getPrinterSettings().paperWidth`. Pengaturan POS menyediakan pilihan 58 mm dan 80 mm.

**Dampak:** saat merchant memilih 58 mm tetapi printer fallback browser digunakan, hasil cetak dapat terlalu lebar, terpotong, atau menghasilkan whitespace yang tidak sesuai. PDF receipt pada `POSKasirPage` juga memakai `@page { size: 80mm auto }` secara tetap.

**Rekomendasi:** baca paper width pada browser/PDF renderer dan gunakan token layout yang sama dengan ESC/POS: 58 mm → sekitar 32 kolom, 80 mm → sekitar 42 kolom. Tambahkan test snapshot/DOM untuk kedua ukuran.

### P2 — Status `printed` berarti job selesai dikirim, bukan bukti kertas keluar

**Lokasi:** `print-bridge/src/server.mjs:68–75`, `print-bridge/src/server.mjs:102–120`

Untuk TCP, bridge menganggap job berhasil setelah socket ditutup tanpa error:

```js
socket.once('connect', () => socket.end(Buffer.from(bytes)));
socket.once('close', hadError => { if (!hadError) resolve(); });
```

Printer thermal TCP umumnya tidak memberi acknowledgement level aplikasi. Karena itu koneksi TCP yang diterima tidak membuktikan printer mencetak, memotong kertas, atau memiliki kertas.

**Dampak:** UI dapat menampilkan berhasil meski printer kehabisan kertas, macet, atau menerima data sebagian.

**Rekomendasi:** label UI sebagai `Dikirim ke printer` atau `Bridge accepted`, bukan `berhasil dicetak`, kecuali driver memberi acknowledgement nyata. Pertahankan tombol test print fisik dan dokumentasikan batas ini pada status/operasional. Untuk serial, pastikan `drain` juga tidak disamakan dengan bukti kertas keluar.

### P2 — Offline receipt tidak diberi penanda pending/offline pada isi struk

**Lokasi:** `src/pages/pos/POSKasirPage.tsx:520–534`, `src/lib/receiptDomain.ts:23–53`

Alur offline menampilkan status lokal pada dialog, tetapi `LastSale` offline dikonversi ke `ReceiptData` yang tidak membawa flag offline/pending. Builder receipt tidak menambahkan penanda bahwa transaksi belum tercatat di server.

**Dampak:** struk yang dicetak dapat terlihat seperti transaksi final, padahal pembayaran tunai masih menunggu sinkronisasi. Jika sinkronisasi kemudian konflik/gagal, bukti fisik tidak menjelaskan statusnya.

**Rekomendasi:** tambahkan `isOffline`/`syncStatus` ke kontrak receipt dan tampilkan `PENDING SYNC / TRANSAKSI OFFLINE` pada thermal, browser, dan PDF. Pastikan penanda hilang hanya pada reprint dari transaksi yang sudah benar-benar tersinkron.

### P2 — Tidak ada retry otomatis atau recovery lintas lifecycle untuk print outbox

**Lokasi:** `src/lib/printOutbox.ts:87–103`, `src/pages/pos/POSPengaturanPage.tsx:187–196`

Outbox bertahan di `localStorage` dan gagal job diberi status `failed`, tetapi pemrosesan ulang hanya dipanggil oleh tombol **Coba ulang antrean**. Tidak ditemukan pemanggilan global pada `online`, `visibilitychange`, startup POS, atau service worker untuk mencoba ulang secara otomatis.

**Dampak:** kasir dapat mengira antrean akan pulih sendiri setelah printer/bridge dinyalakan, padahal job menunggu tindakan manual di halaman pengaturan.

**Rekomendasi:** flush saat POS boot, saat event `online`, dan setelah koneksi printer berhasil; gunakan backoff terbatas agar tidak membuat loop. Tampilkan badge antrean di shell POS, bukan hanya di halaman pengaturan. Pertahankan retry eksplisit untuk menghindari duplikasi saat acknowledgement printer tidak pasti.

### P2 — Print Bridge tidak memiliki autentikasi jika binding/CORS diperlebar

**Lokasi:** `print-bridge/src/server.mjs:10–14`, `29–40`, `124–163`

Default binding `127.0.0.1` dan allowlist origin adalah keputusan yang benar. Namun server tidak memvalidasi `x-print-bridge-token`, meskipun header tersebut diumumkan dalam CORS. Jika operator menjalankan `HOST=0.0.0.0` atau `ALLOWED_ORIGIN=*`, endpoint `/jobs`, `/printers`, dan `/jobs/:id` dapat dipakai tanpa autentikasi; `/jobs` juga mengekspos payload Base64 receipt.

**Dampak:** perangkat jaringan lain atau halaman berbahaya dapat mengirim pekerjaan ke printer atau membaca riwayat job jika service terekspos.

**Rekomendasi:** jangan mengandalkan CORS sebagai autentikasi. Tolak request tanpa token saat bind non-loopback, validasi token pada semua endpoint sensitif, batasi `/jobs` hanya untuk status minimal, dan dokumentasikan mode loopback sebagai satu-satunya mode produksi default.

## 4. Hal yang sudah baik

- `receiptPrintContract.ts` menjadi jalur bersama untuk checkout, reprint, dan retry.
- Job disimpan di outbox sebelum printer dicoba.
- `jobId` digunakan untuk mencegah duplikasi pada transaksi normal.
- Ada fallback browser ketika bridge/native printer gagal.
- Print Bridge default bind ke loopback dan CORS tidak wildcard secara default.
- Ada persistence job bridge dan recovery job `queued`/`printing` saat service restart.
- Ada test untuk bridge health, timeout, JSON error, browser fallback, Android print service, QR print, dan hook receipt.
- Pengaturan menyediakan test print, pilihan 58/80 mm, jumlah salinan, koneksi USB/Bluetooth/WiFi, Android print service, dan retry antrean.

## 5. Verifikasi yang dijalankan

Perintah yang dijalankan tanpa mengubah kode:

```bash
pnpm vitest run \
  src/lib/receiptPrintContract.test.ts \
  src/lib/printBridgeClient.test.ts \
  src/hooks/usePOSReceipt.test.ts \
  src/lib/androidPrintService.test.ts \
  src/lib/posQrPrint.test.ts
```

Hasil: **5 test files passed, 13 tests passed**.

TypeScript check (`pnpm exec tsc --noEmit`) **lulus** (exit code 0).

## 6. Prioritas perbaikan

1. **P1:** perbaiki ID/job lifecycle cetak ulang dan tambah test dua kali cetak ulang.
2. **P1:** scope pengaturan printer ke tenant + outlet + device.
3. **P2:** samakan ukuran browser/PDF fallback dengan 58/80 mm.
4. **P2:** beri label offline/pending pada receipt.
5. **P2:** tambahkan retry outbox saat boot/online/koneksi printer.
6. **P2:** tambahkan autentikasi bridge jika ada kemungkinan binding selain loopback.
7. Lakukan UAT pada printer USB, Bluetooth BLE, Android Print Service, dan LAN/TCP nyata.

## 7. Keputusan audit

**Status fitur print POS: Perlu perbaikan sebelum production sign-off.**

Test otomatis saat ini cukup untuk memvalidasi kontrak client dan alur mock, tetapi belum cukup untuk menyatakan:

- cetak ulang benar-benar menghasilkan salinan baru;
- konfigurasi aman untuk multi-outlet/multi-tenant;
- layout fallback benar pada 58 mm;
- status `printed` sesuai keluaran kertas;
- receipt offline tidak menyesatkan;
- printer fisik dan recovery setelah restart benar-benar berfungsi.
