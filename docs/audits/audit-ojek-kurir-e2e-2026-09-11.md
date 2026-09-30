# Audit End-to-End Pemesanan Ojek dan Kurir

**Tanggal:** 11 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Ruang lingkup:** pemesanan ojek penumpang, pencarian/acceptance driver, pengambilan penumpang, penyelesaian perjalanan, rating, pemesanan kurir marketplace, dispatch/offer, pickup barang, delivery, dan pembatasan jarak kurir.

## Ringkasan eksekutif

Audit menemukan bahwa alur **kurir marketplace** sudah memiliki fondasi server-side yang cukup baik: checkout menghitung jarak dari koordinat server, assignment dan offer memakai RPC, serta transisi status kurir dikunci berdasarkan courier yang ditugaskan. Namun, alur **ojek penumpang** belum setara tingkat pengamanannya. RLS masih mengizinkan penumpang dan courier melakukan `UPDATE` langsung terhadap seluruh baris `ride_requests` tanpa pembatasan kolom atau state transition di database. Dampaknya, aktor yang berwenang atas barisnya dapat berpotensi mengubah field sensitif seperti `driver_id`, tarif, jarak, timestamp, status, atau rating secara langsung melalui API PostgREST.

Selain itu, halaman booking kurir saat ini belum melakukan dispatch atau membuat order; tombol lanjut hanya menyimpan detail di UI dan menampilkan pesan bahwa dispatch belum aktif. Ini merupakan gap fungsional **P0/P1**, bukan sekadar isu UX.

Pembatasan jarak kurir marketplace telah ditetapkan **10 km** untuk `delivery_type = 'INTERNAL'`, dengan pembatasan tambahan kabupaten/kota dan kecamatan apabila metadata tersedia. Kontrol ini berlaku pada trigger order, sedangkan checkout terbaru menghitung Haversine distance dari koordinat merchant dan tujuan. Kontrol tersebut perlu diuji di staging/live untuk memastikan migration terbaru benar-benar telah diterapkan.

## Peta alur yang diaudit

| Tahap | Ojek penumpang | Kurir marketplace | Hasil audit |
|---|---|---|---|
| Pemesanan | `RideBookingPage` membuat `ride_requests` secara langsung | Checkout memakai `create_marketplace_checkout` | Ojek masih client-authoritative; marketplace lebih baik |
| Pencarian/dispatch | Trigger memberi notifikasi semua courier aktif; driver mengambil dengan `accept_ride` | Merchant/admin membuat offer melalui RPC | Acceptance ojek atomik, tetapi otorisasi parameter belum lengkap |
| Pengambilan | UI courier mengubah `ACCEPTED -> PICKED_UP` | `courier_transition_order` mengunci courier dan state | Marketplace memiliki guard server-side; ojek tidak konsisten |
| Perjalanan/delivery | UI mengubah `PICKED_UP -> IN_TRANSIT -> COMPLETED` | `PICKED_UP -> SENT -> DELIVERED` | Ojek dapat memakai direct update melalui RLS |
| Rating | `RideTrackingPage` update langsung ke `ride_requests` | `submit_courier_rating` RPC memeriksa buyer, status selesai, courier | Rating ojek belum memiliki guard server-side ekuivalen |
| Batas jarak | Tidak ditemukan validasi batas jarak lokal yang setara pada ride penumpang | Internal delivery dibatasi 10 km + wilayah administratif | Batas kurir marketplace ada; batas ride penumpang belum terlihat |

## Temuan prioritas

### OJ-01 — P0: Penumpang dapat melakukan direct update terhadap field sensitif ride

**Bukti:** `supabase/bootstrap/06_20260509000000_to_20260823071000.sql:2289-2291` membuat policy `Passengers can update own rides` dengan kondisi hanya `passenger_id = auth.uid()` dan status awal `SEARCHING` atau `ACCEPTED`. Policy tidak membatasi kolom yang boleh diubah. `RideTrackingPage.tsx:222-230` melakukan update status pembatalan langsung hanya berdasarkan `id`; tidak ada RPC ownership/state transition khusus.

**Risiko:** penumpang dapat mencoba mengubah `driver_id`, `estimated_fare`, `final_fare`, koordinat, timestamp, status ke nilai tidak valid, atau field lain yang ikut terbuka pada update. RLS memastikan kepemilikan baris, tetapi tidak memastikan integritas bisnis per kolom dan transisi.

**Perbaikan wajib:** cabut direct `UPDATE` dari client untuk ride; sediakan RPC terpisah `cancel_ride` yang memeriksa `passenger_id`, status yang diizinkan, waktu pembatalan, dan biaya pembatalan. Gunakan RPC `transition_ride_status` untuk courier dengan state machine eksplisit. Jika direct update tetap diperlukan, gunakan grant column-level dan trigger yang menolak perubahan field sensitif oleh non-admin.

### OJ-02 — P0: Courier dapat direct update ride yang ditugaskan tanpa guard kolom/state

**Bukti:** policy `Couriers can update assigned rides` pada `supabase/bootstrap/06_20260509000000_to_20260823071000.sql:2284-2286` hanya memeriksa `driver_id` terkait user. Fallback di `src/pages/courier/CourierRidesPage.tsx:297-304` melakukan update langsung dengan predicate `id`, `driver_id`, dan status lama. Predicate mencegah sebagian race condition, tetapi tidak mencegah perubahan field lain yang dikirim oleh client.

**Risiko:** courier yang sah atas satu ride dapat memodifikasi tarif, koordinat, passenger metadata, rating, atau status ke nilai yang tidak sesuai alur jika endpoint langsung dipanggil dengan payload tambahan.

**Perbaikan wajib:** hapus fallback direct update setelah RPC tersedia; buat RPC yang memeriksa identitas courier dari `auth.uid()`, status saat ini, status tujuan, serta mengisi timestamp di database. Tambahkan `SELECT ... FOR UPDATE` dan audit history.

### OJ-03 — P0: Rating ojek dapat dikirim sebelum perjalanan selesai dan berpotensi diubah berulang

**Bukti:** `src/pages/ride/RideTrackingPage.tsx:258-268` menulis `rating` dan `rating_comment` langsung ke `ride_requests` hanya dengan `.eq('id', ride.id)`. Tidak ada pengecekan client terhadap status selesai pada operasi database, tidak ada RPC rating ride yang memeriksa `passenger_id`, dan tidak ada unique constraint yang terlihat untuk satu rating per ride. Sebaliknya, rating kurir marketplace memiliki guard kuat di `supabase/bootstrap/49_20260911005000_review_refund_rating_hardening.sql:186-205`: buyer harus cocok, status harus selesai, courier harus cocok, rating 1–5, lalu dicatat melalui RPC.

**Risiko:** rating prematur, rating overwrite, manipulasi skor, dan ketidakselarasan antara rating ojek dan rating kurir marketplace.

**Perbaikan wajib:** buat `submit_ride_rating(p_ride_id, p_rating, p_comment)` SECURITY DEFINER; periksa passenger, status `COMPLETED`, driver tidak null, rating 1–5, dan `rating IS NULL`. Tambahkan unique constraint `(ride_request_id)` pada tabel rating terpisah atau `ride_requests.rating_submitted_at` dengan update atomik. Jangan simpan rating melalui direct table update.

### OJ-04 — P1: Booking kurir belum menyelesaikan pemesanan atau dispatch

**Bukti:** `src/pages/transport/CourierBookingPage.tsx:304-320` hanya memeriksa kelengkapan input lalu menampilkan toast: “Pencarian mitra kurir akan tersedia setelah dispatch kurir diaktifkan.” Tidak ada insert order, pemanggilan checkout, pembuatan delivery offer, atau navigasi ke order yang dibuat.

**Dampak:** pengguna dapat mengisi pickup, tujuan, penerima, barang, berat, dan COD, tetapi tidak ada order yang tercipta. Alur pemesanan kurir berhenti sebelum tahap dispatch.

**Perbaikan wajib:** hubungkan halaman ke kontrak order authoritative: validasi dan normalisasi koordinat, panggil RPC checkout/order yang sesuai, simpan `delivery_type = INTERNAL` atau `EXPEDITION`, lalu buat offer melalui `create_delivery_offer` atau worker dispatch. Tambahkan test yang memastikan satu klik menghasilkan tepat satu order (idempotensi).

### OJ-05 — P1: Tidak ada batas jarak server-side yang jelas untuk ride ojek penumpang

**Bukti:** seed `ride_fare_settings` pada `supabase/bootstrap/05_20260220110705_to_20260508000000.sql:917-925` hanya memuat tarif dasar, tarif per km, minimum, dan maksimum; tidak terlihat enforcement maksimum jarak untuk `ride_requests`. Policy dan acceptance RPC juga tidak menunjukkan pemeriksaan jarak atau wilayah.

**Dampak:** ride ojek dapat dibuat dengan `distance_km` atau koordinat yang melewati cakupan operasional, bergantung pada validasi UI yang tidak cukup sebagai kontrol keamanan/bisnis.

**Perbaikan wajib:** tentukan kebijakan eksplisit, misalnya maksimum 10 km atau maksimum jarak sesuai wilayah operasional. Hitung jarak server-side dari koordinat pickup dan tujuan dengan Haversine; jangan percaya `distance_km` dari client. Tolak di RPC create ride bila koordinat invalid, jarak melebihi batas, atau wilayah di luar cakupan. Simpan `server_distance_km` dan tarif server-side.

### OJ-06 — P1: Acceptance ojek menerima `p_courier_id` dari client tanpa verifikasi identitas di RPC

**Bukti:** `accept_ride(p_ride_id, p_courier_id)` pada `supabase/bootstrap/05_20260220110705_to_20260508000000.sql:932-947` meng-update `driver_id = p_courier_id` bila ride masih `SEARCHING` dan belum memiliki driver. Potongan fungsi yang diaudit tidak menunjukkan pemeriksaan bahwa `p_courier_id` adalah courier milik `auth.uid()`, aktif, approved, dan tersedia.

**Risiko:** courier authenticated dapat mencoba menerima ride atas nama courier lain atau menugaskan akun courier yang tidak aktif, jika RPC dapat dipanggil langsung.

**Perbaikan wajib:** abaikan `p_courier_id` dari client atau cocokkan dengan `SELECT id FROM couriers WHERE user_id = auth.uid()`. Validasi `registration_status = APPROVED`, `status = ACTIVE`, dan `is_available = true` di dalam transaksi. Lebih aman, ubah signature menjadi `accept_ride(p_ride_id)`.

### OJ-07 — P1: Notifikasi ride membroadcast alamat pickup kepada semua courier aktif

**Bukti:** trigger `notify_couriers_new_ride` pada `supabase/bootstrap/05_20260220110705_to_20260508000000.sql:1036-1067` memasukkan notifikasi ke semua courier yang approved, active, dan available; pesan berisi `NEW.pickup_address`.

**Risiko:** paparan alamat pribadi kepada courier yang tidak mengambil order, termasuk potensi masalah privasi dan kebocoran lokasi penumpang.

**Perbaikan wajib:** gunakan coarse location/area dan estimasi jarak pada fase broadcast. Setelah courier menerima assignment, baru tampilkan alamat lengkap kepada courier yang ditugaskan. Jika kebutuhan bisnis mengharuskan alamat penuh, dokumentasikan dasar pemrosesan dan batasi retensi notifikasi.

### OJ-08 — P1: Batas kurir marketplace 10 km menggunakan field historis `buyer_distance_km`; enforcement bergantung pada migration terbaru

**Bukti positif:** `supabase/bootstrap/47_20260909210000_delivery_method_restrictions.sql:18-75` menolak `INTERNAL` bila `NEW.buyer_distance_km > 10` dan membandingkan kabupaten/kota serta kecamatan bila metadata tersedia. `supabase/bootstrap/50_20260911071000_transaction_critical_high_hardening.sql` menghitung Haversine distance dari koordinat merchant dan delivery pada checkout dan tidak lagi memakai nilai jarak mentah dari client.

**Residual risk:** source repository berisi bootstrap/manual migrations, dan belum ada koneksi staging dalam audit ini untuk membuktikan migration 47 dan 50 sudah aktif pada database target. Selain itu, trigger hanya membandingkan wilayah administratif jika kedua sisi memiliki metadata; jarak adalah authoritative fallback.

**Perbaikan/verification:** jalankan smoke test staging dengan jarak 10 km, 10.01 km, koordinat null, dan wilayah berbeda. Pastikan insert/update langsung ke `orders` ditolak dan checkout hanya bisa lewat RPC authoritative. Log `server_distance_km`/quote ID untuk rekonsiliasi.

## Alur yang sudah cukup baik

1. **Acceptance kurir marketplace** memakai `create_delivery_offer` dan `respond_delivery_offer`, serta mengunci assignment/order dengan row lock.
2. **Transisi order kurir marketplace** pada `courier_transition_order` memeriksa `courier_id` terhadap `auth.uid()` dan hanya mengizinkan rangkaian `COURIER_ACCEPTED -> PICKED_UP -> SENT -> DELIVERED`.
3. **Rating courier marketplace** sudah memeriksa buyer, status selesai, courier yang benar, rentang 1–5, dan meng-update agregat rating melalui RPC.
4. **Batas internal delivery marketplace** memiliki kontrol 10 km dan wilayah administratif pada database, dengan checkout terbaru menghitung jarak dari koordinat server-side.
5. **Acceptance race** untuk `accept_ride` menggunakan predicate `status = 'SEARCHING' AND driver_id IS NULL`, sehingga hanya satu acceptance concurrent yang semestinya berhasil; tetap perlu verifikasi identitas courier di RPC.

## Hasil pengujian lokal

| Pemeriksaan | Hasil | Catatan |
|---|---:|---|
| `pnpm install --frozen-lockfile --prefer-offline` | PASS | Dependency berhasil dipasang |
| Test delivery restriction | PASS | 5 test passed |
| Test courier integration | PASS dengan skip | 1 test file; 1 test passed, 4 skipped karena fixture staging tidak aktif |
| Test `DeliveryStatusCard` | PASS | 3 test passed |
| Total test terarah | PASS | 9 passed, 4 skipped |
| `pnpm run build` | PASS | Vite + PWA build berhasil |
| Dynamic RLS/staging test | BELUM DILAKUKAN | Memerlukan credential/fixture database staging |

Test yang ada belum mencakup abuse case paling penting: buyer mengubah `driver_id`/tarif/status melalui direct update, courier mengubah field sensitif, rating sebelum selesai, duplicate rating, dan acceptance dengan `p_courier_id` milik akun lain.

## Rencana remediasi prioritas

### P0 — sebelum alur dianggap production-ready

1. Tutup direct update `ride_requests` dari buyer dan courier; semua cancel/accept/status/rating harus melalui RPC stateful.
2. Implementasikan `submit_ride_rating` dengan ownership, status selesai, idempotensi, dan constraint satu rating.
3. Verifikasi identitas courier di `accept_ride`, atau hapus parameter courier dari signature RPC.
4. Hubungkan `CourierBookingPage` ke create-order dan dispatch yang authoritative, atau sembunyikan tombol sampai backend siap.

### P1 — sebelum pilot diperluas

1. Terapkan dan smoke-test batas jarak ride ojek penumpang di database.
2. Kurangi paparan alamat pada broadcast notification.
3. Tambahkan server-side coordinate validation: rentang latitude/longitude, koordinat null, akurasi GPS, dan kewajaran jarak.
4. Tambahkan audit history untuk setiap transition, cancel, acceptance, dan rating.

### Test matrix minimum

| Skenario | Ekspektasi |
|---|---|
| Buyer A membuat ride untuk dirinya | Berhasil, status `SEARCHING` |
| Buyer A mengubah `driver_id` atau tarif | Ditolak |
| Buyer A membatalkan `SEARCHING` | Berhasil melalui RPC |
| Buyer A membatalkan `COMPLETED` | Ditolak |
| Courier A menerima dengan courier ID B | Ditolak |
| Dua courier menerima ride bersamaan | Tepat satu berhasil |
| Courier mengubah `ACCEPTED -> COMPLETED` langsung | Ditolak |
| Courier mengikuti state machine sampai selesai | Berhasil |
| Rating sebelum selesai | Ditolak |
| Rating kedua untuk ride sama | Ditolak/idempotent |
| Internal delivery tepat 10 km | Berhasil jika wilayah sama |
| Internal delivery 10.01 km | Ditolak, arahkan ke `EXPEDITION` |
| Internal delivery wilayah berbeda meski 4 km | Ditolak |
| Client mengirim jarak palsu | Diabaikan; server menghitung ulang |
| Booking courier menekan submit dua kali | Satu order, bukan duplikasi |

## Kesimpulan

**Marketplace courier flow** sudah memiliki kontrol inti yang lebih matang, khususnya pada order fulfillment, offer, rating, dan batas jarak. **Passenger ojek flow belum aman dan belum konsisten**, terutama karena direct update RLS dan rating langsung pada `ride_requests`. Prioritas tertinggi adalah memindahkan seluruh mutasi ojek ke RPC dengan state machine dan ownership checks, lalu mengaktifkan/menyelesaikan dispatch pada halaman booking kurir. Build dan test lokal lulus, tetapi hasil tersebut tidak menggantikan dynamic RLS/concurrency test pada staging.

> Status akhir audit: **belum direkomendasikan untuk production sign-off pada alur ojek penumpang; alur kurir marketplace dapat dilanjutkan ke staging verification dengan migration gate.**
