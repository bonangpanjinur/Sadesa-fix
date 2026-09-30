# Kontrak API dan Logika Alarm Ojek

**Status:** berlaku mulai commit `56c0e003`  
**Audience:** frontend, backend/Supabase, QA, dan developer yang mengintegrasikan dashboard kurir/ojek  
**Scope:** penerimaan order ojek, tawaran pengiriman langsung, push notification, alarm bunyi/getar, expiry, dan recovery koneksi.

## 1. Prinsip utama

1. **Offer harus targeted.** Ojek hanya boleh melihat dan menerima offer yang ditujukan kepada `courier_id` miliknya.
2. **Validasi server adalah sumber kebenaran.** UI, realtime, polling, dan alarm tidak boleh dianggap sebagai otorisasi.
3. **Kurir harus aktif dan lokasinya fresh.** Kurir yang tidak aktif, tidak tersedia, belum approved, atau heartbeat GPS-nya stale tidak boleh menerima order baru.
4. **Satu order hanya memiliki satu offer aktif.** Offer yang expired/ditolak diproses sebelum offer berikutnya dibuat.
5. **Alarm fail closed.** Jika tabel offer privat tidak tersedia atau query targeting gagal, aplikasi tidak boleh menggantinya dengan query seluruh order/ride yang sedang mencari kurir.

## 2. Entitas dan status penting

### 2.1 `ride_requests` — penumpang ojek

Status yang relevan:

| Status | Arti |
|---|---|
| `SEARCHING` | Menunggu offer kepada ojek yang eligible |
| `ACCEPTED` | Seorang ojek berhasil menerima offer |
| `PICKED_UP` | Penumpang sudah dijemput |
| `IN_TRANSIT` | Perjalanan sedang berlangsung |

`driver_id` diisi saat `accept_ride` berhasil. Sebelum itu, `driver_id` harus `NULL`.

### 2.2 `ride_request_offers` — offer privat ojek

| Kolom | Keterangan |
|---|---|
| `ride_id` | Ride penumpang |
| `courier_id` | Ojek yang ditargetkan |
| `status` | `PENDING`, `ACCEPTED`, `REJECTED`, atau `EXPIRED` |
| `offered_at` | Waktu offer dibuat |
| `expires_at` | Batas waktu penerimaan; default 30 detik |
| `responded_at` | Waktu ojek merespons/offer diproses otomatis |

Constraint penting:

- Unique `(ride_id, courier_id)`: satu ojek hanya dapat mencoba ride yang sama satu kali.
- Partial unique index untuk `status = 'PENDING'`: satu ride tidak dapat memiliki dua offer aktif bersamaan.
- RLS membatasi pembacaan offer kepada ojek yang memiliki `courier_id` tersebut.

### 2.3 `delivery_assignments` — pengiriman barang langsung

Status yang relevan:

| Status | Arti |
|---|---|
| `OFFERED` | Tawaran sedang menunggu respons ojek |
| `ACCEPTED` | Ojek menerima pengiriman |
| `EXPIRED` | Tawaran dilepas otomatis |

Alarm hanya membaca assignment dengan `courier_id` milik ojek yang sedang login, `status = 'OFFERED'`, dan `expires_at` masih di masa depan.

## 3. Kontrak RPC/API server

Semua RPC di bawah berada di schema `public` dan harus dipanggil melalui Supabase RPC. Jangan mengubah status tabel secara langsung dari client untuk alur acceptance.

### 3.1 `dispatch_next_ride_offer(p_ride_id uuid)`

**Akses:** `service_role` internal.  
**Return:** `uuid` offer baru atau `NULL` jika tidak ada ojek eligible.

Tugas:

1. Mengunci ride dan advisory lock dispatch.
2. Mengakhiri offer `PENDING` yang sudah expired.
3. Memilih satu ojek terdekat dengan syarat:
   - `registration_status = 'APPROVED'`;
   - `status = 'ACTIVE'`;
   - `is_available = true`;
   - `current_lat` dan `current_lng` tidak null;
   - `last_location_update >= now() - interval '90 seconds'`;
   - tidak sedang menjalankan ride aktif (`ACCEPTED`, `PICKED_UP`, `IN_TRANSIT`);
   - belum pernah dicoba untuk ride tersebut;
   - tidak sedang memegang offer ride lain yang masih `PENDING` dan belum expired.
4. Membuat offer selama 30 detik.
5. Membuat notifikasi in-app dan job push dengan template `new_ride_request`.

Dispatch dipicu saat ride baru berstatus `SEARCHING` dan dapat dipanggil ulang oleh expiry/recovery worker.

### 3.2 `accept_ride(p_ride_id uuid, p_courier_id uuid)`

**Akses:** `authenticated`; caller harus memiliki identitas courier tersebut.  
**Return:** `true` jika diterima, `false` jika offer sudah tidak valid atau ride sudah diambil.

Validasi atomik:

- courier cocok dengan `auth.uid()`;
- ride masih `SEARCHING` dan `driver_id IS NULL`;
- offer untuk pasangan `ride_id + courier_id` masih `PENDING`;
- offer belum melewati `expires_at`;
- courier tetap `APPROVED`, `ACTIVE`, dan `is_available = true`;
- heartbeat lokasi masih kurang dari 90 detik;
- koordinat courier tersedia;
- courier tidak mempunyai ride aktif lain.

Jika valid, fungsi mengubah:

```text
ride_request_offers.status = ACCEPTED
ride_requests.driver_id = p_courier_id
ride_requests.status = ACCEPTED
ride_requests.accepted_at = now()
```

Jika validasi gagal karena timeout, offer ditandai `EXPIRED` dan dispatch berikutnya boleh dijalankan.

### 3.3 `decline_ride_request(p_ride_id uuid)`

**Akses:** `authenticated`; courier diambil dari `auth.uid()`.  
**Return:** `true` jika offer aktif berhasil ditolak, `false` jika tidak ada offer aktif yang dapat ditolak.

Perilaku:

- hanya memproses offer milik courier caller;
- mengubah offer aktif menjadi `REJECTED`;
- jika respons datang setelah deadline, menandai offer sebagai `EXPIRED`;
- memanggil `dispatch_next_ride_offer` untuk mencari ojek berikutnya.

### 3.4 `process_expired_ride_offers()`

**Akses:** courier authenticated yang `APPROVED`, `ACTIVE`, `is_available = true`, dan memiliki heartbeat fresh.  
**Return:** jumlah ride yang berhasil diberi offer berikutnya.

Fungsi ini bukan pengganti scheduler server. Ia merupakan mekanisme kompatibilitas/heartbeat dari client. Worker server tetap menjadi pilihan utama untuk production recovery.

### 3.5 `dispatch_courier_order(p_order_id uuid)`

**Akses:** buyer pemilik order atau admin.  
**Return:** object JSON dengan status dispatch, misalnya:

```json
{
  "order_id": "<uuid>",
  "assignment_id": "<uuid>",
  "dispatch_status": "OFFERED"
}
```

Kemungkinan `dispatch_status`:

| Nilai | Arti |
|---|---|
| `OFFERED` | Offer baru atau offer aktif ditemukan |
| `WAITING_FOR_COURIER` | Belum ada courier eligible |
| `TIMED_OUT` | Order sudah melewati batas respons |
| `NOT_APPLICABLE` | Order bukan direct courier atau status tidak sesuai |
| `NOT_FOUND` | Order tidak ditemukan |

Pemilihan courier mengikuti aturan status, availability, koordinat, heartbeat 90 detik, riwayat rejection, dan tidak memiliki assignment aktif yang konflik.

### 3.6 `process_unresponsive_transport_offers()`

**Akses:** `service_role` saja.  
**Tujuan:** recovery terjadwal untuk:

- memproses offer ride yang expired;
- melepas offer direct delivery dari courier yang koneksinya hilang atau GPS-nya stale;
- memilih courier eligible berikutnya;
- mengirim notifikasi timeout jika tidak ada courier yang merespons.

Client tidak boleh menjalankan fungsi ini menggunakan anon/authenticated RPC.

## 4. Kontrak notifikasi dan push

Saat offer dibuat, server membuat dua jalur durable:

1. row pada `public.notifications` untuk inbox aplikasi;
2. row pada `public.notification_delivery_jobs` untuk worker push.

### Template push

| Flow | `template_key` | `data.type` | URL |
|---|---|---|---|
| Ojek penumpang | `new_ride_request` | `new_ride_request` | `/courier/rides` |
| Direct delivery | `new_delivery_offer` | `new_delivery_offer` | `/courier/deliveries` |

Payload minimal harus membawa identifier yang relevan, misalnya `ride_id`, `offer_id`, `order_id`, atau `assignment_id`. Jangan memasukkan data sensitif penumpang ke payload push.

Service worker menampilkan notification dengan:

- `silent: false`;
- pola vibrasi `COURIER_ALARM_VIBRATION_PATTERN`;
- action `Buka` dan `Tutup`;
- URL internal yang dibuka setelah user memilih notification.

## 5. Logika alarm client

Implementasi utama berada di [`useCourierOrderAlarm.ts`](../../src/hooks/useCourierOrderAlarm.ts).

### 5.1 Kapan alarm boleh aktif

Alarm hanya boleh berbunyi/getar jika seluruh kondisi berikut terpenuhi:

```text
courier.status === 'ACTIVE'
courier.registration_status === 'APPROVED'
courier.is_available === true
```

Saat courier menjadi offline, tidak available, atau statusnya berubah, pending set dikosongkan dan playback dihentikan.

### 5.2 Sumber data alarm

Untuk ride:

```text
ride_request_offers
  .courier_id = courier.id
  .status = 'PENDING'
  .expires_at > now()
```

Untuk direct delivery:

```text
delivery_assignments
  .courier_id = courier.id
  .status = 'OFFERED'
  .expires_at > now()
```

Client menggunakan kombinasi:

- Supabase Realtime untuk INSERT/UPDATE;
- polling inbox courier setiap 8 detik sebagai recovery bila realtime tidak aktif;
- seeding awal saat layout courier dibuka atau channel berhasil subscribe.

### 5.3 Fail-closed rule

Jika `ride_request_offers` tidak tersedia atau query targeted offer gagal:

- jangan query `ride_requests` dengan `status = 'SEARCHING'` secara global;
- jangan subscribe ke seluruh INSERT `ride_requests` `SEARCHING`;
- jangan membunyikan alarm dari ride yang tidak dapat dibuktikan ditargetkan kepada courier;
- tunggu migration/schema yang benar tersedia atau tampilkan error operasional melalui monitoring.

Aturan ini mencegah pickup/lokasi penumpang tampil ke seluruh ojek.

### 5.4 Bunyi dan getar

- Bunyi diputar melalui Web Audio API atau custom audio yang dikonfigurasi.
- Browser autoplay memerlukan user gesture; tombol **Aktifkan Bunyi & Getar** melakukan unlock AudioContext.
- Getar menggunakan `navigator.vibrate` jika perangkat mendukung.
- Alarm courier dipaksa aktif melalui profile courier; pengaturan merchant tidak boleh mematikan alarm penerimaan order courier.
- Alarm dihentikan ketika seluruh pending offer hilang, courier offline, component unmount, atau offer berubah menjadi non-pending.

## 6. State machine ringkas

```text
ride SEARCHING
  -> create targeted PENDING offer
  -> courier accepts     -> ride ACCEPTED
  -> courier declines    -> next courier offer
  -> expires             -> next courier offer
  -> no eligible courier -> tetap SEARCHING / recovery worker mencoba lagi

order ASSIGNED + assignment OFFERED
  -> courier accepts     -> assignment ACCEPTED
  -> courier declines    -> assignment EXPIRED / next courier
  -> courier stale       -> worker melepas offer / re-dispatch
  -> timeout             -> order timeout sesuai policy transport
```

`ASSIGNED` pada sisi order hanya berarti tawaran diarahkan ke courier. Chat dan live tracking buyer baru boleh dibuka setelah courier benar-benar menerima (`COURIER_ACCEPTED` untuk delivery flow).

## 7. Checklist developer

### Saat membuat atau mengubah API

- [ ] Gunakan RPC authoritative, bukan update status langsung dari browser.
- [ ] Pertahankan validasi ownership melalui `auth.uid()`.
- [ ] Gunakan row lock/advisory lock untuk acceptance dan dispatch concurrent.
- [ ] Pertahankan expiry dan `responded_at`.
- [ ] Pastikan dispatch tidak memilih courier dengan ride/offer/order aktif lain.
- [ ] Tambahkan notifikasi in-app dan durable delivery job jika membuat jenis offer baru.
- [ ] Tambahkan bootstrap bundle yang identik dengan source migration.

### Saat mengubah client alarm

- [ ] Query selalu memakai `courier_id` caller.
- [ ] Query selalu memfilter status offer aktif dan `expires_at`.
- [ ] Jangan menambahkan fallback global ke semua `SEARCHING` ride.
- [ ] Hentikan alarm saat status courier tidak eligible.
- [ ] Uji realtime INSERT, UPDATE menjadi accepted/rejected/expired, polling, refresh halaman, dan reconnect.
- [ ] Uji browser tanpa `navigator.vibrate` dan tanpa AudioContext.

### Quality gate

```bash
pnpm exec vitest run src/lib/courierOrderAlarm.test.ts \
  src/lib/nearestCourierDispatch.test.ts \
  src/lib/courierBookingDispatch.test.ts \
  src/lib/rideRequestRls.test.ts \
  src/lib/orderNotificationSound.test.ts \
  src/lib/pushNotification.test.ts

pnpm exec tsc --noEmit
pnpm exec eslint src/hooks/useCourierOrderAlarm.ts src/lib/courierOrderAlarm.test.ts
pnpm run validate:migrations
pnpm run validate:db-bootstrap
pnpm run build
```

## 8. Referensi implementasi

- Alarm client: [`src/hooks/useCourierOrderAlarm.ts`](../../src/hooks/useCourierOrderAlarm.ts)
- Regression test alarm: [`src/lib/courierOrderAlarm.test.ts`](../../src/lib/courierOrderAlarm.test.ts)
- Sound profile: [`src/lib/orderNotificationSound.ts`](../../src/lib/orderNotificationSound.ts)
- Push service worker: [`src/sw.ts`](../../src/sw.ts)
- Sequential ride dispatch migration: [`20260929011000_nearest_courier_sequential_ride_dispatch.sql`](../../archive/supabase/migrations/20260929011000_nearest_courier_sequential_ride_dispatch.sql)
- Delivery offer push migration: [`20260929133000_courier_delivery_offer_push.sql`](../../archive/supabase/migrations/20260929133000_courier_delivery_offer_push.sql)
- Transport recovery migration: [`20260929150000_transport_connection_drop_offer_recovery.sql`](../../archive/supabase/migrations/20260929150000_transport_connection_drop_offer_recovery.sql)
- RLS/ride contract test: [`src/lib/rideRequestRls.test.ts`](../../src/lib/rideRequestRls.test.ts)
