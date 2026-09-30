# Arsitektur Live Chat Realtime SaDesa

**Status:** Rencana arsitektur  
**Tanggal:** 7 September 2026  
**Ruang lingkup:** percakapan pembeli–pedagang dan penumpang–ojek, dengan fondasi yang dapat dipakai untuk percakapan lain di masa depan.

## 1. Tujuan

SaDesa membutuhkan chat dua arah yang:

1. terasa realtime tanpa refresh halaman;
2. aman berdasarkan relasi pengguna terhadap pesanan atau perjalanan;
3. mendukung konteks bisnis, yaitu produk/pesanan atau perjalanan ojek;
4. memiliki daftar percakapan, unread count, read receipt, status koneksi, dan notifikasi;
5. dapat berkembang dari percakapan dua pihak menjadi percakapan grup terbatas bila diperlukan;
6. tetap menggunakan stack yang sudah ada: React/Vite di frontend dan Supabase Auth, PostgreSQL, RLS, Realtime, Storage, serta Edge Functions di backend.

Dokumen ini adalah rencana dan arsitektur. Implementasi kode, migrasi database, dan perubahan UI dilakukan pada tahap terpisah setelah keputusan produk dikonfirmasi.

## 2. Kondisi saat ini

Proyek sudah memiliki fondasi chat berbasis order:

- tabel `public.chat_messages`;
- `order_id` sebagai konteks wajib;
- `sender_id`, `receiver_id`, `message`, `is_read`, `created_at`;
- `chat_type`: `buyer_merchant`, `buyer_courier`, `merchant_courier`;
- `image_url` dan `auto_delete_at`;
- RLS berbasis sender/receiver dan helper `is_chat_participant`;
- `chat_messages` sudah masuk publication `supabase_realtime`;
- `OrderChat` sudah berlangganan event `INSERT` dan `DELETE`;
- halaman daftar chat sudah tersedia untuk buyer, merchant, dan courier;
- unread counter dan notifikasi suara sudah memakai Realtime;
- `ride_requests` sudah menjadi domain perjalanan ojek dan sudah memiliki RLS serta Realtime.

### Batasan fondasi saat ini

`chat_messages` masih menggabungkan beberapa tanggung jawab:

- identitas percakapan diturunkan dari kombinasi `order_id` dan `chat_type`;
- tidak ada entitas conversation/thread yang stabil;
- setiap pesan menyimpan `receiver_id`, sehingga desainnya terutama dua pihak;
- percakapan ojek belum memiliki foreign key ke `ride_requests`;
- pengiriman pesan dilakukan langsung melalui insert dari browser;
- aturan update pesan masih perlu diperketat agar penerima hanya dapat mengubah status baca;
- `auto_delete_at` cocok untuk kebijakan chat order, tetapi tidak boleh menjadi asumsi global semua jenis chat.

## 3. Keputusan arsitektur utama

### 3.1 Conversation sebagai entitas utama

Tambahkan entitas `chat_conversations` sebagai sumber kebenaran untuk thread. Pesan tidak lagi menentukan thread hanya dari `order_id` + `chat_type`.

Satu conversation dapat memiliki:

- konteks `order_id`, atau
- konteks `ride_request_id`, atau
- konteks lain di masa depan melalui `context_type` dan `context_id`;
- judul/label yang aman ditampilkan;
- status aktif/tertutup/diarsipkan;
- kebijakan retensi;
- waktu pesan terakhir untuk pengurutan inbox.

Untuk MVP, satu conversation tetap dibatasi dua partisipan. Model partisipan dibuat sebagai tabel terpisah agar dapat diperluas tanpa mengubah tabel pesan.

### 3.2 Pesan immutable, read state terpisah

Isi pesan tidak boleh diedit oleh pengguna setelah terkirim pada MVP. Status baca disimpan di `chat_message_reads`, bukan mengubah satu `is_read` pada pesan. Ini menghindari masalah ketika satu pesan kelak memiliki lebih dari satu penerima dan membuat read receipt lebih konsisten.

### 3.3 Realtime untuk delivery, database untuk durability

Alur normal:

1. client melakukan insert pesan ke PostgreSQL melalui Supabase;
2. RLS memvalidasi pengirim dan partisipan;
3. PostgreSQL menjadi sumber kebenaran;
4. Supabase Realtime menyebarkan `INSERT` ke subscriber;
5. recipient melakukan ack/read update;
6. jika koneksi terputus, client melakukan refetch berdasarkan cursor.

Jangan menganggap event realtime sebagai satu-satunya sumber data. Event dapat terlewat ketika tab tidur, jaringan berpindah, atau channel reconnect.

### 3.4 Presence bukan sumber kebenaran bisnis

Status online/typing memakai Presence/Broadcast pada channel conversation dan bersifat ephemeral. Jangan menyimpan “online” sebagai status permanen di tabel pengguna. Status yang ditampilkan harus memiliki TTL client-side dan fallback “terakhir aktif” hanya jika fitur itu memang disetujui.

## 4. Arsitektur komponen

```text
React pages
  ├─ Chat inbox per role
  ├─ Conversation view
  └─ Context entry points (order / ride)
          │
          ▼
Chat domain hooks and API
  ├─ conversation repository
  ├─ message repository
  ├─ realtime subscription manager
  ├─ unread/read receipt manager
  └─ connection/reconnect state
          │
          ├─ Supabase Auth session
          ├─ PostgREST + RLS
          ├─ Supabase Realtime
          └─ Supabase Storage (optional attachment phase)
          │
          ▼
PostgreSQL
  ├─ chat_conversations
  ├─ chat_participants
  ├─ chat_messages
  ├─ chat_message_reads
  └─ chat_reports / moderation events (phase lanjut)
```

### Pembagian tanggung jawab

| Bagian | Tanggung jawab |
|---|---|
| Chat inbox | Mengambil thread yang boleh dilihat user, last message, unread count, dan konteks order/ojek |
| Conversation view | Menampilkan histori berpaginasi, mengirim pesan, ack baca, reconnect |
| Domain entry point | Membuat atau membuka conversation yang tepat dari order atau perjalanan |
| Repository/API | Menyembunyikan detail query, cursor pagination, deduplikasi, dan error mapping |
| Realtime manager | Satu channel per conversation aktif; cleanup subscription; reconnect dan refetch |
| RLS | Otorisasi final untuk select/insert/update |
| Edge Function | Notifikasi push, rate limiting tambahan, moderasi/attachment processing bila diperlukan |

## 5. Model data yang diusulkan

Nama tabel di bawah ini adalah desain target. Hindari langsung menghapus `chat_messages`; lakukan migrasi bertahap.

### 5.1 `chat_conversations`

```text
id                 uuid primary key
context_type       text not null -- 'order' | 'ride'
order_id           uuid null references orders(id) on delete cascade
ride_request_id    uuid null references ride_requests(id) on delete cascade
conversation_type  text not null
status             text not null default 'active'
last_message_id    uuid null
last_message_at   timestamptz null
closed_at          timestamptz null
retention_until   timestamptz null
created_at         timestamptz not null default now()
updated_at         timestamptz not null default now()
```

Constraint yang harus diterapkan:

- tepat satu konteks bisnis untuk MVP: `order_id` atau `ride_request_id`;
- `conversation_type` dibatasi enum/check:
  - `buyer_merchant`;
  - `buyer_courier`;
  - `merchant_courier`;
  - `passenger_courier` untuk istilah domain ojek yang lebih jelas;
- order conversation tidak boleh dibuat tanpa order yang valid;
- ride conversation tidak boleh dibuat tanpa `ride_requests` yang valid;
- satu pasangan konteks + tipe + partisipan tidak boleh membuat duplicate conversation.

Catatan keputusan: untuk kompatibilitas dengan kode sekarang, `buyer_courier` dapat tetap dipakai sebagai nilai teknis pada fase transisi; label UI boleh menggunakan “Penumpang–Ojek”.

### 5.2 `chat_participants`

```text
conversation_id    uuid references chat_conversations(id) on delete cascade
user_id            uuid not null
role               text not null -- buyer | merchant | courier | passenger
joined_at          timestamptz not null default now()
left_at            timestamptz null
last_read_at       timestamptz null
last_read_message_id uuid null
muted_until        timestamptz null
primary key (conversation_id, user_id)
```

`role` adalah peran dalam conversation, bukan pengganti `user_roles`. Validasi partisipan harus berasal dari relasi domain:

- buyer/merchant harus terkait dengan order;
- passenger/courier harus terkait dengan ride;
- merchant/courier harus terkait dengan order yang memiliki courier tersebut.

### 5.3 `chat_messages`

Target struktur:

```text
id                 uuid primary key
conversation_id    uuid not null references chat_conversations(id) on delete cascade
sender_id          uuid not null
message_type      text not null default 'text'
body               text not null
attachment_path    text null
client_message_id  uuid null
created_at         timestamptz not null default now()
deleted_at         timestamptz null
```

Aturan:

- `body` memiliki batas panjang, misalnya 4.000 karakter;
- `body` di-trim dan tidak boleh kosong;
- `message_type` MVP hanya `text`;
- `attachment_path` baru diaktifkan setelah bucket, MIME allowlist, ukuran maksimum, dan signed URL siap;
- `client_message_id` diberi unique constraint per sender untuk idempotensi retry;
- pesan tidak di-update untuk mengubah isi;
- delete user, bila diperlukan, menggunakan soft delete dan hanya untuk pesan sendiri;
- penghapusan otomatis mengikuti `retention_until` conversation, bukan timer yang melekat pada setiap pesan.

### 5.4 `chat_message_reads` (opsional pada MVP dua pihak, direkomendasikan)

```text
message_id         uuid references chat_messages(id) on delete cascade
user_id            uuid not null
read_at            timestamptz not null default now()
primary key (message_id, user_id)
```

Untuk MVP dua pihak, `chat_participants.last_read_message_id` dapat dipakai agar query ringan. Jika ingin read receipt per pesan atau grup, gunakan `chat_message_reads`.

### 5.5 Notifikasi

Gunakan tabel `notifications` yang sudah ada untuk in-app notification. Notifikasi chat minimal berisi:

```text
type = 'chat'
entity_type = 'chat_conversation'
entity_id = conversation_id
payload = {
  "message_id": "...",
  "sender_id": "...",
  "preview": "..."
}
```

Preview harus dipotong dan tidak menaruh data sensitif. Push notification diproses asynchronous melalui mekanisme push yang sudah ada, bukan menunggu request insert pesan selesai.

## 6. Relasi domain

### 6.1 Pembeli ↔ pedagang

```text
orders.buyer_id = buyer user id
orders.merchant_id -> merchants.id
merchants.user_id = merchant user id
```

Conversation dibuat saat:

- pembeli menekan tombol chat dari detail produk/order; atau
- pedagang membalas conversation yang sudah ada.

Untuk chat dari halaman produk sebelum checkout, produk belum memiliki order. Pilih salah satu keputusan produk berikut sebelum implementasi:

1. **MVP aman:** chat pedagang hanya tersedia setelah order dibuat; atau
2. buat `merchant_inquiries` sebagai konteks pra-order yang berbeda dari order.

Rekomendasi: mulai dari opsi 1 agar RLS sederhana dan chat langsung punya konteks bisnis.

### 6.2 Penumpang ↔ ojek

```text
ride_requests.passenger_id = passenger user id
ride_requests.driver_id -> couriers.id
couriers.user_id = courier user id
```

Conversation dibuat ketika:

- perjalanan berhasil menerima driver; atau
- penumpang membuka chat dari halaman tracking; atau
- driver membuka chat dari perjalanan yang ditugaskan.

Sebelum ada driver yang menerima perjalanan, tidak ada recipient individual. Komunikasi fase `SEARCHING` tetap memakai mekanisme dispatch/ride request, bukan chat broadcast ke semua ojek.

### 6.3 Pedagang ↔ ojek

Conversation hanya boleh dibuat jika kedua pihak terkait dengan order yang sama dan courier sudah ditetapkan. RLS tidak boleh hanya menerima `chat_type` dari client.

## 7. Alur pesan realtime

### 7.1 Membuka conversation

1. Client memanggil `get-or-create` melalui RPC atau query transaction-safe.
2. Server memvalidasi relasi user terhadap order/ride.
3. Server mengembalikan conversation dan participant summary.
4. Client mengambil halaman pesan terbaru dengan cursor.
5. Client subscribe channel `conversation:<conversation_id>`.
6. Client mengirim `presence` join dan menyimpan status koneksi.

RPC `get_or_create_chat_conversation` direkomendasikan agar dua client yang membuka chat bersamaan tidak membuat thread ganda.

### 7.2 Mengirim pesan

1. Client membuat `client_message_id`.
2. Client menampilkan status `sending` secara optimistik.
3. Client insert ke `chat_messages`.
4. RLS memvalidasi `sender_id = auth.uid()` dan membership aktif.
5. Database meng-update `last_message_id` dan `last_message_at` secara transaction-safe.
6. Realtime mengirim `INSERT`.
7. Pengirim mengganti status optimistik menjadi `sent` dengan mencocokkan `client_message_id`.
8. Recipient menerima event, memperbarui daftar pesan, dan membuat/menjadwalkan unread notification.

Jika insert timeout, client melakukan query berdasarkan `client_message_id` sebelum retry agar tidak menggandakan pesan.

### 7.3 Menandai sudah dibaca

Client mengirim update ketika:

- conversation sedang terbuka;
- tab/app terlihat;
- pesan sudah masuk viewport atau user berada di bagian paling bawah.

Jangan menandai semua pesan terbaca hanya karena inbox dibuka. Update read state harus dibatasi ke conversation dan user yang sedang login.

### 7.4 Reconnect dan sinkronisasi

Saat channel berubah ke `TIMED_OUT`, `CLOSED`, atau `CHANNEL_ERROR`:

1. tampilkan indikator “Menghubungkan ulang…”;
2. lakukan backoff bertahap;
3. setelah `SUBSCRIBED`, fetch pesan setelah cursor/`created_at` terakhir;
4. deduplikasi berdasarkan `id`;
5. jangan menghapus histori lokal hanya karena channel reconnect gagal.

## 8. Desain channel Supabase Realtime

### Database changes

Gunakan channel privat per conversation:

```text
private:conversation:<conversation_id>
```

Listen minimal:

- `INSERT` pada `chat_messages`;
- `UPDATE` pada `chat_messages` bila soft delete diaktifkan;
- perubahan participant/read state bila read receipt realtime diperlukan.

Channel harus difilter berdasarkan `conversation_id`, bukan subscribe ke seluruh tabel untuk setiap halaman. Inbox boleh menggunakan satu subscription user-level untuk event yang memang diperlukan, tetapi hasil akhir tetap diverifikasi dengan query RLS.

### Presence

Payload presence minimal:

```json
{
  "user_id": "uuid",
  "role": "buyer|merchant|courier|passenger",
  "last_seen_at": "timestamp"
}
```

Jangan mengirim lokasi GPS atau informasi sensitif melalui presence. Tracking lokasi ojek tetap menggunakan domain/rute yang sudah ada.

### Broadcast typing

Typing indicator memakai Broadcast dan debounce 300–500 ms. Payload tidak disimpan ke database. Hentikan typing setelah timeout maksimal sekitar 3 detik untuk menghindari indikator yang macet.

## 9. Keamanan dan RLS

### Prinsip

- client tidak boleh menentukan sendiri bahwa ia adalah merchant/courier;
- membership dihitung dari `auth.uid()` dan relasi domain;
- service-role hanya dipakai di Edge Function/server process, tidak pernah di bundle browser;
- semua tabel chat memakai RLS;
- realtime private channel memakai policy yang mengizinkan join hanya kepada participant aktif;
- isi pesan tidak boleh terlihat lewat query inbox yang tidak berhak.

### Policy target

#### `chat_conversations`

- `SELECT`: user adalah participant aktif atau admin;
- `INSERT`: hanya melalui RPC yang memvalidasi order/ride;
- `UPDATE`: sistem/admin; user tidak boleh mengubah konteks atau participant;
- `DELETE`: tidak dilakukan oleh user; gunakan archive/retention.

#### `chat_participants`

- `SELECT`: participant dalam conversation yang sama;
- `INSERT/DELETE`: sistem/RPC/admin;
- `UPDATE`: user hanya boleh mengubah `last_read_*`, `muted_until` miliknya sendiri.

#### `chat_messages`

- `SELECT`: participant aktif atau admin;
- `INSERT`: `sender_id = auth.uid()`, participant aktif, conversation aktif, body valid;
- `UPDATE`: tidak boleh mengubah body/sender/context; hanya soft-delete pesan sendiri jika fitur disetujui;
- `DELETE`: admin/job retention, bukan client.

### Abuse controls

Tambahkan sebelum production:

- rate limit per user dan per conversation;
- batas panjang body dan jumlah pesan burst;
- block/report user;
- audit log untuk report, admin access, dan deletion;
- validasi link dan attachment;
- redaksi preview pada push notification;
- expiry/retention sesuai kebutuhan privasi dan kebijakan bisnis.

Rate limiting dapat dimulai dengan Edge Function atau RPC yang mencatat counter terkontrol; jangan mengandalkan JavaScript client.

## 10. Perubahan frontend yang direncanakan

### Komponen domain

Pisahkan logika yang saat ini berada di `OrderChat` menjadi:

- `ChatInboxPage` atau adapter per role;
- `ConversationView`;
- `ConversationHeader`;
- `MessageList` dengan cursor pagination;
- `MessageComposer`;
- `ChatConnectionStatus`;
- `useConversation(conversationId)`;
- `useChatInbox(userId, role)`;
- `useChatPresence(conversationId)`;
- `useTypingIndicator(conversationId)`.

Komponen per role hanya menentukan query konteks dan label. Pengiriman, pagination, reconnect, deduplikasi, dan read receipt berada di shared chat domain.

### Navigasi dan entry point

Pertahankan route yang sudah ada agar tidak memecahkan bookmark:

- `/buyer/chat`;
- `/merchant/chat`;
- `/courier/chat`.

Tambahkan pembukaan conversation dari:

- order detail/tracking;
- ride tracking;
- detail percakapan inbox.

Pada fase migrasi, `OrderChat` dapat menjadi adapter yang memanggil `get-or-create` lalu merender `ConversationView`.

### State UI minimum

- loading history;
- empty conversation;
- sending/sent/failed;
- offline/reconnecting;
- unread badge;
- read receipt;
- online/typing bila tersedia;
- closed/expired conversation;
- error yang dapat dicoba ulang.

## 11. Migrasi bertahap

### Fase 0 — keputusan produk dan kontrak

- tentukan apakah chat hanya setelah order/ride aktif;
- tetapkan retensi chat;
- tetapkan batas panjang dan rate limit;
- pilih istilah UI: pedagang, pembeli, ojek, penumpang;
- tetapkan apakah image/attachment masuk MVP.

**Output:** kontrak domain dan acceptance criteria.

### Fase 1 — schema foundation

- buat `chat_conversations` dan `chat_participants`;
- tambahkan `conversation_id` nullable pada `chat_messages`;
- buat RPC `get_or_create_chat_conversation`;
- tambahkan index `(conversation_id, created_at desc)`;
- tambahkan policy RLS dan policy realtime private channel;
- tetap pertahankan kolom legacy `order_id`, `receiver_id`, `chat_type` sementara.

**Output:** conversation baru dapat dibuat aman tanpa memutus chat lama.

### Fase 2 — backfill

- buat satu conversation untuk setiap kombinasi unik order/ride + tipe + pasangan yang valid;
- isi participants dari relasi domain, bukan dari data client;
- backfill `conversation_id` pada pesan lama;
- verifikasi pesan orphan dan relasi yang tidak valid;
- simpan laporan migrasi sebelum menghapus kolom legacy.

**Output:** seluruh histori yang dipertahankan memiliki conversation id.

### Fase 3 — shared frontend

- pindahkan query/listener dari `OrderChat` ke repository/hook shared;
- gunakan cursor pagination;
- gunakan `client_message_id` dan optimistic state;
- pasang private channel per conversation;
- pertahankan route dan adapter lama selama rollout.

**Output:** buyer, merchant, dan courier memakai alur shared.

### Fase 4 — ride chat

- tambahkan `ride_request_id` sebagai konteks resmi;
- buat passenger–courier conversation setelah driver ditetapkan;
- integrasikan ke `RideTrackingPage` dan halaman riwayat;
- tambahkan unread badge ke alur penumpang dan ojek.

**Output:** chat ojek berjalan tanpa menyalahgunakan `order_id`.

### Fase 5 — hardening dan cleanup

- aktifkan rate limit, report/block, dan monitoring;
- uji reconnect, duplicate retry, dan RLS matrix;
- aktifkan push notification yang idempotent;
- tetapkan retention job yang aman;
- hapus fallback legacy hanya setelah seluruh client dan data tervalidasi.

## 12. Indeks dan performa

Indeks minimum:

```text
chat_participants(user_id, left_at)
chat_messages(conversation_id, created_at desc, id desc)
chat_messages(sender_id, created_at desc)
chat_conversations(last_message_at desc)
chat_conversations(order_id, conversation_type)
chat_conversations(ride_request_id, conversation_type)
```

Pagination harus memakai keyset cursor `(created_at, id)`, bukan offset. Batasi pesan awal, misalnya 30–50 pesan, dan muat histori lama saat scroll ke atas.

Inbox tidak boleh membaca seluruh tabel pesan untuk setiap render. Gunakan `last_message_id/last_message_at` pada conversation dan aggregate unread yang terkontrol.

## 13. Notifikasi

### In-app

- event insert pesan memperbarui badge jika recipient tidak sedang membaca conversation;
- notification ditautkan ke conversation;
- membuka conversation meng-mark read secara eksplisit;
- notification tidak dibuat berulang untuk retry pesan yang sama.

### Push

Alur yang direkomendasikan:

```text
INSERT message
  → database trigger/queue event
  → process-notification-queue / push function
  → push recipient jika tidak sedang aktif di conversation
```

Push body menggunakan nama pengirim + preview pendek + konteks “Pesanan” atau “Perjalanan”. Detail sensitif tidak dimasukkan ke notification saat layar terkunci.

## 14. Observability

Catat metrik tanpa menyimpan isi pesan:

- waktu insert pesan sampai event diterima;
- persentase subscription `SUBSCRIBED`;
- jumlah `CHANNEL_ERROR`, `TIMED_OUT`, reconnect;
- insert gagal per alasan;
- duplicate retry yang berhasil dideduplikasi;
- unread notification delivery;
- query latency inbox dan history;
- jumlah conversation aktif per konteks.

Log tidak boleh memuat body pesan, token, atau URL signed attachment.

## 15. Acceptance criteria MVP

### Pembeli–pedagang

- pembeli dapat membuka/melanjutkan satu conversation untuk order;
- pedagang hanya melihat conversation order yang menjadi miliknya;
- pesan muncul di tab lawan tanpa refresh;
- refresh/reconnect tidak menggandakan pesan;
- unread count bertambah untuk recipient yang tidak sedang membuka conversation;
- read receipt berubah hanya setelah recipient melihat pesan;
- user tanpa relasi order mendapat `403`/hasil kosong sesuai kontrak, bukan data.

### Penumpang–ojek

- conversation hanya tersedia setelah courier ditetapkan;
- penumpang dan courier dapat mengirim pesan dua arah;
- merchant tidak dapat membaca chat ride;
- perubahan status ride tidak otomatis menghapus histori sebelum retention;
- ride yang selesai dapat ditutup sesuai kebijakan, dengan histori tetap terbaca sampai retention.

### Reliability

- reconnect melakukan catch-up dari cursor;
- retry aman dengan `client_message_id`;
- channel dibersihkan saat unmount/navigation;
- ada fallback error ketika Realtime tidak tersedia;
- direct database query tetap dibatasi RLS.

## 16. Matriks pengujian wajib

| Area | Skenario |
|---|---|
| Auth | anonymous, buyer, merchant, courier, admin |
| RLS | participant valid, user tidak terkait, user terkait order lain, user terkait ride lain |
| Delivery | dua tab, tab background, reload setelah event, network reconnect |
| Idempotensi | double click send, timeout lalu retry, duplicate realtime event |
| Read | membuka inbox, membuka detail, scroll, dua device user yang sama |
| Lifecycle | order selesai, ride selesai, cancelled, retention expiry |
| Abuse | body kosong, body terlalu panjang, burst rate, spoof sender/receiver |
| UI | mobile, keyboard Enter, loading, offline, error, empty state |

## 17. Risiko dan keputusan terbuka

1. **Chat pra-order:** belum ada konteks order. Rekomendasi MVP: tunda sampai order dibuat.
2. **Retensi:** auto-delete 3 jam yang ada sekarang perlu keputusan bisnis; jangan bawa default itu ke ride chat tanpa persetujuan.
3. **Lampiran:** `image_url` lama belum cukup untuk attachment aman. Lebih baik gunakan Storage path + signed URL dan validasi server.
4. **Multi-device:** read state perlu diputuskan apakah per user atau per device. Rekomendasi: per user.
5. **Admin access:** admin boleh support/debug, tetapi setiap akses isi pesan harus diaudit.
6. **Group chat:** model participant mendukungnya, tetapi UI dan unread policy grup bukan bagian MVP.
7. **Moderasi:** report/block dan filtering konten perlu diprioritaskan sebelum chat dibuka lebih luas.
8. **Istilah domain:** teknis saat ini memakai `buyer_courier`; UI perlu konsisten menggunakan “penumpang–ojek” untuk ride.

## 18. Urutan implementasi yang direkomendasikan

Urutan paling aman:

1. sepakati keputusan terbuka nomor 1–3;
2. implementasikan schema foundation + RLS;
3. backfill dan validasi data legacy;
4. migrasikan order chat ke shared conversation view;
5. tambahkan ride chat;
6. tambahkan push, attachment, report/block, dan hardening;
7. jalankan acceptance matrix dan ukur Realtime di staging sebelum production.

Jangan menghapus `chat_messages` legacy atau mengganti seluruh route sebelum fase backfill dan dual-read berhasil diverifikasi.