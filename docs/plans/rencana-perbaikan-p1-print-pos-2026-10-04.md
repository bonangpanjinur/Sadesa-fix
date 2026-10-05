# Rencana Perbaikan P1 Fitur Print POS

**Tanggal:** 4 Oktober 2026  
**Referensi audit:** [`docs/audits/audit-print-pos-2026-10-04.md`](../audits/audit-print-pos-2026-10-04.md)  
**Status:** Implementasi selesai di workspace; UAT printer fisik dan rollout produksi masih diperlukan

## 1. Tujuan

Memperbaiki dua temuan P1 yang dapat menyebabkan kasir menerima informasi keberhasilan yang keliru atau mencetak ke konfigurasi printer yang salah:

1. **Cetak ulang menjadi no-op** karena memakai `jobId` yang sama dengan percobaan sebelumnya.
2. **Konfigurasi printer global** karena hanya disimpan pada satu key `localStorage`, tanpa isolasi tenant, outlet, dan perangkat.

Target akhirnya:

- setiap aksi reprint yang disetujui menghasilkan satu percobaan print baru;
- idempotensi tetap mencegah duplikasi transaksi, tetapi tidak menghalangi reprint yang disengaja;
- konfigurasi printer aktif selalu cocok dengan tenant dan outlet yang sedang digunakan;
- konfigurasi lama tetap dapat dimigrasikan tanpa membuat POS kehilangan akses printer secara diam-diam;
- status job dan error dapat ditelusuri berdasarkan transaksi, outlet, perangkat, dan percobaan print.

## 2. Prinsip desain

| Prinsip | Keputusan |
|---|---|
| Idempotensi penjualan | `saleId` dan request key transaksi tidak berubah; reprint tidak pernah membuat penjualan baru |
| Idempotensi print normal | Cetak otomatis untuk satu transaksi tetap memakai job ID deterministik agar refresh/re-render tidak mencetak duplikat |
| Reprint eksplisit | Setiap klik **Cetak Ulang** membuat `attemptId` baru dan job baru |
| Scope konfigurasi | `tenantId + outletId + deviceId`, dengan fallback migrasi satu kali dari key legacy |
| Keamanan data | Jangan menyalin konfigurasi tenant/outlet lain ke scope aktif tanpa konfirmasi atau migrasi terkontrol |
| Kegagalan print | Job gagal tetap dapat dicoba ulang; jangan mengubah status transaksi atau membuat transaksi baru |
| UX status | Bedakan `queued`, `printing`, `printed/accepted`, dan `failed`; jangan menyatakan settlement atau keberhasilan transaksi berubah karena print |

## 3. P1-A — Perbaikan cetak ulang

### 3.1 Masalah saat ini

`POSTransaksiPage` membuat ID seperti:

```ts
receipt:reprint:${selected.id}:${selected.created_at}
```

`enqueueReceiptData()` tidak menambahkan job jika ID tersebut sudah ada. Akibatnya, reprint kedua dapat membaca job lama berstatus `printed`, melewati pengiriman ke printer, lalu tetap mengembalikan status sukses.

### 3.2 Desain target

Pisahkan tiga identitas:

```ts
interface PrintAttemptIdentity {
  saleId: string;       // identitas transaksi canonical
  printIntent: 'auto' | 'manual' | 'reprint' | 'retry';
  attemptId: string;    // unik per percobaan print
}
```

- **Auto-print pertama:** tetap deterministik, misalnya `receipt:${saleId}`.
- **Tombol Cetak Struk manual pada dialog sukses:** gunakan job deterministik yang sama hanya jika tujuannya mencegah double-click pada aksi yang sama.
- **Cetak ulang:** selalu gunakan `crypto.randomUUID()` atau ID monotonic baru:

```ts
receipt:reprint:${saleId}:${attemptId}
```

- **Retry job gagal:** dapat memakai job ID yang sama bila retry memang melanjutkan job yang belum `printed`. UI harus membedakan retry dari reprint baru.

### 3.3 Perubahan yang direncanakan

1. Tambahkan helper domain, misalnya:
   - `createReceiptPrintJobId(saleId)` untuk print normal;
   - `createReceiptReprintJobId(saleId, attemptId)` untuk reprint;
   - `createReceiptRetryId(jobId)` bila diperlukan untuk observability, tanpa membuat receipt baru.
2. Ubah `POSTransaksiPage.reprintReceipt()` agar menghasilkan `attemptId` baru setiap aksi reprint.
3. Pastikan `printReceiptWithContract()` tidak menganggap job lama berstatus `printed` sebagai keberhasilan untuk job baru.
4. Tambahkan metadata pada job:
   - `printIntent`;
   - `attemptId`;
   - `requestedAt`;
   - optional `requestedBy`/kasir bila tersedia.
5. Pertahankan `saleId`, `saleNumber`, `outletId`, dan snapshot receipt yang sama dengan transaksi canonical.
6. Perbarui toast/UI:
   - `Struk dikirim untuk dicetak ulang` saat job baru diterima;
   - `Percobaan cetak ulang gagal; transaksi tidak berubah` saat gagal;
   - hindari toast `berhasil dicetak` jika hanya browser/bridge menerima job.

### 3.4 Acceptance criteria P1-A

- Klik **Cetak Ulang** dua kali pada transaksi yang sama menghasilkan dua `jobId` berbeda.
- Kedua job mengandung `saleId` yang sama.
- Tidak ada insert/update ke tabel penjualan saat reprint.
- Jika job pertama `printed`, job kedua tetap dikirim ke bridge/printer.
- Jika job pertama `failed`, kasir dapat memilih **Coba lagi** untuk melanjutkan job lama atau **Cetak ulang** untuk membuat attempt baru; kedua tindakan tidak ambigu.
- Double-click cepat pada satu aksi tidak menghasilkan dua job kecuali memang dua aksi reprint yang terpisah sudah dikonfirmasi/diterima UI.
- Reprint tidak mengubah stok, pembayaran, laporan, atau status transaksi.

### 3.5 Test P1-A

**Unit/domain**

- ID print normal stabil untuk `saleId` yang sama.
- ID reprint selalu unik.
- ID berbeda tetap mempertahankan `saleId` dan `outletId`.

**Contract/component**

- job `printed` lama tidak membuat reprint baru dianggap selesai tanpa flush.
- bridge dipanggil satu kali untuk setiap reprint baru.
- failure lalu retry tidak membuat sale kedua.
- browser fallback tetap menyelesaikan attempt yang benar.

**E2E mock**

1. Selesaikan transaksi.
2. Auto-print sukses.
3. Buka histori transaksi.
4. Reprint pertama → assert job A diterima.
5. Reprint kedua → assert job B diterima dan `jobA !== jobB`.
6. Verifikasi hanya satu transaksi canonical yang ada.

**UAT perangkat**

- Cetak pertama.
- Cabut kertas atau matikan printer.
- Jalankan reprint dan pastikan job terlihat gagal/queued.
- Nyalakan kembali printer.
- Jalankan retry, lalu lakukan reprint kedua untuk memastikan tidak terjadi deduplikasi keliru.

## 4. P1-B — Isolasi konfigurasi printer

### 4.1 Masalah saat ini

`getPrinterSettings()` dan `savePrinterSettings()` menggunakan key global:

```ts
pos_printer_settings
```

Akibatnya konfigurasi terakhir dapat terbawa ketika perangkat yang sama dipakai oleh outlet atau tenant berbeda.

### 4.2 Desain target

Gunakan key berscope:

```text
pos_printer_settings:v2:{tenantId}:{outletId}:{deviceId}
```

`deviceId` harus berupa identifier acak yang dibuat sekali di perangkat dan tidak memuat email, user ID, atau data sensitif:

```text
pos_device_id:v1 → crypto.randomUUID()
```

Model akses yang disarankan:

```ts
getPrinterSettings({ tenantId, outletId }): PrinterSettings
savePrinterSettings({ tenantId, outletId }, settings): void
```

Aturan:

- tenant/outlet aktif wajib berasal dari `POSContext`, bukan input bebas dari URL;
- jika belum ada konfigurasi scoped, gunakan default aman dan tampilkan status **Belum dikonfigurasi untuk outlet ini**;
- jangan otomatis mengambil konfigurasi outlet lain;
- konfigurasi printer tidak perlu disimpan di database untuk MVP jika printer memang device-local, tetapi scope key wajib diterapkan di browser;
- bila organisasi membutuhkan konfigurasi terpusat, desain database terpisah harus mencakup RLS dan approval device.

### 4.3 Migrasi key legacy

Migrasi dilakukan sekali saat membaca konfigurasi:

1. Coba baca key v2 untuk tenant + outlet + device aktif.
2. Jika ada, gunakan key v2.
3. Jika belum ada, cek key legacy `pos_printer_settings`.
4. Jika key legacy ada:
   - salin ke key v2 aktif;
   - beri marker `migratedFromLegacy: true` dan `migratedAt` di metadata lokal, bukan di payload printer bila tidak diperlukan;
   - tampilkan banner **Konfigurasi printer lama ditemukan untuk perangkat ini. Verifikasi outlet aktif sebelum mencetak.**
5. Jangan hapus key legacy pada versi pertama; lakukan cleanup setelah periode observasi atau setelah pengguna menekan **Konfirmasi konfigurasi ini**.
6. Jika tenant/outlet berubah, jangan membawa konfigurasi scoped sebelumnya.

Perhatian: migrasi legacy tidak dapat membuktikan bahwa konfigurasi lama memang milik tenant/outlet aktif. Karena itu migration harus bersifat reversible dan memerlukan verifikasi test print.

### 4.4 Perubahan yang direncanakan

1. Tambahkan `deviceId` helper yang aman dan stabil di localStorage.
2. Ubah API settings agar menerima scope `{ tenantId, outletId }`.
3. Perbarui seluruh pemanggilan:
   - `usePOSReceipt`;
   - `receiptPrintContract`;
   - `printOutbox`;
   - `printBridgeClient`;
   - `POSPengaturanPage`;
   - `UniversalPrinter`.
4. Pastikan `usePOSReceipt` memakai settings untuk tenant/outlet aktif saat membuat receipt dan memilih channel.
5. Simpan scope metadata pada job outbox agar antrean lama tidak dicetak ke konfigurasi outlet baru secara keliru.
6. Saat outlet berganti:
   - reload settings scoped;
   - reset status koneksi UI;
   - jangan flush antrean outlet lama ke printer baru tanpa filter outlet.
7. Tampilkan scope aktif pada halaman pengaturan, misalnya `Printer untuk: Toko A · Outlet Utama`.
8. Tambahkan guard sebelum auto-print jika scope belum terverifikasi: browser fallback boleh tersedia, tetapi thermal auto-print harus diberi status jelas.

### 4.5 Acceptance criteria P1-B

- Tenant A dan tenant B pada perangkat yang sama tidak membaca konfigurasi printer satu sama lain.
- Outlet A dan outlet B dalam tenant yang sama dapat memiliki IP, printer, paper width, salinan, dan auto-print berbeda.
- Mengganti outlet mereset status koneksi dan memuat konfigurasi outlet tujuan.
- Job outbox outlet A tidak otomatis dikirim saat outlet B sedang aktif.
- Migrasi dari key legacy tidak menghapus data sebelum konfigurasi scoped diverifikasi.
- Logout/login tenant berbeda tidak mempertahankan auto-print atau printer sebelumnya secara salah.
- Test print menampilkan scope tenant/outlet yang sedang aktif pada UI/log lokal.

### 4.6 Test P1-B

**Unit**

- key v2 deterministik untuk scope yang sama.
- key berbeda untuk tenant berbeda, outlet berbeda, dan device berbeda.
- `get` scoped tidak membaca key tenant/outlet lain.
- device ID stabil setelah reload tetapi berbeda pada profile/device berbeda.

**Migration**

- key legacy disalin ke scope aktif tepat satu kali.
- key legacy rusak/tidak valid kembali ke default tanpa crash.
- konfigurasi scoped yang sudah ada mengalahkan key legacy.
- migrasi tidak menghapus key legacy sebelum konfirmasi.

**Component**

- halaman pengaturan menampilkan outlet aktif.
- pergantian outlet mengubah settings dan reset status koneksi.
- auto-print memakai settings outlet aktif.

**Outbox**

- job outlet A tidak ikut `flushReceiptOutbox()` ketika filter scope outlet B aktif.
- job lama tetap dapat dilihat dan dipulihkan setelah kembali ke outlet A.
- konfigurasi printer berubah setelah job dibuat tidak mengubah snapshot sale, tetapi aturan copies/channel terdokumentasi dan teruji.

**Multi-tenant E2E**

1. Login/siapkan tenant A, outlet A, simpan printer A.
2. Ganti ke outlet B, simpan printer B.
3. Kembali ke outlet A, pastikan printer A kembali.
4. Ganti tenant, pastikan tidak ada konfigurasi A yang tampil.
5. Buat job pending pada outlet A, pindah ke outlet B, pastikan job A tidak dicetak.

## 5. Urutan implementasi

### Fase 0 — Baseline dan observability

- Tambahkan test reproduksi untuk dua P1 sebelum mengubah logic.
- Catat shape job saat ini, tanpa menulis isi receipt lengkap ke log produksi.
- Pastikan `git status` bersih dari perubahan yang tidak terkait.

**Exit gate:** test reproduksi gagal dengan alasan yang tepat dan tidak ada perubahan data produksi.

### Fase 1 — Perbaikan P1-A reprint

- Implementasi ID attempt dan metadata print intent.
- Update contract, outbox, histori transaksi, dan tests.
- Uji mock bridge/browser.

**Exit gate:** acceptance criteria P1-A lulus.

### Fase 2 — Scope konfigurasi P1-B

- Implementasi device ID dan key v2.
- Migrasi legacy read-only/copy-on-read.
- Propagasi scope melalui hook, outbox, printer router, dan halaman pengaturan.
- Tambahkan test tenant/outlet switching.

**Exit gate:** acceptance criteria P1-B lulus dan tidak ada cross-scope read.

### Fase 3 — UAT perangkat

Matriks minimum:

| Jalur | Perangkat/skenario |
|---|---|
| USB | Chrome/Edge desktop, printer serial/USB yang didukung |
| Bluetooth | BLE printer yang mendukung profile yang diimplementasikan |
| Android | Android Print Service pada tablet target |
| LAN | Print Bridge + printer TCP pada jaringan lokal |
| Browser fallback | popup diizinkan dan popup diblokir |
| Recovery | printer mati, bridge restart, browser reload, kertas habis |
| Scope | dua outlet, dua tenant, satu perangkat bersama |

**Exit gate:** bukti nomor transaksi, job ID, outlet, status job, dan hasil fisik tersimpan untuk setiap skenario.

### Fase 4 — Rollout bertahap

1. Aktifkan job metadata dan scoped settings di internal/staging.
2. Pantau:
   - rasio job failed;
   - reprint yang menghasilkan job berbeda;
   - pending outbox per outlet;
   - konflik scope/migrasi;
   - fallback browser;
   - komplain cetak ganda/tidak tercetak.
3. Rollout ke pilot terbatas satu outlet per merchant.
4. Perluas setelah satu siklus operasional penuh tanpa temuan P1 baru.
5. Hapus key legacy hanya pada versi berikutnya setelah migrasi berhasil dan rollback window berakhir.

## 6. Rencana rollback

### P1-A

- Pertahankan pembacaan job lama untuk retry.
- Jika UI/contract baru bermasalah, matikan tombol reprint baru melalui feature flag dan tetap tampilkan transaksi.
- Jangan menghapus job outbox atau mengubah data transaksi.

### P1-B

- Tetap dukung pembacaan key legacy selama satu release penuh.
- Jika scoped settings gagal dibaca, fallback ke default aman dan tampilkan banner konfigurasi belum diverifikasi; jangan diam-diam memakai scope lain.
- Jangan menghapus key v2 saat rollback agar konfigurasi dapat dipulihkan.

## 7. Definition of Done

Rencana ini dianggap selesai hanya jika:

- [ ] Reprint kedua benar-benar mengirim job baru dengan `jobId` berbeda.
- [ ] Tidak ada transaksi kedua setelah reprint atau retry.
- [ ] Settings tenant/outlet/device terisolasi dan teruji.
- [ ] Job outbox memiliki scope outlet dan tidak salah flush lintas outlet.
- [ ] Migrasi legacy terdokumentasi dan reversible.
- [ ] Test unit, contract, component, dan E2E mock lulus.
- [ ] UAT printer fisik selesai untuk jalur yang diklaim didukung.
- [ ] Dokumen runbook kasir diperbarui untuk reprint, retry, dan pergantian outlet.
- [ ] Status UI tidak mengklaim kertas tercetak bila hanya bridge menerima data.


## 8. Status implementasi 4 Oktober 2026

- [x] Reprint menggunakan attempt ID unik dan job ID baru.
- [x] Metadata `printIntent`, `attemptId`, dan `requestedAt` ditambahkan pada receipt/job.
- [x] Konfigurasi printer menggunakan scope tenant + outlet + device ID dengan migrasi key legacy.
- [x] Outbox pending count dan retry difilter berdasarkan scope outlet aktif.
- [x] Router USB/Bluetooth, Print Bridge, browser contract, kasir, dan halaman pengaturan memakai scope receipt aktif.
- [x] Regression test identitas job reprint ditambahkan.
- [x] TypeScript, lint, test suite, dan production build lulus.
- [ ] UAT printer fisik dan verifikasi output kertas masih harus dilakukan pada perangkat target.
