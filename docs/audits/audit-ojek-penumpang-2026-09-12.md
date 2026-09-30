# Audit Alur Ojek Penumpang

**Tanggal:** 12 September 2026
**Repository:** `bonangpanjinur/Sadesa-fix`
**Cakupan:** booking penumpang, `ride_requests`, pembatalan, dispatch driver, transisi status, realtime, rating, RLS, dan pengujian.

## Kesimpulan

Source code sudah memiliki hardening utama untuk alur ojek penumpang melalui migration `52_20260911110000_ride_authoritative_mutations.sql`. Pembuatan ride, acceptance driver, pembatalan passenger, dan rating diarahkan melalui RPC. Direct `INSERT` dan `UPDATE` authenticated pada `ride_requests` juga dicabut oleh migration tersebut.

Alur ini **belum memperoleh production sign-off** karena belum ada dynamic RLS test, concurrency test, dan verifikasi bahwa migration terbaru sudah aktif pada database staging/production.

## Kontrol yang sudah tersedia

| Area | Implementasi | Status |
|---|---|---|
| Create ride | `create_ride_request()` menghitung jarak dan tarif di server | Selesai di source |
| Validasi koordinat | Latitude/longitude dibatasi rentang valid | Selesai di source |
| Batas jarak | Ride dibatasi maksimal 10 km pada RPC | Selesai di source |
| Acceptance | `accept_ride()` memeriksa `user_id`, status approved/active, dan availability courier | Selesai di source |
| Race acceptance | Update mensyaratkan `SEARCHING` dan `driver_id IS NULL` | Selesai di source |
| Cancel passenger | `cancel_ride()` membatasi pemilik dan status `SEARCHING`/`ACCEPTED` | Selesai di source |
| Transition driver | `transition_ride_status()` memeriksa driver assigned dan state matrix | Selesai di source |
| Rating | `submit_ride_rating()` hanya menerima ride `COMPLETED` dan satu rating | Selesai di source |
| Direct mutation | `INSERT`/`UPDATE` authenticated dicabut | Selesai di source |
| Staging verification | Dynamic RLS, race, dan abuse test | Belum dilakukan |

## State machine

| State | Aktor | Transisi sah |
|---|---|---|
| `SEARCHING` | Passenger/system/driver | `CANCELLED`, `ACCEPTED` |
| `ACCEPTED` | Assigned driver/passenger | `PICKED_UP`, `CANCELLED` |
| `PICKED_UP` | Assigned driver | `IN_TRANSIT` |
| `IN_TRANSIT` | Assigned driver | `COMPLETED` |
| `COMPLETED` | Passenger | Rating satu kali |
| `CANCELLED` | System | Terminal |

## Risiko residual

| ID | Prioritas | Risiko | Tindakan |
|---|---|---|---|
| RIDE-P0-01 | P0 | Database target mungkin belum menerapkan migration authoritative terbaru | Terapkan bootstrap ke staging dan jalankan smoke test RPC/RLS |
| RIDE-P0-02 | P0 | Acceptance dua courier secara bersamaan belum diuji pada database nyata | Jalankan concurrency test dan pastikan tepat satu request berhasil |
| RIDE-P1-03 | P1 | Realtime reconnect dan auto-cancel belum diuji saat jaringan terputus | Uji reconnect, lease/timeout, dan status terminal |
| RIDE-P1-04 | P1 | Audit history ride belum selengkap order marketplace | Tambahkan `ride_status_history` bila kebutuhan investigasi operasional mengharuskannya |
| RIDE-P2-05 | P2 | Payload notifikasi perlu ditinjau untuk meminimalkan alamat/lokasi sensitif | Kurangi data lokasi pada broadcast notification |

## Test matrix staging

| Skenario | Ekspektasi |
|---|---|
| Passenger membuat ride dengan koordinat valid | Satu ride `SEARCHING` |
| Passenger mengirim koordinat di luar rentang | Ditolak |
| Passenger mengirim jarak client palsu | Diabaikan; server menghitung ulang |
| Passenger cancel `SEARCHING` | Berhasil melalui RPC |
| Passenger cancel `COMPLETED` | Ditolak |
| Courier A menerima memakai ID Courier B | Ditolak |
| Dua courier menerima bersamaan | Tepat satu berhasil |
| Courier melompat `ACCEPTED` ke `COMPLETED` | Ditolak |
| Courier mengikuti state machine | Berhasil |
| Rating sebelum selesai | Ditolak |
| Rating kedua | Ditolak atau idempotent |
| Direct update `ride_requests` sebagai authenticated | Ditolak oleh privilege/RLS |

## Status akhir

Alur ojek penumpang sudah **dihardening pada source**, tetapi tetap **menunggu verifikasi staging**. Item yang tersisa bukan lagi implementasi dasar RPC, melainkan penerapan migration pada database target, pengujian concurrency/RLS, dan pengujian operasional reconnect/timeout.

## References

[1]: https://supabase.com/docs/guides/database/postgres/row-level-security "Supabase Row Level Security documentation"
