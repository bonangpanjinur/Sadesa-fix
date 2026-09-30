# Audit Fitur Ojek Penumpang dan Kurir

**Tanggal:** 29 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Scope:** sisi penumpang/pengirim, provider ojek/kurir, visibilitas pesanan berdasarkan jarak, penerimaan atomik, dan hilangnya penawaran setelah diambil provider lain.

## Kesimpulan eksekutif

Secara source code, kebutuhan inti sudah tersedia dan telah diperkuat:

1. **Ojek penumpang** hanya menawarkan satu pesanan kepada satu provider terdekat pada satu waktu.
2. Provider lain tidak dapat melihat pesanan tersebut karena RLS membaca `ride_request_offers` yang ditargetkan khusus ke provider itu.
3. Saat satu provider menerima, database mengunci proses acceptance sehingga hanya satu request concurrent yang berhasil.
4. **Kurir antar barang** menggunakan `delivery_assignments`/offer yang scoped ke `courier_id`; feed provider hanya mengembalikan offer milik provider yang sedang login.
5. Setelah order diterima, assignment lain tidak lagi berstatus `OFFERED`, sehingga tidak tampil sebagai penawaran aktif provider lain.

Perbaikan tambahan pada audit ini: inbox ojek provider sekarang memanggil `process_expired_ride_offers()` melalui heartbeat setiap 15 detik. Ini memastikan jika provider terdekat tidak merespons dalam 30 detik, offer dapat diteruskan ke provider eligible berikutnya tanpa menunggu aksi manual.

> **Status:** source siap untuk verifikasi staging. Belum ada bukti dari audit ini bahwa migration terbaru sudah diterapkan di database production/staging aktif.

## 1. Alur ojek penumpang

### Dari sisi penumpang

- `RideBookingPage` memanggil RPC `create_ride_request`, bukan insert langsung dari browser.
- Koordinat pickup dan tujuan dikirim untuk dihitung ulang di server.
- Penumpang melihat status melalui `RideTrackingPage` yang dibatasi `passenger_id = auth.uid()`.
- Pembatalan memakai RPC `cancel_ride`.
- Rating memakai RPC `submit_ride_rating` dan hanya tersedia setelah `COMPLETED`.

### Dari sisi provider ojek

Migration `20260929011000_nearest_courier_sequential_ride_dispatch.sql` menyediakan:

- Tabel `ride_request_offers`.
- Satu offer `PENDING` maksimum per ride melalui partial unique index.
- Satu percobaan per kombinasi ride/provider melalui unique constraint `(ride_id, courier_id)`.
- Masa berlaku offer 30 detik.
- Ranking provider berdasarkan jarak Haversine pickup ke lokasi provider.
- Syarat provider eligible: `APPROVED`, `ACTIVE`, `is_available = true`, lokasi diperbarui maksimal 90 detik, dan tidak sedang memiliki perjalanan aktif.
- Provider yang sudah pernah menerima offer untuk ride tersebut tidak dipilih ulang.
- Provider yang sedang memegang offer ride lain yang masih pending tidak dipilih untuk offer tambahan.

### Acceptance dan race condition

`accept_ride()` melakukan:

1. Advisory transaction lock untuk serialisasi dispatch/acceptance.
2. Verifikasi `p_courier_id` memang milik `auth.uid()`.
3. Lock row ride dengan syarat `status = 'SEARCHING'` dan `driver_id IS NULL`.
4. Verifikasi offer yang ditargetkan ke provider tersebut masih `PENDING` dan belum expired.
5. Update offer ke `ACCEPTED` dan ride ke `ACCEPTED` dalam transaksi.

Dengan kontrak ini, dua provider yang mencoba menerima request yang sama tidak dapat sama-sama berhasil.

## 2. Apakah pesanan hanya muncul pada ojek terdekat?

**Ya, untuk alur ojek penumpang.**

Query dispatch memilih satu kandidat dengan:

```sql
ORDER BY ranked.distance_km ASC, ranked.id ASC
LIMIT 1
```

Kemudian hanya membuat satu row `ride_request_offers` berstatus `PENDING`. Policy RLS provider hanya mengizinkan SELECT jika ada offer `PENDING` yang:

- `offer.ride_id = ride_requests.id`;
- `offer.expires_at > now()`;
- `offer.courier_id` terkait dengan `auth.uid()`;
- provider masih approved, active, available, dan memiliki lokasi terbaru;
- provider tidak sedang menjalankan ride lain.

Jadi provider kedua tidak sekadar disembunyikan oleh frontend; row ride memang tidak lolos RLS untuk provider tersebut.

## 3. Apakah penawaran hilang setelah diambil provider lain?

**Ya, secara server-side.**

Saat provider A berhasil menerima:

- ride berubah dari `SEARCHING` menjadi `ACCEPTED`;
- `driver_id` terisi provider A;
- offer A berubah menjadi `ACCEPTED`;
- policy provider hanya memperbolehkan ride `SEARCHING` dengan `driver_id IS NULL`;
- provider B tidak lagi mendapatkan ride tersebut pada query berikutnya maupun realtime refresh.

Jika provider B mengirim request lama/stale setelah itu, `accept_ride()` mengembalikan `false`, bukan mengambil alih ride.

## 4. Alur kurir antar barang

### Dari sisi pengirim/buyer

`CourierBookingPage`:

- Memvalidasi pickup, tujuan, penerima, nomor telepon, barang, berat, dan jarak maksimal 10 km di UI.
- Memanggil RPC `create_courier_order` untuk membuat order authoritative.
- Server menghitung ulang koordinat/jarak dan membuat dispatch/assignment.
- Buyer diarahkan ke halaman tracking setelah `order_id` terbentuk.

### Dari sisi provider kurir

- Feed offer memakai `get_courier_delivery_offers()`.
- RPC mengambil `courier_id` dari `auth.uid()`.
- Hanya assignment provider tersebut dengan `status = 'OFFERED'`, belum expired, dan order masih `ASSIGNED` yang dikembalikan.
- Provider menerima/menolak melalui `respond_delivery_offer()`.
- Transisi pickup, pengantaran, dan selesai memakai `courier_transition_order()` dengan ownership dan state guard.

Dengan begitu, provider lain tidak menerima offer yang sama hanya karena melakukan query order umum. Offer dibatasi pada assignment provider yang dituju.

## 5. Temuan residual dan prioritas

| ID | Prioritas | Temuan | Dampak | Rekomendasi |
|---|---:|---|---|---|
| AUD-01 | P0 | Migration 55 sudah ada di source, tetapi audit sandbox tidak terhubung ke database staging/production | Perilaku runtime belum terbukti identik dengan source | Apply migration melalui jalur deployment resmi, reload PostgREST schema, lalu jalankan smoke test dua provider |
| AUD-02 | P1 | Sebelumnya expiry offer ojek tidak memiliki pemanggil UI aktif yang terverifikasi | Provider terdekat yang diam 30 detik dapat menahan dispatch lebih lama dari yang diharapkan | **Sudah diperbaiki:** inbox `CourierRidesPage` menjalankan heartbeat expiry tiap 15 detik; untuk produksi jangka panjang tetap lebih baik memakai worker/scheduler server |
| AUD-03 | P1 | Dispatch ojek bergantung pada session provider aktif untuk menjalankan expiry processor | Jika tidak ada provider online, offer berikutnya baru maju saat ada session aktif | Tambahkan scheduler/service worker terjadwal sebagai fallback dan metrik `dispatch_lag_seconds` |
| AUD-04 | P1 | Broadcast notification masih menyebut alamat pickup lengkap pada pesan offer ojek | Provider yang belum menerima dapat memperoleh detail lokasi melalui notifikasi yang ditargetkan; perlu minimisasi data | Gunakan area/estimasi jarak pada notifikasi, buka alamat lengkap setelah acceptance jika kebijakan privasi mengharuskan |
| AUD-05 | P1 | Concurrency test database nyata belum dijalankan | Static contract test belum membuktikan dua session Supabase benar-benar menghasilkan tepat satu winner | Jalankan dua user provider authenticated secara paralel terhadap database staging |
| AUD-06 | P2 | Provider dapat berubah lokasi setelah offer dibuat | Jarak yang disimpan adalah jarak saat penawaran, bukan jaminan jarak real-time | Tampilkan timestamp lokasi dan validasi ulang saat accept; source saat ini sudah melakukan validasi freshness |

## 6. Perubahan yang dilakukan pada audit ini

File yang diubah:

- `src/pages/courier/CourierRidesPage.tsx`
  - Memanggil `process_expired_ride_offers()` secara best-effort sebelum mengambil inbox.
  - Menambahkan `refetchInterval: 15_000`.
  - Error heartbeat tidak memblokir inbox lokal.
- `src/lib/nearestCourierDispatch.test.ts`
  - Menambahkan assertion bahwa inbox ojek benar-benar memanggil expiry processor.

## 7. Validasi lokal

| Pemeriksaan | Hasil |
|---|---:|
| Contract test dispatch terdekat + delivery status | **PASS — 2 test files, 9 tests** |
| Validasi migration | **PASS — 56 SQL deployment files** |
| Production build Vite | **PASS** |
| Dynamic RLS test | Belum dilakukan; membutuhkan database staging dan beberapa akun authenticated |
| Race acceptance dua provider | Belum dilakukan pada database nyata |

Ada warning non-blocking dari Tailwind tentang class `duration-[250ms]`; tidak berkaitan dengan alur order.

## 8. Test matrix staging yang wajib

1. Provider A lebih dekat daripada provider B: hanya A menerima offer awal.
2. Provider A menolak: offer B muncul setelah penolakan.
3. Provider A tidak merespons 30 detik: offer expired dan B menerima offer berikutnya.
4. Provider A dan B menekan terima bersamaan: tepat satu sukses.
5. Provider B mengirim `p_courier_id` A: ditolak.
6. Setelah A menerima: B tidak dapat SELECT ride dan `accept_ride()` B mengembalikan `false`.
7. Provider tidak aktif/approved, lokasi lebih dari 90 detik, atau sedang punya ride aktif: tidak dipilih.
8. Dua order baru bersamaan: satu provider tidak menerima dua pending offer sekaligus.
9. Kurir marketplace A menerima order: assignment tidak lagi muncul sebagai `OFFERED` pada provider lain.
10. Double click tombol Ambil: tetap satu assignment/acceptance.
11. Buyer membatalkan saat dispatch: offer ditutup dan tidak dapat diambil provider.
12. Realtime disconnect/reconnect: inbox melakukan refetch dan tidak menampilkan offer stale.

## Putusan audit

**Secara desain dan source, requirement “pesanan hanya untuk ojek terdekat” dan “hilang dari provider lain setelah diambil” sudah terpenuhi untuk ojek penumpang dan kurir antar barang.** Kontrol utama berada di database/RLS/RPC, bukan hanya penyaringan UI.

Sebelum production sign-off, masih wajib dibuktikan bahwa migration sudah aktif di database target dan concurrency/RLS test di atas lulus pada staging.
