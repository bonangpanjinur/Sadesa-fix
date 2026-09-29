# Dokumentasi Perubahan: GPS Hanya Wajib Saat Pemesanan

**Tanggal:** 29 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Commit:** [`317c6e709a871561867804c2bad521323a682f7d`](https://github.com/bonangpanjinur/Sadesa-fix/commit/317c6e709a871561867804c2bad521323a682f7d)  
**Pesan commit:** `fix: scope GPS requirement to order actions`

## Ringkasan

Perubahan ini memperbaiki dua hal pada alur transportasi dan pengiriman:

1. **GPS tidak lagi menjadi syarat global saat aplikasi dibuka.** Pengguna tetap dapat membuka beranda, menjelajah produk, melihat layanan, dan membaca halaman lain tanpa mengaktifkan lokasi.
2. **GPS menjadi syarat pada tindakan yang memang membutuhkan alamat/lokasi.** Ketika pengguna benar-benar mengirim pesanan makanan atau membuat booking ojek/kurir, aplikasi meminta posisi GPS terbaru. Jika GPS gagal atau izin ditolak, order tidak dikirim ke server.

Perubahan ini menghindari kesan bahwa aplikasi terus-menerus melacak pengguna, tetapi tetap menjaga akurasi alamat dan keamanan operasional ketika order dibuat.

## Perilaku pengguna

### Fitur yang tetap dapat digunakan tanpa GPS

- Membuka aplikasi dan beranda.
- Menjelajah katalog, toko, wisata, dan layanan.
- Membaca riwayat atau halaman informasi yang tidak membutuhkan lokasi baru.
- Melihat form booking sebelum menekan tombol final pemesanan.

### Fitur yang meminta GPS

| Alur | Kapan GPS diminta | Jika GPS gagal |
|---|---|---|
| Checkout makanan dengan pengiriman | Saat submit checkout | Order tidak dibuat dan pengguna mendapat pesan untuk mengaktifkan GPS |
| Checkout makanan dengan pickup/ambil sendiri | Tidak wajib | Checkout tetap dapat dilanjutkan tanpa GPS |
| Booking ojek | Saat konfirmasi akhir booking | Permintaan ojek tidak dibuat |
| Booking kurir/barang | Saat melanjutkan booking | Order kurir tidak dibuat |

Pada halaman booking ojek, tombol lokasi tetap tersedia sebagai pilihan untuk mengisi titik jemput. Namun membuka halaman tersebut tidak otomatis memunculkan prompt GPS.

## Implementasi teknis

### Helper lokasi terpusat

File baru `src/lib/requiredLocation.ts` menyediakan:

```ts
requestRequiredLocation(): Promise<{ lat: number; lng: number } | null>
```

Karakteristik helper:

- Meminta lokasi terbaru dengan `enableHighAccuracy: true`.
- Tidak menggunakan cache lokasi lama (`maximumAge: 0`).
- Memiliki timeout 10 detik.
- Mengembalikan `null` jika browser tidak mendukung geolocation atau pengguna menolak izin.
- Tidak memanggil GPS secara global ketika aplikasi baru dimuat.

### Checkout makanan

`src/pages/CheckoutPage.tsx` memanggil helper sebelum membuat checkout marketplace apabila:

```ts
deliveryType !== 'PICKUP'
```

Dengan demikian, pengiriman ke alamat membutuhkan GPS, sedangkan pickup tidak.

### Booking ojek

`src/pages/ride/RideBookingPage.tsx` memvalidasi GPS tepat sebelum memanggil RPC:

```text
requestRequiredLocation()
  -> gagal: tampilkan “GPS wajib diaktifkan”
  -> berhasil: lanjutkan create_ride_request
```

Pemanggilan GPS otomatis saat halaman booking dibuka dihapus. Pengguna hanya menerima prompt pada tindakan pemesanan final atau ketika menekan tombol lokasi.

### Booking kurir/barang

`src/pages/transport/CourierBookingPage.tsx` menjalankan validasi GPS sebelum `create_courier_order`. Jika lokasi tidak tersedia, RPC tidak dipanggil sehingga tidak ada order kosong atau order tanpa validasi posisi.

### Perbaikan inbox ojek

Commit yang sama juga menyelaraskan inbox ojek dengan model offer server-side:

- Dashboard hanya menghitung `ride_request_offers` berstatus `PENDING` milik kurir yang sedang login.
- Halaman ojek hanya mengambil offer yang ditargetkan ke kurir tersebut dan belum kedaluwarsa.
- Realtime subscription tidak lagi mendengarkan semua ride `SEARCHING` secara global.
- Regression test memastikan query lama yang mengambil semua ride `SEARCHING` tidak kembali digunakan.

Perbaikan ini mencegah order tampil kepada kurir yang bukan target offer dan kemudian gagal ketika tombol Terima ditekan.

## File yang berubah

| File | Perubahan |
|---|---|
| `src/App.tsx` | Menghapus global permission lock dari seluruh aplikasi |
| `src/lib/requiredLocation.ts` | Helper permintaan GPS on-demand |
| `src/pages/CheckoutPage.tsx` | GPS wajib untuk delivery checkout, tidak untuk pickup |
| `src/pages/ride/RideBookingPage.tsx` | GPS wajib sebelum membuat request ojek; tidak prompt saat halaman dibuka |
| `src/pages/transport/CourierBookingPage.tsx` | GPS wajib sebelum membuat order kurir |
| `src/pages/CourierDashboardPage.tsx` | Counter permintaan ojek scoped ke offer aktif kurir |
| `src/pages/courier/CourierRidesPage.tsx` | Inbox dan realtime scoped ke offer target kurir |
| `src/lib/nearestCourierDispatch.test.ts` | Regression contract untuk targeted courier offer |

## Kontrak keamanan dan privasi

- Website tidak dapat mengubah toggle GPS Android secara langsung. Browser tetap menampilkan permission prompt resmi atau meminta pengguna mengubah pengaturan situs/perangkat.
- Aplikasi hanya meminta lokasi ketika ada tindakan yang membutuhkan lokasi.
- Lokasi yang diminta oleh helper digunakan untuk memvalidasi kesiapan alur order; data bisnis tetap divalidasi oleh RPC server-side.
- Pickup tidak dipaksa memakai GPS karena tidak membutuhkan pengantaran ke alamat.
- Notifikasi push merupakan concern terpisah dari permission GPS. Permission notifikasi tidak digunakan sebagai alasan untuk mengunci aktivitas browsing.

## Validasi

Validasi pada commit ini:

- `pnpm exec tsc --noEmit` — **lulus**
- ESLint file terkait — **lulus**
- `pnpm build` — **lulus**
- `git diff --check` — **lulus**
- Regression test dispatch yang relevan — **11 test lulus**

## Acceptance criteria

Perubahan dianggap benar apabila:

- Pengguna dapat membuka dan menjelajah aplikasi tanpa mengaktifkan GPS.
- Checkout delivery gagal dengan pesan yang jelas jika GPS ditolak atau dimatikan.
- Checkout pickup tidak gagal hanya karena GPS tidak aktif.
- Booking ojek dan kurir meminta GPS pada tindakan final pemesanan.
- Tidak ada RPC pembuatan order yang dipanggil setelah validasi GPS gagal.
- Kurir hanya melihat dan menerima offer yang memang ditargetkan ke akunnya.
