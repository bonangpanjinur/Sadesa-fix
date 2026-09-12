# Audit Alur Ojek Penumpang

**Tanggal:** 12 September 2026
**Repository:** `bonangpanjinur/Sadesa-fix`
**Cakupan:** booking penumpang, `ride_requests`, pembatalan, dispatch driver, transisi status, realtime, rating, RLS, dan pengujian.

## Kesimpulan

Alur ojek penumpang sudah memiliki fondasi UI dan beberapa RPC, tetapi belum dapat diberi production sign-off. Risiko utama berada pada policy `UPDATE` langsung terhadap `ride_requests`, konsistensi identitas driver pada acceptance, dan belum adanya bukti dynamic RLS/concurrency test pada database staging.

Alur tracking ride di `RideTrackingPage` sudah menggunakan `cancel_ride()` dan `submit_ride_rating()`, tetapi policy lama masih mengizinkan update langsung pada kondisi tertentu. Karena itu, keamanan tidak boleh hanya bergantung pada frontend atau policy status sederhana.

## Peta alur

| Tahap | Komponen | Kontrak saat ini | Penilaian |
|---|---|---|---|
| Booking | `RideBookingPage` | Membuat/menemukan order melalui RPC atau jalur booking terkait | Perlu diuji double-submit dan dispatch |
| Mencari driver | `ride_requests` status `SEARCHING` | Realtime dan auto-cancel di halaman tracking | Perlu lease/timeout server-side yang konsisten |
| Acceptance | `accept_ride` / dispatch driver | Predicate status dan driver kosong membantu race prevention | Identitas courier dan parameter RPC perlu diverifikasi |
| Perjalanan | `ACCEPTED`, `PICKED_UP`, `IN_TRANSIT` | Driver dashboard mengubah status | Direct update harus ditutup seluruhnya |
| Selesai | `COMPLETED` | Rating dibuka setelah selesai | Perlu idempotensi rating dan audit history |
| Batal | `cancel_ride` | Penumpang dapat membatalkan pada status awal | Perlu memastikan direct update tidak menjadi bypass |

## Temuan

| ID | Prioritas | Temuan | Dampak |
|---|---|---|---|
| RIDE-P0-01 | P0 | Policy `UPDATE` pada `ride_requests` masih memberi jalur langsung kepada courier assigned dan passenger pada status tertentu | Caller dapat mencoba mengubah field sensitif seperti tarif, driver, koordinat, atau status apabila kolom tidak dibatasi oleh trigger/RPC |
| RIDE-P0-02 | P0 | Belum ada dynamic RLS dan concurrency test pada staging | Tidak ada bukti bahwa policy dan RPC final benar-benar aktif di database target |
| RIDE-P0-03 | P0 | Acceptance perlu memastikan `p_courier_id` benar-benar terikat ke `auth.uid()` | Courier A berpotensi mencoba menerima ride memakai ID courier B jika signature dan function belum mengunci identitas |
| RIDE-P1-04 | P1 | State machine ride belum dipastikan tunggal antara UI driver, UI penumpang, RPC, dan policy | Driver dapat melewati status atau UI menampilkan status yang tidak sesuai |
| RIDE-P1-05 | P1 | Rating perlu diuji idempotensi dan constraint satu rating per ride | Duplicate rating atau rating sebelum selesai dapat merusak agregat rating |
| RIDE-P1-06 | P1 | Coordinate validation dan distance sanity belum dibuktikan pada server | Koordinat invalid atau jarak tidak wajar dapat memengaruhi tarif/dispatch |
| RIDE-P2-07 | P2 | Audit history ride belum lengkap untuk cancel, acceptance, transition, dan rating | Investigasi sengketa dan rekonsiliasi sulit dilakukan |
| RIDE-P2-08 | P2 | Broadcast notification berpotensi terlalu banyak memaparkan alamat pickup/destination | Risiko privasi lokasi penumpang |

## State machine yang direkomendasikan

| State | Aktor | Transisi sah |
|---|---|---|
| `SEARCHING` | Passenger/system/driver | `CANCELLED`, `ACCEPTED` |
| `ACCEPTED` | Assigned driver/passenger | `PICKED_UP`, `CANCELLED` |
| `PICKED_UP` | Assigned driver | `IN_TRANSIT`, `CANCELLED` bila kebijakan mengizinkan |
| `IN_TRANSIT` | Assigned driver | `COMPLETED` |
| `COMPLETED` | System/passenger | Rating satu kali, tidak kembali ke ride aktif |
| `CANCELLED` | System | Terminal |

Semua transisi harus dilakukan melalui RPC yang memeriksa actor, ownership, current state, dan row lock. Direct `UPDATE` authenticated sebaiknya dicabut untuk passenger dan courier.

## Remediasi yang diperlukan

1. Buat atau perkuat `passenger_cancel_ride()` dan `courier_transition_ride()` dengan row lock, actor ownership, state matrix, timestamp, dan history.
2. Revoke direct `UPDATE` authenticated pada `ride_requests`; berikan hanya `SELECT` sesuai ownership dan `EXECUTE` RPC.
3. Ubah `accept_ride` agar mengambil courier dari `auth.uid()` atau memvalidasi bahwa parameter courier memiliki `user_id = auth.uid()`.
4. Pastikan `submit_ride_rating()` mengunci ride, hanya menerima status `COMPLETED`, membatasi rating 1–5, dan idempotent berdasarkan `ride_id + passenger_id`.
5. Tambahkan validasi latitude/longitude, akurasi, jarak maksimum, dan kewajaran jarak server-side.
6. Tambahkan `ride_status_history` atau audit event yang mencatat actor, from status, to status, reason, dan timestamp.
7. Reduksi data lokasi pada notifikasi broadcast; driver hanya menerima data yang diperlukan untuk dispatch.

## Test matrix minimum

| Skenario | Hasil yang diharapkan |
|---|---|
| Passenger membuat ride | Satu row `SEARCHING` |
| Passenger submit dua kali | Satu ride, bukan duplikasi |
| Passenger mengubah driver/tarif/status | Ditolak |
| Passenger cancel `SEARCHING` | Berhasil melalui RPC |
| Passenger cancel `COMPLETED` | Ditolak |
| Courier A menerima memakai ID Courier B | Ditolak |
| Dua courier menerima bersamaan | Tepat satu sukses |
| Courier melompat dari `ACCEPTED` ke `COMPLETED` | Ditolak |
| Courier mengikuti state machine | Berhasil |
| Rating sebelum `COMPLETED` | Ditolak |
| Rating kedua | Ditolak atau dikembalikan sebagai idempotent |
| Koordinat di luar rentang | Ditolak |
| Jarak palsu dari client | Diabaikan; server menghitung ulang |
| RLS direct update | Ditolak |

## Status akhir

**Belum production-ready.** Marketplace order dan ekspedisi dapat dilanjutkan ke staging, tetapi alur ojek penumpang membutuhkan hardening RPC/RLS dan dynamic staging test sebelum digunakan sebagai alur produksi.
