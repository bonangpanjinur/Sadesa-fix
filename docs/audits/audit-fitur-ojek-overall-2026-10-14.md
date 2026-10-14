# Audit Fitur Ojek Keseluruhan

**Tanggal:** 2026-10-14  
**Scope:** role pembeli/penumpang, role ojek/driver, booking kurir/barang, dispatch, state machine, ongkos, fee/pendapatan, RLS, dan kesiapan test/deploy.  
**Metode:** static review source React, Supabase bootstrap/archive/migration, kontrak test, serta build/test smoke lokal.

## Ringkasan eksekutif

Fondasi fitur ojek sudah memiliki beberapa kontrol baik: mutasi utama memakai RPC server-authoritative, offer ditargetkan ke ojek tertentu, GPS/heartbeat diperiksa saat penerimaan, dan pembatasan satu perjalanan aktif sudah tampak pada bootstrap terbaru `58_20260929160000_ride_requests_rls_recursion_fix.sql`.

Namun fitur belum layak dianggap selesai end-to-end karena:

1. **P0 — Jalur deploy database tidak deterministik dari sudut `supabase/migrations`.** Schema/RPC ride berada di bootstrap/archive, sementara script konsolidasi menghapus migration aktif. Jika environment baru menjalankan `supabase db push` hanya dari migration aktif, fitur ojek dapat tidak terbentuk atau drift.
2. **P0 — Driver dapat membatalkan ride setelah penumpang dijemput.** RPC masih menerima status `PICKED_UP` dan `IN_TRANSIT`, tanpa incident/reassign/refund/kompensasi.
3. **P1 — Harga yang terlihat pembeli tidak dijamin sama dengan harga server.** UI ride menghitung estimasi dari jarak jalan/fallback, sedangkan RPC menghitung jarak garis lurus dari koordinat. Booking kurir memiliki risiko serupa di batas zona dan saat rute lama masih tertinggal.
4. **P1 — Fee courier dapat berbeda antara snapshot order dan ledger wallet.** Default `charge_courier_delivery` berbeda (`false` pada trigger snapshot vs `true` pada wallet operation).
5. **P1 — Tarif ride dari JSON settings belum divalidasi ketat atau memiliki snapshot parameter/version.** Nominal final tersimpan, tetapi perubahan/setting invalid sulit diaudit.
6. **P1 — Histori state ride belum terstruktur.** Transisi normal dan cancel tidak menulis actor/reason ke `ride_status_history`, sehingga dispute dan investigasi SLA sulit.

## Temuan prioritas

### P0-01 — Pipeline deploy schema/RPC ojek tidak deterministik

**Bukti:**

- `supabase/migrations/` aktif hanya berisi migration checkout/admin bertimestamp 2026-10-13–14; objek ride utama ada di `supabase/bootstrap/01_20260127034916_to_20260907020000.sql` sekitar baris 15750+ dan bundle berikutnya.
- `scripts/consolidate-bootstrap.py:83-148` memindahkan migration aktif ke archive/bootstrap lalu menghapus file aktif.
- `supabase/bootstrap/01_20260127034916_to_20260907020000.sql:7-9` sendiri memperingatkan bootstrap tidak diterapkan ke project yang sudah memiliki migration history.

**Dampak:** environment baru, staging, dan production dapat memiliki schema/RPC berbeda bila jalur deploy tidak secara eksplisit menjalankan bootstrap kosong yang benar. Kegagalan akan muncul sebagai `function does not exist`, tabel tidak ada, atau state flow parsial.

**Rekomendasi:** pilih satu sumber kebenaran deploy dan enforce di CI: (a) migration aktif lengkap dan incremental, atau (b) bootstrap kosong yang diuji pada database kosong. Tambahkan smoke test yang memanggil `create_ride_request_with_landmark`, `accept_ride`, `transition_ride_status`, `create_courier_order`, dan RPC fee setelah bootstrap.

### P0-02 — Driver cancel setelah pickup tanpa recovery operasional

**Bukti:** `supabase/bootstrap/05_20260911110000_to_20260914150000.sql:2132-2138` mengizinkan `ACCEPTED`, `PICKED_UP`, dan `IN_TRANSIT`, lalu langsung mengubah status menjadi `CANCELED` dan mengirim notifikasi.

**Dampak:** penumpang bisa sudah berada di kendaraan lalu ditinggalkan. Tidak ada incident ticket, re-dispatch, refund/kompensasi, penalti terukur, atau handoff ke admin.

**Rekomendasi:**

- Batasi cancel mandiri driver ke `ACCEPTED` sebelum pickup, atau masukkan status khusus `DRIVER_CANCEL_REVIEW` setelah pickup.
- Untuk cancel pasca-pickup, wajibkan alasan terstruktur + foto/lokasi bila perlu, beri alert admin, dan buat recovery/reassign.
- Pisahkan `CANCELED_BY_DRIVER_BEFORE_PICKUP` dan `ABORTED_AFTER_PICKUP`; hitung dampak saldo/kompensasi secara eksplisit.

### P1-01 — Estimasi ongkos ride UI berbeda dengan harga server

**Bukti:**

- `src/pages/ride/RideBookingPage.tsx:241-248` memilih `roadRoute?.distanceKm` dan fallback jarak garis lurus.
- `src/pages/ride/RideBookingPage.tsx:264-285` menghitung `estimatedFare` di browser.
- `src/pages/ride/RideBookingPage.tsx:320-328` hanya mengirim koordinat/alamat/landmark; tidak mengirim `distanceKm` atau `estimatedFare`.
- `supabase/bootstrap/58_20260929160000_ride_requests_rls_recursion_fix.sql:58-74` menghitung ulang jarak haversine garis lurus dan tarif server.

**Dampak:** pembeli dapat melihat nominal berdasarkan jarak jalan, tetapi order tersimpan menggunakan jarak garis lurus. Saat routing gagal atau perbedaan cukup besar, angka konfirmasi tidak sama dengan final/estimated fare di ride.

**Rekomendasi:** gunakan RPC quote server yang mengembalikan `distance_km`, `fare`, `pricing_version`, lalu tampilkan quote tersebut sebelum konfirmasi dan simpan quote snapshot saat create. Minimal, labeli estimasi UI sebagai indikatif dan tampilkan nominal server setelah order dibuat.

### P1-02 — Estimasi kurir bisa stale saat titik diubah cepat

**Bukti:** `src/pages/transport/CourierBookingPage.tsx:264-284` memperbarui route asynchronous tetapi tidak mengosongkan `roadRoute` lama sebelum request baru selesai. `canContinue` di sekitar `:296-308` tidak mensyaratkan `routeLoading === false`. RPC dipanggil di `:325-340` hanya dengan koordinat dan berat.

**Dampak:** user dapat menekan submit ketika jarak/band/estimasi masih berasal dari pasangan titik sebelumnya. Server tetap menghitung ulang dari koordinatnya sendiri, sehingga nominal final dapat berbeda dari kartu estimasi.

**Rekomendasi:** reset `roadRoute` saat input titik berubah, disable submit saat `routeLoading`, dan gunakan server quote yang sama dengan create. Tambahkan test untuk perubahan pickup/destination berturut-turut dan route request out-of-order.

### P1-03 — Booking kurir memaksa GPS walau pickup sudah dipilih manual

**Bukti:** `src/pages/transport/CourierBookingPage.tsx:310-323` selalu memanggil `requestRequiredLocation()` sebelum create, meskipun pickup sudah mempunyai koordinat hasil pilihan peta.

**Dampak:** user yang menolak izin lokasi tetap tidak dapat memakai layanan, padahal form mendukung pemilihan pickup manual. Ini juga tidak konsisten dengan makna koordinat pickup yang sudah diberikan user.

**Rekomendasi:** jadikan GPS wajib hanya ketika mengisi pickup otomatis atau ketika kebijakan operasional benar-benar mengharuskannya. Untuk titik manual, validasi koordinat, alamat, dan area layanan tanpa memblokir karena permission GPS.

### P1-04 — Dispatch order dari UI berpotensi retry/race berulang

**Bukti:** audit frontend menemukan `src/pages/OrderTrackingPage.tsx:170-177` memanggil `dispatch_courier_order`, sementara `fetchOrderDetails` dipicu mount, realtime, refresh manual, dan effect dependency sekitar `:231-264`.

**Dampak:** refresh/realtime dapat memicu retry dispatch berulang. Meskipun RPC terbaru sudah memiliki perlindungan eligibility, cooldown/idempotensi operasional tetap harus dijamin server-side agar tidak membuat offer berulang atau notifikasi duplikat.

**Rekomendasi:** pindahkan retry ke job/server dengan idempotency key + cooldown, atau RPC harus mengembalikan `next_retry_at` dan menolak retry sebelum waktunya. UI hanya menampilkan status dispatch.

### P1-05 — Snapshot fee courier dan ledger wallet memakai default berbeda

**Bukti:**

- `supabase/migrations/20261013210000_validate_shipping_settings_and_snapshot_courier_fees.sql:217-227` memakai `COALESCE(charge_courier_delivery, false)`.
- `supabase/bootstrap/88_20261009092000_commission_wallet_operations.sql:289-301` memakai `COALESCE(charge_courier_delivery, true)`.

**Dampak:** untuk row settings legacy/NULL, order dapat menyimpan `courier_platform_fee = 0`, tetapi operasi wallet tetap menagih komisi. Tampilan pendapatan, saldo, dan ledger menjadi tidak sama.

**Rekomendasi:** buat satu fungsi canonical `resolve_courier_delivery_fee_contract()` yang mengembalikan enabled/rate/payer/version; gunakan fungsi itu untuk snapshot order, earning, dan wallet settlement. Tetapkan default tunggal serta migrasikan NULL lama secara eksplisit.

### P1-06 — Snapshot fee belum immutable sebagai contract lengkap

**Bukti:** trigger snapshot hanya berjalan pada `BEFORE UPDATE OF status` menuju terminal di `supabase/migrations/20261013210000_validate_shipping_settings_and_snapshot_courier_fees.sql:194-239`. Yang disimpan terutama nominal gross/platform fee; rate dan versi setting tidak disimpan. Ledger membaca rate saat settlement pada `supabase/bootstrap/88_20261009092000_commission_wallet_operations.sql:289-343`.

**Dampak:** import/backfill atau perubahan setting sebelum settlement dapat membuat histori sulit dijelaskan dan membuka selisih antara order snapshot dan wallet.

**Rekomendasi:** simpan `fee_percent_snapshot`, `fee_enabled_snapshot`, `charge_courier_delivery_snapshot`, `fee_policy_version`, `gross_amount_snapshot`, dan `net_amount_snapshot` saat terminal transition. Settlement hanya boleh memakai snapshot tersebut.

### P1-07 — Tarif ride belum divalidasi ketat dan belum menyimpan pricing version

**Bukti:** `supabase/bootstrap/58_20260929160000_ride_requests_rls_recursion_fix.sql:67-74` mengambil field JSON lalu `COALESCE`; tidak ada pengecekan server bahwa nilai non-negatif, `min <= max`, dan batas maksimum operasional. Seed default ada di `supabase/bootstrap/01_20260127034916_to_20260907020000.sql:15989-15997`.

**Dampak:** setting invalid dapat menghasilkan tarif anomali; ketika setting berubah, nominal lama bisa diketahui tetapi parameter kebijakan yang menghasilkan nominal tersebut tidak tersimpan.

**Rekomendasi:** validasi melalui trigger/RPC admin, tolak nilai invalid, dan simpan `fare_policy_version` + parameter snapshot pada ride.

### P1-08 — Accept ride perlu satu invariant serialisasi yang jelas

**Bukti:** `supabase/bootstrap/74_20261005123000_close_stale_transport_offers.sql:33-47` sudah mengambil advisory lock dan mengunci row ride sebelum update, sehingga bootstrap terbaru relatif aman. Namun sumber/archive dan bundle historis memiliki beberapa definisi `accept_ride`; jalur deploy yang salah dapat memilih implementasi lama.

**Dampak:** bila definisi lama aktif, status offer dapat menyimpang dari driver ride aktual pada penerimaan bersamaan.

**Rekomendasi:** pastikan hanya satu definisi final yang diterapkan, tambah unique partial index/invariant untuk satu driver aktif dan satu ride accepted, lalu integration-test dua accept paralel.

### P1-09 — Histori status ride tidak terstruktur

**Bukti:** `supabase/bootstrap/06_20260914153000_to_20260918170000.sql:69-106` melakukan transition dan membuat `courier_earnings`, tetapi tidak terlihat insert actor/reason ke `ride_status_history`. Cancel di `supabase/bootstrap/05_20260911110000_to_20260914150000.sql:2135-2138` juga langsung update row.

**Dampak:** dispute, audit siapa melakukan transisi, waktu SLA, dan rekonsiliasi cancel sulit dilakukan.

**Rekomendasi:** tambahkan append-only `ride_status_history` pada setiap transition/cancel dengan `from_status`, `to_status`, `actor_id`, `actor_role`, `reason`, `metadata`, dan timestamp.

### P2-01 — Validasi redirect sukses belum defensif

**Bukti:** `src/pages/transport/CourierBookingPage.tsx:342-349` harus memeriksa `result.order_id`; `src/pages/ride/RideBookingPage.tsx:329-334` langsung menavigasi menggunakan `data`.

**Dampak:** respons RPC shape kosong/salah dapat menghasilkan URL `/orders/undefined/tracking` atau `/ride/undefined` setelah toast sukses.

**Rekomendasi:** validasi dengan schema/guard (`zod` atau type predicate) sebelum toast dan redirect; jika invalid, tampilkan error dan jangan menganggap booking berhasil.

### P2-02 — Timeout searching ride hanya mengandalkan toast/realtime

**Bukti:** `src/pages/ride/RideTrackingPage.tsx:187-205` mengubah countdown menjadi 0 dan menampilkan pesan pembatalan otomatis, tetapi tidak melakukan refetch/backoff setelah deadline.

**Dampak:** ketika realtime terlambat/putus, buyer dapat melihat status `SEARCHING` stale lebih lama dan CTA belum berubah.

**Rekomendasi:** setelah timeout jalankan refetch terbatas dengan exponential backoff, tampilkan status `CANCEL_PENDING` bila tersedia, dan sediakan tombol retry yang aman.

## Review role

### Pembeli/penumpang

- **Booking ride:** sudah memakai landmark wajib, pengecekan active ride, GPS, dan RPC create. Risiko terbesar adalah quote UI vs server dan validasi ID respons.
- **Tracking/cancel/rating:** akses data dibatasi ke `passenger_id`; cancel/rating lewat RPC. Perlu recovery timeout dan aturan kompensasi saat driver cancel pasca-pickup.
- **Booking kurir:** input manual cukup lengkap dan server memvalidasi koordinat/berat/recipient; namun GPS dipaksa dan estimasi dapat stale.

### Ojek/driver

- **Offer:** target offer, expiry, heartbeat, status approved/active, dan GPS terbaru sudah diperiksa. Pastikan bundle final selalu yang terdeploy.
- **Accept:** UI memperbarui lokasi lalu memanggil RPC; kontrol keamanan tidak boleh bergantung pada UI. Bootstrap terbaru sudah memiliki advisory lock dan row lock.
- **Lifecycle:** transition `ACCEPTED → PICKED_UP → IN_TRANSIT → COMPLETED` server-authoritative dan membutuhkan verification note. Celah utamanya adalah cancel pasca-pickup dan histori status.
- **Pendapatan:** ride menghasilkan `courier_earnings`; delivery mencoba menghitung gross/net dari snapshot. Perlu menyatukan contract fee order dan wallet.

### Ongkos

- **Ride passenger:** server menghitung base + per-km dengan haversine, min/max; UI memakai road route/fallback. Wajib server quote/snapshot.
- **Kurir barang:** UI menampilkan 8k/12k/18k + tambahan berat; server bootstrap terbaru memakai formula yang sama secara konsep, tetapi tetap memakai jarak haversine sementara UI dapat memakai road route dan route lama.
- **Komisi courier delivery:** nominal gross/platform fee belum konsisten saat setting NULL dan belum menyimpan rate/version lengkap.

## Pengujian dan keterbatasan verifikasi

- Static contract tests terkait RLS, dispatch, fee, dan lifecycle tersedia di `src/lib/*test.ts`.
- Build dan test smoke **belum dapat dijalankan** pada sandbox audit ini karena dependency lokal belum ter-install (`node_modules` tidak ada; `vite` dan `vitest` tidak ditemukan). Ini bukan bukti test gagal secara kode, tetapi merupakan gap validasi lingkungan.
- Tambahkan regression test untuk: quote server vs UI, route loading/out-of-order, manual pickup tanpa GPS permission, missing RPC ID, driver cancel setelah pickup, fee NULL/default, dan dua accept paralel.

## Urutan perbaikan yang disarankan

1. Pastikan pipeline bootstrap/migration deterministik dan jalankan smoke test DB kosong + staging.
2. Tutup driver cancel setelah pickup dan implementasikan incident/recovery.
3. Satukan server quote + pricing snapshot untuk ride dan courier.
4. Satukan fee contract order–earning–wallet dengan policy version.
5. Tambahkan status history append-only dan invariant concurrency.
6. Perbaiki UX/robustness: GPS manual pickup, route loading, timeout refetch, response schema guard.
7. Install dependency dan jalankan full `pnpm test` + `pnpm build` di CI/staging.
