# Rencana Perbaikan dan Pembangunan Chat Realtime SaDesa

**Tanggal:** 9 September 2026  
**Basis:** Audit kesiapan chat realtime SaDesa  
**Target:** Chat dua arah yang aman dan dapat dioperasikan untuk pembeli–pedagang, pembeli–kurir, penumpang–ojek, serta pedagang–kurir.

## 1. Keputusan utama

Pembangunan dilakukan secara bertahap. **Perbaikan keamanan dan isolasi data harus selesai sebelum fitur chat diperluas.** Implementasi tidak boleh langsung menambahkan fitur UI baru di atas model direct chat yang sekarang karena model tersebut berpotensi mencampur percakapan beberapa pembeli pada merchant yang sama.

Arsitektur target menggunakan `chat_conversations` sebagai identitas thread, `chat_participants` sebagai sumber kebenaran anggota, `chat_messages` sebagai log pesan immutable, dan `chat_message_reads` atau read cursor sebagai sumber kebenaran status baca.

Retensi menjadi kebijakan berbasis pesan:

- Hari 0–13: pesan normal dan terbaca oleh participant yang berhak.
- Hari 14–29: pesan di-soft-delete dan isi tidak ditampilkan ke user.
- Hari 30 ke atas: row pesan di-hard-delete secara permanen, termasuk attachment yang terkait.

Pengecualian untuk dispute, fraud, chargeback, atau kewajiban hukum harus menjadi keputusan bisnis/legal terpisah sebelum retention job diaktifkan pada production.

## 2. Sasaran hasil akhir

Pada akhir proyek, sistem harus memenuhi kondisi berikut:

1. Setiap conversation hanya dapat diakses oleh participant yang sah berdasarkan relasi order atau ride.
2. Direct buyer–merchant selalu unik untuk pasangan buyer dan merchant.
3. Buyer–merchant, buyer–courier, passenger–courier, dan merchant–courier memakai domain chat bersama.
4. Chat ride memakai `ride_request_id`, bukan menyalahgunakan `order_id`.
5. Pesan baru diterima realtime tanpa refresh pada koneksi normal.
6. Reconnect melakukan catch-up dari cursor agar pesan tidak hilang.
7. Retry tidak menggandakan pesan karena menggunakan `client_message_id` idempotent.
8. Read receipt konsisten antara inbox, detail conversation, dan multi-device.
9. Soft delete berjalan pada hari ke-14 dan hard delete pada hari ke-30.
10. Semua operasi deletion, admin access, dan error cleanup dapat diaudit tanpa mencatat isi pesan.
11. Inbox tidak membaca seluruh tabel pesan untuk setiap render.
12. UI memiliki state loading, empty, sending, sent, failed, retry, offline, reconnecting, closed, expired, dan deleted.

## 3. Prioritas dan gate

| Gate | Fokus | Status sebelum gate dibuka |
|---|---|---|
| Gate 0 | Kontrak produk dan retention | Keputusan participant, konteks, istilah, dan 14/30 hari disetujui |
| Gate 1 | Security foundation | Direct chat terisolasi, RLS mutation dikunci, regression test lulus |
| Gate 2 | Canonical data migration | Backfill dan dual-read tervalidasi tanpa orphan atau leakage |
| Gate 3 | Shared chat frontend | Semua role menggunakan repository/hook bersama |
| Gate 4 | Realtime reliability | Reconnect, catch-up, retry, dan deduplikasi lulus |
| Gate 5 | Retention operations | Soft/hard delete, scheduler, storage cleanup, dan monitoring lulus |
| Gate 6 | Pilot readiness | E2E lintas role, load test, security review, dan rollback plan lulus |

**Aturan:** Jika Gate 1 belum lulus, direct chat tidak boleh dibuka untuk pengguna luas. Jika Gate 5 belum lulus, chat tidak boleh dianggap memenuhi kebijakan retensi.

## 4. Roadmap fase pembangunan

### Fase 0 — Kontrak produk dan desain final

**Tujuan:** Menghapus keputusan ambigu sebelum migration baru dibuat.

Produk harus menetapkan apakah buyer–merchant direct chat hanya boleh setelah order atau juga sebelum order. Rekomendasi untuk tahap pertama adalah direct pra-order tetap tersedia, tetapi menggunakan conversation pair-scoped yang terpisah dari order. Istilah UI ditetapkan sebagai “Pembeli”, “Pedagang”, “Kurir”, dan “Penumpang–Ojek”.

| Pekerjaan | Hasil |
|---|---|
| Tetapkan konteks conversation: `order`, `ride`, `direct` | Kontrak domain |
| Tetapkan participant untuk setiap tipe | Matriks otorisasi |
| Tetapkan retention 14/30 hari | Policy tertulis |
| Tetapkan batas pesan 4.000 karakter dan 30 pesan/menit | Kontrak abuse control |
| Tetapkan attachment sebagai fase lanjutan | MVP tetap text-only |
| Tetapkan admin access dan pengecualian legal | Approval bisnis/legal |

**Acceptance criteria:** tidak ada tipe chat yang belum memiliki aturan siapa yang boleh membuat, membaca, mengirim, menutup, dan menghapus.

### Fase 1 — Perbaikan P0 keamanan dan direct chat

**Tujuan:** Menutup risiko kebocoran data sebelum pengembangan lain.

Migration baru harus menambahkan identitas buyer pada direct conversation, misalnya `buyer_user_id uuid references auth.users(id)`. Unique index harus merepresentasikan pasangan buyer–merchant, bukan hanya merchant:

```sql
CREATE UNIQUE INDEX chat_direct_pair_uidx
ON public.chat_conversations (buyer_user_id, merchant_id, conversation_type)
WHERE context_type = 'direct' AND status <> 'archived';
```

RPC `get_or_create_direct_chat` harus memvalidasi bahwa caller adalah buyer yang sah, mengambil user merchant dari `merchants`, melakukan upsert berdasarkan pasangan tersebut, dan mengisi tepat dua participant. Merchant tidak boleh dapat menambahkan buyer lain melalui client.

Pekerjaan lain pada fase ini:

- menonaktifkan atau mengganti legacy UPDATE policy yang terlalu longgar;
- menolak perubahan `sender_id`, `receiver_id`, `body`, `conversation_id`, konteks, dan timestamp setelah insert;
- mempertahankan read update hanya melalui `mark_chat_conversation_read`;
- menambahkan test cross-buyer leakage;
- memastikan Realtime channel hanya dapat dijoin participant aktif.

**Acceptance criteria:** Buyer A dan Buyer B yang menghubungi merchant sama memperoleh dua conversation berbeda. Buyer A tidak dapat membaca, menerima event, atau menandai read pesan Buyer B.

### Fase 2 — Canonical schema dan migrasi data

**Tujuan:** Menjadikan conversation sebagai sumber kebenaran tanpa memutus histori.

Schema target mempertahankan compatibility sementara, tetapi seluruh data baru harus canonical.

Perubahan yang diperlukan:

| Entitas | Perubahan |
|---|---|
| `chat_conversations` | Tambah `buyer_user_id` untuk direct, `retention_policy`, `retention_started_at`, `closed_at`, `last_message_*`, dan status yang konsisten |
| `chat_participants` | Pertahankan role, `left_at`, `last_read_at`, dan `last_read_message_id` |
| `chat_messages` | Jadikan `conversation_id` wajib setelah backfill, tambah retention/deletion metadata, pertahankan legacy fields hanya selama rollout |
| `chat_message_reads` | Gunakan sebagai read receipt canonical atau tetapkan read cursor sebagai satu-satunya sumber kebenaran |
| `chat_message_attachments` | Tunda ke fase attachment; jangan gunakan public URL pada MVP |

Backfill harus membuat satu conversation per kombinasi konteks dan tipe yang valid. Data dengan participant tidak valid harus masuk laporan quarantine, bukan dipaksa masuk conversation. Setelah dual-read tervalidasi, client baru tidak boleh menulis ke jalur legacy.

**Acceptance criteria:** semua pesan yang dipertahankan memiliki `conversation_id`, semua conversation memiliki participant valid, tidak ada orphan, dan jumlah pesan sebelum/sesudah backfill dapat direkonsiliasi.

### Fase 3 — RLS, RPC, dan abuse control

**Tujuan:** Memindahkan otorisasi final ke database.

RPC yang dipertahankan atau dibangun:

- `get_or_create_chat_conversation`;
- `get_or_create_direct_chat`;
- `send_chat_message` atau insert canonical dengan trigger validasi;
- `mark_chat_conversation_read`;
- `get_chat_unread_count`;
- `soft_delete_expired_chat_messages`;
- `hard_delete_expired_chat_messages`.

Policy target:

- SELECT conversation/message hanya untuk participant aktif atau admin;
- INSERT hanya untuk participant aktif, conversation aktif, sender `auth.uid()`, body valid, dan client ID belum pernah dipakai;
- UPDATE message dilarang untuk user; soft delete otomatis dikerjakan job;
- DELETE user dilarang; hard delete hanya job retention atau proses admin yang diaudit;
- participant hanya dapat mengubah read cursor dan mute miliknya sendiri;
- admin access selalu dicatat sebagai audit event.

Rate limit 30 pesan/menit dipertahankan sebagai baseline. Tambahkan limit ukuran payload, validasi whitespace, dan proteksi burst pada level database/Edge Function.

**Acceptance criteria:** semua skenario spoof sender, spoof receiver, mutation body, participant dari order lain, participant dari ride lain, dan anonymous request ditolak.

### Fase 4 — Shared frontend chat domain

**Tujuan:** Menghilangkan duplikasi logika pada `OrderChat`, halaman inbox, dan fallback legacy.

Struktur target:

```text
src/lib/chat/
  repository.ts
  types.ts
  retention.ts
  realtime.ts
  errors.ts
src/hooks/chat/
  useConversation.ts
  useChatInbox.ts
  useChatPresence.ts
  useTypingIndicator.ts
src/components/chat/
  ChatInbox.tsx
  ConversationView.tsx
  ConversationHeader.tsx
  MessageList.tsx
  MessageComposer.tsx
  ChatConnectionStatus.tsx
  MessageStatus.tsx
```

`OrderChat` dipertahankan sementara sebagai adapter route lama. Seluruh query baru harus melalui repository bersama. Inbox mengambil `chat_conversations`, participant summary, last message, dan unread aggregate; inbox tidak lagi mengambil seluruh `chat_messages` lalu grouping di browser.

Perilaku UI minimum:

- pesan optimistik dengan status `sending`;
- perubahan ke `sent` setelah database mengembalikan row;
- `failed` dengan tombol retry;
- empty state berbeda untuk belum ada pesan dan tidak ada akses;
- offline/reconnecting state yang jelas;
- conversation closed/expired state;
- placeholder “Pesan dihapus otomatis” untuk soft-deleted row;
- tombol kembali, close dialog, Escape, focus management, dan label icon;
- input max 4.000 karakter;
- Enter untuk kirim dan Shift+Enter untuk baris baru jika multiline diaktifkan.

**Acceptance criteria:** buyer, merchant, courier, dan passenger memakai komponen shared yang sama; perbedaan hanya pada konteks, label, dan permission.

### Fase 5 — Realtime reliability dan ride integration

**Tujuan:** Membuat realtime tahan terhadap jaringan buruk dan melengkapi chat ojek.

Alur subscribe:

1. Fetch history terbaru dengan keyset cursor.
2. Subscribe channel conversation.
3. Simpan status `SUBSCRIBED`, `CHANNEL_ERROR`, `TIMED_OUT`, dan `CLOSED`.
4. Setelah subscribe ulang, fetch semua pesan setelah cursor terakhir.
5. Deduplikasi berdasarkan `id` dan `client_message_id`.
6. Listen INSERT dan UPDATE untuk soft delete.
7. Cleanup channel ketika route/dialog unmount.

Ride integration harus membuat passenger–courier conversation setelah driver ditetapkan. Sebelum driver ditetapkan, jangan broadcast chat ke semua kurir. Buyer/passenger dan courier harus melihat ride chat dari tracking dan inbox. Merchant tidak boleh menjadi participant ride chat kecuali ada keputusan produk baru.

Tambahkan Presence dan Broadcast typing hanya setelah basic delivery stabil. Payload presence tidak boleh memuat GPS atau data sensitif. Typing harus debounce 300–500 ms dan berhenti otomatis maksimal tiga detik.

**Acceptance criteria:** tidak ada pesan hilang setelah offline/reconnect; duplicate event tidak menggandakan row; ride chat muncul di inbox passenger dan courier; merchant menerima hasil kosong/forbidden.

### Fase 6 — Implementasi retention 14/30 hari

**Tujuan:** Memenuhi kebijakan penghapusan yang diminta.

Schema minimal:

```sql
ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS soft_delete_at timestamptz,
  ADD COLUMN IF NOT EXISTS hard_delete_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_reason text;
```

Saat pesan dibuat, database mengisi:

```text
soft_delete_at = created_at + 14 hari
hard_delete_at = created_at + 30 hari
```

Job cleanup harus berjalan berkala dan aman diulang:

1. Ambil batch pesan dengan `soft_delete_at <= now()` dan `deleted_at IS NULL`.
2. Set `deleted_at`, `deleted_reason = 'retention_14_days'`, dan redaksi body sesuai policy.
3. Publikasikan UPDATE melalui Realtime agar UI lawan memperbarui tampilan.
4. Ambil batch pesan dengan `hard_delete_at <= now()`.
5. Hapus attachment object berdasarkan storage path yang sudah divalidasi.
6. Hapus row message dan dependent read rows.
7. Catat metrics dan error tanpa body pesan.

Cleanup lama berbasis `auto_delete_at` tiga jam setelah order selesai harus dimigrasikan atau dinonaktifkan. Tidak boleh ada dua policy retention yang bersaing.

Job harus memiliki lock/batch agar tidak memproses row yang sama secara bersamaan. Scheduler harus memiliki alert jika cleanup lag lebih dari satu periode.

**Acceptance criteria:** simulasi H+13 tidak menghapus pesan; H+14 menyembunyikan isi dan mengirim UPDATE; H+29 masih mempertahankan placeholder/audit row; H+30 menghapus row dan attachment secara permanen.

### Fase 7 — Notification, observability, dan operations

**Tujuan:** Menjadikan fitur dapat dipantau dan dioperasikan.

Notification harus memakai `conversation_id`, `message_id`, sender display name, preview terpotong, dan deep-link yang sesuai role. Trigger atau queue harus idempotent agar retry tidak membuat notifikasi ganda.

Metrik minimum:

- latency insert sampai event diterima;
- persentase channel `SUBSCRIBED`;
- jumlah timeout, closed, dan channel error;
- reconnect success rate;
- duplicate retry recovered;
- inbox/history query latency;
- unread notification delivery;
- retention cleanup success, failure, dan lag;
- active conversations per konteks.

Log tidak boleh mengandung body pesan, token, signed URL, atau lokasi pengguna.

### Fase 8 — Testing, pilot, dan rollout

**Tujuan:** Membuktikan seluruh jalur sebelum production luas.

| Kelompok test | Skenario |
|---|---|
| Security | Buyer A/B merchant sama, order berbeda, ride berbeda, spoof sender/receiver, admin access |
| Database | Constraint, unique pair, RLS SELECT/INSERT/UPDATE/DELETE, RPC race condition |
| Realtime | Dua tab, background tab, network switch, timeout, reconnect, event duplicate |
| Reliability | Timeout setelah commit, retry client ID, reload setelah event, pagination |
| Retention | H+13, H+14, H+29, H+30, cleanup retry, scheduler failure, attachment cleanup |
| UI | Mobile, keyboard, screen reader, focus trap, empty/loading/error/offline/closed |
| Performance | Inbox besar, history besar, concurrent send, rate limit, cleanup batch |
| Domain | Buyer–merchant, buyer–courier, passenger–courier, merchant–courier |

Rollout dilakukan dengan feature flag per role dan per domain. Tahap awal hanya membuka order chat untuk internal/staging. Setelah Gate 1–5 lulus, buka pilot terbatas untuk satu kelompok merchant, kurir, dan buyer. Ride chat dibuka setelah ride matrix lulus. Direct pra-order dibuka paling akhir karena memiliki domain pair dan abuse surface yang lebih luas.

## 5. Urutan migration yang aman

Migration tidak boleh menghapus legacy columns pada awal proyek. Urutan yang disarankan:

1. `chat_direct_pair_foundation.sql` — tambah `buyer_user_id`, constraint, dan unique pair index.
2. `chat_direct_rpc_hardening.sql` — ganti RPC dan validasi dua participant.
3. `chat_rls_mutation_hardening.sql` — cabut legacy update dan tegakkan immutable message.
4. `chat_retention_columns.sql` — tambah expiry/deletion metadata.
5. `chat_retention_jobs.sql` — soft/hard delete functions, lock, batch, metrics.
6. `chat_backfill_validation.sql` — audit orphan, backfill, reconciliation report.
7. `chat_canonical_write_cutover.sql` — semua client baru menulis canonical.
8. `chat_realtime_private_channels.sql` — channel auth dan policy participant.
9. `chat_legacy_cleanup.sql` — hapus fallback setelah periode observasi dan rollback window.

Setiap migration harus idempotent, memiliki rollback strategy yang terdokumentasi, dan diuji pada staging clone sebelum production.

## 6. Pembagian pekerjaan teknis

| Area | Tanggung jawab |
|---|---|
| Product | Retention policy, chat availability, terminology, closed conversation behavior |
| Backend/database | Schema, RPC, RLS, trigger, retention jobs, migration, backfill |
| Frontend | Shared repository/hooks, inbox, conversation UI, reconnect state, accessibility |
| Realtime/operations | Channel authorization, scheduler, alert, metrics, incident playbook |
| QA/security | RLS matrix, cross-tenant isolation, E2E, load/reconnect, retention simulation |
| Legal/privacy | Soft/hard deletion exceptions, dispute retention, user-facing disclosure |

## 7. Definition of done production

Fitur hanya dianggap selesai jika seluruh kondisi berikut terpenuhi:

- Tidak ada cross-buyer atau cross-order data leakage pada RLS test.
- Direct conversation unik berdasarkan pasangan buyer–merchant.
- Semua empat relasi memiliki entry point dan inbox yang benar.
- Realtime reconnect melakukan catch-up dan tidak menggandakan pesan.
- Read receipt tidak lagi bergantung pada update bebas ke row message.
- Retention job terbukti menjalankan soft delete hari ke-14 dan hard delete hari ke-30.
- Attachment cleanup dan audit deletion telah diuji.
- Inbox menggunakan conversation summary dan pagination.
- Dependency lokal terpasang dan typecheck, lint, unit test, integration test, serta build lulus.
- Staging menjalankan seluruh acceptance matrix.
- Monitoring, alert, rollback, dan runbook incident tersedia.
- Product, operations, security, dan privacy memberikan sign-off.

## 8. Risiko dan mitigasi

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Direct pair salah desain | Kebocoran privasi | Perbaiki schema dan test cross-buyer sebelum UI rollout |
| Legacy dan canonical policy tumpang tindih | Authorization tidak konsisten | Matikan legacy mutation dan lakukan cutover bertahap |
| Cleanup job gagal | Pelanggaran retention dan pertumbuhan data | Batch idempotent, metrics, alert, retry, manual runbook |
| Event realtime terlewat | Pesan tidak terlihat | Catch-up query berbasis cursor setelah reconnect |
| Query inbox membesar | Latency dan biaya meningkat | Conversation summary, index, keyset pagination |
| User menganggap chat hilang tanpa penjelasan | Kebingungan/support load | Tampilkan kebijakan “dihapus otomatis” dan placeholder soft-deleted |
| Dispute membutuhkan histori | Kehilangan bukti | Legal hold/retention exception sebelum hard delete |
| Migration tidak sama antara environment | Perbedaan perilaku production | Bootstrap manifest, migration checksum, staging gate |

## 9. Prioritas eksekusi pertama

Pekerjaan pertama yang paling aman dan bernilai tinggi adalah:

1. Buat migration pair-scoped direct chat.
2. Buat test Buyer A versus Buyer B pada merchant yang sama.
3. Kunci legacy UPDATE policy.
4. Tambahkan kolom retention dan jalankan simulasi cleanup di staging.
5. Baru setelah itu refactor inbox dan reconnect behavior.

Dengan urutan tersebut, tim tidak membangun UI lebih jauh di atas model authorization yang masih berisiko.

## References

[1]: docs/arsitektur-live-chat-realtime.md "Arsitektur Live Chat Realtime SaDesa"
[2]: docs/audit-kesiapan-chat-realtime-2026-09-09.md "Audit Kesiapan Chat Realtime SaDesa"
[3]: supabase/bootstrap/18_20260907040000_live_chat_realtime.sql "Live chat realtime foundation migration"
[4]: supabase/bootstrap/33_20260909100000_direct_chat_realtime.sql "Direct chat realtime migration"
