# Audit Kesiapan Chat Realtime Dua Arah SaDesa

**Tanggal audit:** 9 September 2026  
**Repositori:** `bonangpanjinur/Sadesa-fix`  
**Cakupan:** pembeli–pedagang, pembeli–kurir/ojek, pedagang–kurir/ojek, serta retensi soft delete 2 minggu dan hard delete 1 bulan.

## Ringkasan eksekutif

Repositori sudah memiliki fondasi yang cukup baik untuk chat dua arah berbasis Supabase: tabel `chat_messages`, model tambahan `chat_conversations`/`chat_participants`, Realtime PostgreSQL Changes, RPC pembuatan percakapan, unread/read state, rate limit dasar, notifikasi in-app, serta fallback legacy selama migrasi.

Namun, fitur ini **belum production-ready**. Penilaian keseluruhan adalah **4,5/10 — prototype/controlled staging**, bukan siap dibuka luas. Risiko terbesar adalah:

1. **P0 — Direct buyer–merchant berpotensi mencampur banyak pembeli dalam satu conversation.** Migration `33_20260909100000_direct_chat_realtime.sql` membuat unique key hanya `(merchant_id, conversation_type)`, tanpa `buyer_id` atau pasangan partisipan. Akibatnya seluruh pembeli yang menghubungi merchant yang sama dapat diarahkan ke thread yang sama; RPC juga menambahkan caller baru sebagai participant pada thread tersebut.
2. **P0 — Retensi yang diminta belum tersedia.** Tidak ada implementasi soft delete pada hari ke-14 dan hard delete pada hari ke-30. `retention_until` tidak diisi oleh alur pembuatan conversation, cleanup canonical hanya melakukan hard delete saat `retention_until` tercapai, dan tidak terlihat scheduler/cron yang menjalankan `cleanup_expired_chats()`.
3. **P1 — RLS update legacy terlalu longgar.** Policy lama `Users can update own messages read status` hanya memakai `USING (auth.uid() = receiver_id)` tanpa `WITH CHECK` dan tanpa membatasi kolom. Receiver berpotensi mengubah `message`, `sender_id`, `receiver_id`, `conversation_id`, atau metadata lain, bukan hanya status baca.
4. **P1 — Realtime belum menjamin catch-up.** Listener percakapan menangani INSERT dan deduplikasi ID, tetapi belum melakukan refetch berbasis cursor setelah `TIMED_OUT`, `CLOSED`, atau `CHANNEL_ERROR`. Dokumen arsitektur sudah merekomendasikan perilaku ini, tetapi implementasi belum lengkap.
5. **P1 — Inbox buyer/merchant/courier masih melakukan query seluruh `chat_messages` dan menghitung thread di browser.** Ini berisiko terhadap performa, unread consistency, dan pagination ketika volume bertambah.
6. **P1 — Chat ride dan inbox courier belum konsisten.** Modal `OrderChat` mendukung konteks `ride`, tetapi halaman inbox courier masih hanya mengambil pesan dengan `order_id` non-null. Percakapan passenger–courier yang berbasis `ride_request_id` tidak akan masuk daftar inbox courier.

## Skor kesiapan per relasi

| Relasi | Status saat ini | Skor | Alasan utama |
|---|---:|---:|---|
| Pembeli ↔ pedagang berbasis order | Berfungsi terbatas di staging | 6/10 | RPC conversation dan listener ada; masih bergantung pada legacy fields, query inbox lebar, read/update policy berisiko, belum ada retention baru. |
| Pembeli ↔ pedagang direct/pra-order | **Tidak aman** | 2/10 | Unique conversation hanya per merchant, bukan per pasangan buyer–merchant; risiko kebocoran antar-pembeli. |
| Pembeli/penumpang ↔ kurir/ojek berbasis order | Berfungsi terbatas | 5/10 | Domain participant order tersedia dan UI modal mendukung chat; inbox dan konteks masih memakai adapter/order legacy. |
| Penumpang ↔ ojek berbasis ride | Belum lengkap | 4/10 | `ride_request_id`, RPC, dan `passenger_courier` ada; inbox courier tidak mengambil ride conversation, dan lifecycle/retention belum selesai. |
| Pedagang ↔ kurir/ojek berbasis order | Berfungsi terbatas | 5/10 | RLS domain order tersedia dan tab UI ada; pengelompokan thread courier masih key legacy `order_id-chat_type`, bukan conversation stabil. |
| Realtime delivery/reconnect | Partial | 5/10 | Subscribe INSERT dan cleanup channel ada; belum ada reliable cursor catch-up setelah reconnect. |
| Retensi & deletion | **Tidak siap** | 1/10 | Belum ada soft-delete 14 hari, hard-delete 30 hari, metadata deletion, atau scheduler yang terbukti berjalan. |

## Arsitektur yang ditemukan

### Frontend

Komponen utama masih dipusatkan di `src/components/chat/OrderChat.tsx`. Komponen ini menangani pengambilan history, membuka/membuat conversation, fallback ke query legacy, subscribe Realtime, optimistic-ish append setelah insert, mark read, notifikasi suara, quick replies, serta seluruh rendering modal.

Repository `src/lib/chat/repository.ts` sudah menyediakan abstraction untuk:

- `getOrCreateConversation`;
- `getOrCreateDirectConversation`;
- `listConversationMessages`;
- `sendConversationMessage` dengan `client_message_id`;
- `markConversationRead`;
- unread count;
- subscribe per conversation.

Halaman `BuyerChatPage`, `MerchantChatPage`, dan `CourierChatPage` masih mengambil `chat_messages` secara langsung, lalu membangun daftar thread di client. Ini membuat shared repository belum menjadi satu-satunya source of truth.

### Backend/database

Migration `18_20260907040000_live_chat_realtime.sql` menambahkan:

- `chat_conversations` dengan konteks order/ride;
- `chat_participants` dengan peran dan read cursor;
- `conversation_id`, `body`, `message_type`, `client_message_id`, `deleted_at`;
- `chat_message_reads`;
- RPC `get_or_create_chat_conversation`;
- RPC `mark_chat_conversation_read` dan `get_chat_unread_count`;
- trigger update `last_message_at`;
- rate limit dasar 30 pesan/menit per sender;
- trigger notifikasi;
- RLS canonical dan publication Realtime.

Migration `32` memperbaiki trigger notifikasi PostgreSQL. Migration `33` menambahkan direct buyer–merchant, tetapi desain unique key-nya tidak cukup untuk percakapan dua pihak.

## Temuan rinci berdasarkan area

### 1. Identitas conversation dan isolasi data — P0

Pada `33_20260909100000_direct_chat_realtime.sql`:

```sql
CREATE UNIQUE INDEX ...
  ON public.chat_conversations(merchant_id, conversation_type)
  WHERE context_type = 'direct' AND merchant_id IS NOT NULL;
```

RPC `get_or_create_direct_chat(p_merchant_id)` melakukan `ON CONFLICT` pada key tersebut, kemudian menambahkan `auth.uid()` dan merchant sebagai participant. Tidak ada identitas buyer pada conversation atau unique index. Dengan RLS canonical yang mengizinkan participant aktif membaca seluruh pesan pada conversation, buyer kedua yang menghubungi merchant yang sama dapat menjadi participant pada thread yang sudah dipakai buyer pertama.

**Perbaikan wajib:** direct conversation harus memiliki `buyer_user_id` pada `chat_conversations`, atau model yang lebih konsisten harus memakai tabel pasangan participant dan unique index yang merepresentasikan merchant + buyer + conversation type. RPC harus mengunci dan memvalidasi tepat dua pihak. Tambahkan test RLS: Buyer A tidak boleh SELECT pesan Buyer B walaupun merchant sama.

### 2. Otorisasi participant

Untuk chat order, `chat_domain_participants()` sudah menghitung buyer/merchant/courier dari relasi order. Untuk ride, passenger dan courier dihitung dari `ride_requests`. Ini arah yang benar.

Kekurangan:

- direct chat memakai participant yang berasal dari RPC, tetapi desain context tidak menyimpan buyer secara eksplisit;
- `get_or_create_chat_conversation` melakukan SELECT conversation lalu INSERT tanpa pola yang sepenuhnya transaction-safe terhadap race; unique index membantu, tetapi perlu menangani unique conflict dan mengambil ulang row secara deterministik;
- aturan `chat_conversations` hanya mendukung `order` dan `ride` pada migration 18, lalu migration 33 mengubahnya menjadi `direct`; bundle penerapan harus diverifikasi urutannya pada staging;
- status conversation `closed` belum terlihat ditegakkan pada seluruh alur UI dan insert selain check status pada policy canonical.

### 3. RLS dan mutasi pesan — P1

Migration legacy membuat policy UPDATE:

```sql
USING (auth.uid() = receiver_id)
```

Tanpa pembatasan kolom dan tanpa `WITH CHECK`, policy ini tidak setara dengan “hanya boleh menandai read”. Walaupun policy canonical INSERT/SELECT sudah lebih baik, policy lama tetap berbahaya selama dual-read/dual-write berlangsung.

**Perbaikan wajib:**

- cabut policy UPDATE legacy atau ganti dengan RPC `mark_chat_conversation_read` saja;
- jika UPDATE tetap dipertahankan, batasi melalui view/RPC atau trigger yang menolak perubahan terhadap `sender_id`, receiver, body, conversation, context, timestamp, dan `deleted_at`;
- jangan izinkan client mengirim `sender_id`/`receiver_id` sebagai sumber kebenaran; sender harus `auth.uid()`, recipient/participant dihitung server-side.

### 4. Realtime dan recovery — P1

Kelebihan implementasi:

- channel dibersihkan saat unmount;
- filter conversation tersedia di `subscribeToConversation`;
- deduplikasi berdasarkan message ID dilakukan saat append;
- status koneksi ditampilkan sebagai “Menghubungkan ulang…”;
- inbox buyer mencatat status realtime dan menyediakan tombol coba lagi.

Gap:

- setelah reconnect belum ada fetch pesan setelah cursor terakhir;
- listener inbox melakukan refetch penuh saat INSERT, bukan update conversation summary secara incremental;
- tidak ada subscription UPDATE untuk soft delete;
- channel bersifat `supabase.channel(...)` tanpa bukti private-channel authorization untuk participant join;
- status `connected` setelah event INSERT bukan bukti channel tetap subscribed;
- event realtime belum diperlakukan sebagai delivery hint yang harus direkonsiliasi dengan database.

**Acceptance test wajib:** kirim saat tab background, putuskan jaringan, reconnect, reload, dan pastikan tidak ada missing message/duplicate message.

### 5. UI/UX

Yang sudah tersedia:

- inbox terpisah buyer, merchant, courier;
- tab filter relasi;
- unread badge;
- timestamp dan label peran;
- modal conversation mobile-friendly;
- quick replies;
- indikator status koneksi;
- sound notification toggle;
- error state untuk sebagian kegagalan.

Yang belum siap untuk kualitas produksi:

- pagination/cursor untuk history dan inbox;
- status pesan `sending`, `sent`, `failed`, retry per pesan;
- typing indicator/presence yang disebut pada arsitektur belum diimplementasikan;
- read receipt masih campuran antara `is_read` legacy dan `chat_message_reads` canonical;
- empty/loading/error state belum seragam antar role;
- tidak ada indikator conversation closed/expired yang operasional;
- modal belum menunjukkan tanggal/jam retensi yang pasti; teks hanya “akan dihapus otomatis setelah pesanan selesai”;
- aksesibilitas masih kurang: overlay tidak terlihat memiliki dialog semantics, focus trap, `aria-label` untuk tombol icon, dan keyboard escape handling;
- input Enter belum membedakan Enter dari Shift+Enter dan belum memiliki batas karakter/indikator batas;
- belum ada attachment aman, report, block, atau moderasi;
- notifikasi diarahkan hard-coded ke `/buyer/chat`, sehingga deep-link merchant/courier/ride dapat salah konteks.

### 6. Coverage tiga relasi bisnis

**Pembeli–pedagang:** order chat memiliki relasi domain yang paling lengkap. Direct chat baru ditambahkan dan justru menjadi risiko tertinggi. Pra-order perlu dipastikan apakah memang kebutuhan; jika iya, gunakan model direct yang benar-benar pair-scoped.

**Pembeli–kurir/ojek:** order-based buyer–courier tersedia. Ride-based passenger–courier telah memiliki RPC dan tipe `passenger_courier`, tetapi belum menjadi pengalaman inbox yang konsisten.

**Pedagang–kurir/ojek:** order-based participant dan tab merchant/courier tersedia. Tidak boleh mengandalkan `chat_type` dari client; server harus memvalidasi bahwa kurir memang ditugaskan pada order merchant tersebut. Ini sudah menjadi arah pada `chat_domain_participants`, tetapi test staging matrix belum ditemukan.

**Kurir/ojek–pemesan/pembeli:** secara produk ini seharusnya satu capability passenger–courier yang sama, bukan fitur terpisah. UI dan data sebaiknya memakai istilah yang konsisten: “Penumpang–Ojek” untuk ride dan “Pembeli–Kurir” untuk order delivery.

### 7. Retensi: kebutuhan 14 hari soft delete, 30 hari hard delete

Kebutuhan yang harus diterapkan secara eksplisit:

| Umur relatif terhadap pesan/conversation | Tindakan | Visibilitas |
|---|---|---|
| Hari 0–13 | Aktif/normal | Pengirim dan participant aktif dapat membaca |
| Hari 14–29 | Soft delete | Isi tidak ditampilkan ke user; row masih ada untuk audit/rekonsiliasi dengan `deleted_at` dan `deleted_reason` |
| Hari 30+ | Hard delete | Row pesan dan attachment metadata dihapus permanen sesuai policy |

Rekomendasi implementasi:

- gunakan `created_at` pesan sebagai dasar expiry; jangan bergantung hanya pada order selesai;
- tambahkan `soft_delete_at`/`deleted_at`, `hard_delete_at` atau hitung deterministik dari `created_at`, serta `deleted_reason`;
- trigger atau job saat pesan dibuat mengisi `soft_delete_at = created_at + interval '14 days'` dan `hard_delete_at = created_at + interval '30 days'`;
- job terjadwal idempotent menjalankan soft delete untuk pesan yang jatuh tempo dan hard delete untuk pesan yang telah melewati 30 hari;
- soft delete harus mengosongkan/redaksi `body` dan attachment reference bila kebijakan privasi mengharuskannya, atau memakai placeholder “Pesan dihapus otomatis”;
- query user selalu memakai `deleted_at IS NULL`; query admin/audit dipisahkan dan diaudit;
- Realtime harus mendengarkan UPDATE soft delete agar layar lawan mengganti isi pesan tanpa refresh;
- hard delete harus menghapus object Storage terkait memakai path terverifikasi, bukan URL publik;
- cleanup lama `auto_delete_at` 3 jam setelah order selesai harus dihentikan atau dimigrasikan agar tidak bertentangan dengan kontrak 14/30 hari;
- job harus punya observability: jumlah soft-deleted, hard-deleted, error, dan oldest pending item;
- lakukan legal/privacy sign-off untuk pengecualian dispute, fraud, chargeback, atau kewajiban pencatatan.

Saat ini `cleanup_expired_chats()` hanya hard-delete row canonical berdasarkan `retention_until`, dan legacy row berdasarkan `auto_delete_at`. Tidak terlihat pengisian `retention_until` atau bukti scheduler. Dengan demikian kebutuhan pengguna **belum terpenuhi**.

## Risiko performa dan skalabilitas

Inbox saat ini melakukan SELECT banyak pesan lalu grouping di browser. Pola ini tidak akan skala dengan jumlah order/pesan besar dan dapat menampilkan ringkasan yang salah ketika soft-deleted messages, duplicate messages, atau multi-device read state masuk.

Target production:

- inbox dari `chat_conversations` dengan `last_message_id`, `last_message_at`, participant relation, dan aggregate unread;
- history keyset pagination `(created_at, id)` 30–50 pesan per page;
- index `(conversation_id, created_at DESC, id DESC)` yang sudah ada dipertahankan;
- filter participant dilakukan server-side melalui RLS/RPC;
- unread dihitung dari read cursor atau `chat_message_reads`, bukan campuran field legacy;
- load test minimal untuk 2 tab × 3 role, reconnect, 30 msg/min limit, dan inbox 1.000+ message rows.

## Pengujian yang belum terbukti

Validasi lokal tidak berjalan karena dependency belum terpasang di clone (`node_modules` tidak tersedia): `tsc`, ESLint, dan Vitest tidak dapat dieksekusi. Ini bukan bukti source gagal, tetapi berarti hasil audit belum mendapat bukti build/test lokal.

Matrix staging wajib:

| Area | Skenario minimum |
|---|---|
| Isolasi | Buyer A/B ke merchant sama; order berbeda; ride berbeda; merchant/courier tidak terkait |
| RLS | SELECT/INSERT/UPDATE/DELETE oleh buyer, merchant, courier, passenger, admin, anonymous |
| Direct chat | Dua buyer membuka merchant sama secara bersamaan; pastikan dua conversation berbeda |
| Realtime | Dua tab, background tab, offline 30 detik, reconnect, reload setelah event |
| Idempotensi | Double click, timeout setelah commit, retry dengan client ID sama |
| Read | Dua device user sama, scroll viewport, inbox dibuka tanpa membuka detail |
| Lifecycle | Order selesai, ride selesai, cancelled, conversation closed |
| Retensi | Simulasikan H+13, H+14, H+29, H+30; verifikasi UI, DB, Storage, audit |
| Abuse | Body kosong, >4.000 karakter, burst >30/menit, spoof sender/receiver, mutation body melalui UPDATE |
| UI | Mobile keyboard, Shift+Enter, screen reader, Escape, loading/error/offline, retry |

## Rencana remediasi prioritas

### P0 — sebelum staging dibuka untuk pengguna

1. Perbaiki direct conversation menjadi pair-scoped buyer–merchant; tambahkan regression RLS test untuk cross-buyer leakage.
2. Cabut/fix legacy UPDATE policy agar hanya read state dapat berubah.
3. Tetapkan satu kontrak retention 14/30 hari dan hentikan default 3 jam yang bertentangan.
4. Implementasikan soft-delete/hard-delete job idempotent serta verifikasi scheduler.

### P1 — sebelum pilot luas

1. Satukan inbox ke query conversation server-side; hilangkan SELECT seluruh message table dari tiga halaman.
2. Tambahkan reconnect catch-up berbasis cursor dan listener UPDATE soft-delete.
3. Integrasikan ride conversation ke inbox buyer dan courier; pastikan merchant tidak dapat membaca ride chat.
4. Hilangkan ketergantungan client pada `receiver_id`/`chat_type` untuk authorization.
5. Tambahkan retry state, failed message action, closed state, dan deep-link notification per role.
6. Aktifkan private Realtime channel authorization dan uji membership.

### P2 — hardening produksi

1. Typing indicator/presence dengan TTL, tanpa GPS/sensitive payload.
2. Attachment melalui private Storage bucket, MIME/size allowlist, signed URL, dan cleanup object.
3. Report/block/moderation dan audit admin access.
4. Observability latency, subscription failures, reconnect, duplicate recovery, unread delivery, cleanup lag.
5. Accessibility pass pada dialog, focus management, labels, keyboard behavior, dan contrast.

## Verdict akhir

**Belum siap produksi untuk seluruh requirement yang diminta.** Order chat dua arah sudah memiliki fondasi yang dapat dilanjutkan di staging, tetapi direct buyer–merchant harus dianggap **blocked** sampai isolasi conversation diperbaiki. Ride chat juga **partial** sampai inbox courier/buyer dan lifecycle ride terintegrasi. Retensi 14 hari soft delete + 30 hari hard delete adalah **belum diimplementasikan**, bukan sekadar belum ditampilkan di UI.

Urutan aman adalah: perbaiki isolasi direct chat → kunci RLS mutation → implementasi retention job → migrasikan inbox ke conversation summary → tambah reconnect/catch-up dan ride inbox → jalankan matrix RLS/realtime/retention di staging → baru pilot terbatas.

## Referensi bukti source

- `src/components/chat/OrderChat.tsx`
- `src/lib/chat/repository.ts`
- `src/pages/buyer/BuyerChatPage.tsx`
- `src/pages/merchant/MerchantChatPage.tsx`
- `src/pages/courier/CourierChatPage.tsx`
- `src/hooks/useChatUnread.ts`
- `supabase/bootstrap/04_20260208054918_to_20260220105922.sql`
- `supabase/bootstrap/05_20260220110705_to_20260508000000.sql`
- `supabase/bootstrap/18_20260907040000_live_chat_realtime.sql`
- `supabase/bootstrap/32_20260908190000_chat_notification_trigger_repair.sql`
- `supabase/bootstrap/33_20260909100000_direct_chat_realtime.sql`
- `docs/architecture/arsitektur-live-chat-realtime.md`

> Catatan: audit ini menilai source dan migration yang ada di repository. Kesiapan staging/production tetap memerlukan verifikasi bahwa bootstrap bundle yang sama sudah diterapkan, RLS/realtime publication benar-benar aktif, scheduler cleanup benar-benar berjalan, dan seluruh test matrix lulus.

---

**Status rekomendasi:** Blocked for broad production rollout; proceed only with P0 remediation and controlled staging tests.

