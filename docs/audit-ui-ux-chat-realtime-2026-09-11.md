# Audit UI/UX Kurir/Ojek dan Chat Realtime

**Tanggal:** 11 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Ruang lingkup:** responsivitas halaman kurir/ojek, layout mobile/desktop, overflow dan fixed/sticky container, lifecycle chat, subscription Supabase Realtime, fallback ketika channel gagal, dan coverage test.

## Ringkasan

Observasi pengguna sesuai dengan hasil source review. Masalahnya terbagi menjadi dua kelompok:

1. **UI/UX kurir dan ojek:** beberapa halaman menggunakan pola fixed/sticky, grid, tombol berderet, dan ukuran peta yang kaku tanpa sistem breakpoint yang seragam. Pada layar 320–375 px, area tombol dan informasi rute berisiko menyempit, bertumpuk, atau mendorong konten utama di balik bar bawah.
2. **Chat:** subscription `postgres_changes` untuk `chat_messages` memang sudah dibuat dan migration menambahkan tabel ke publication `supabase_realtime`. Namun, saat channel gagal, timeout, atau koneksi terputus, komponen hanya mengubah status menjadi reconnecting tanpa strategi retry/polling yang benar-benar memulihkan subscription. Akibatnya, pesan baru tidak masuk ke state UI sampai pengguna reload atau membuka ulang chat.

## Temuan UI/UX

### UI-01 — P1: Fixed/sticky layout belum memiliki kontrak safe-area dan spacing terpadu

`CourierLayout.tsx:37-53` menggunakan `h-screen`, header sticky, dan content `overflow-y-auto`. Di sisi lain, halaman booking kurir menggunakan summary `sticky bottom-20` pada `CourierBookingPage.tsx:569`, sementara shell aplikasi juga dapat memiliki bottom navigation. Pola ini rentan membuat CTA tertutup, jarak bawah tidak konsisten, atau area scroll berhenti terlalu dekat dengan tombol fixed pada perangkat dengan home indicator.

**Perbaikan:** buat satu layout contract untuk semua halaman kurir/ojek:

- gunakan `min-h-[100dvh]` alih-alih hanya `h-screen`;
- tambahkan `padding-bottom: calc(var(--bottom-nav-height) + env(safe-area-inset-bottom) + 16px)` pada area scroll;
- gunakan satu komponen `StickyActionBar` dengan posisi dan offset yang sama;
- pastikan hanya satu container yang bertanggung jawab atas vertical scrolling.

### UI-02 — P1: Aksi pada kartu ride berpotensi overflow pada mobile

`CourierRidesPage.tsx:490-500` menempatkan harga, tombol “Lihat Rute”, dan tombol “Terima” dalam satu baris flex. Label tombol dan badge jarak juga berada pada area yang sama (`:470-500`). Pada lebar 320–375 px, kombinasi harga panjang, dua tombol, ikon, dan badge dapat menyebabkan wrapping yang tidak terkontrol atau target tap menjadi terlalu sempit.

**Perbaikan:** pada breakpoint mobile, ubah footer kartu menjadi dua baris: harga dan jarak di baris pertama, tombol `Lihat Rute` dan `Terima` full-width/dua kolom di baris kedua. Gunakan `min-w-0`, `truncate`, dan `flex-wrap` secara eksplisit.

### UI-03 — P1: Peta booking/tracking memakai tinggi kaku dan menguasai viewport kecil

`RideBookingPage.tsx:320` memakai `fixed inset-0`, sedangkan komponen peta dan panel detail menggunakan area viewport yang relatif besar. `CourierRidesPage.tsx:505-524` menggunakan peta expanded tetap `h-[150px]`. Tinggi yang kaku membuat komposisi terlihat tidak seimbang antara device pendek dan device tinggi, serta dapat mengurangi ruang untuk CTA/status perjalanan.

**Perbaikan:** gunakan tinggi responsif berbasis viewport, misalnya `min-h-[220px] h-[34dvh] max-h-[420px]` untuk peta booking; peta inline di kartu cukup `h-36 sm:h-44`. Uji pada 320×568, 375×667, 390×844, dan desktop.

### UI-04 — P1: Halaman courier belum memiliki mobile information hierarchy yang konsisten

`CourierLayout.tsx` menyembunyikan subtitle pada mobile (`:45-46`) dan menyimpan sidebar sebagai drawer. Ini menghemat ruang, tetapi dashboard/rides/history masih menampilkan banyak metrik dan kontrol tanpa prioritas visual yang sama. `CourierHistoryPage.tsx` memakai tiga kolom statistik (`grid-cols-3`) pada semua ukuran, sementara `CourierEarningsPage.tsx` memakai dua kolom statistik (`grid-cols-2`). Pada layar kecil angka dan label dapat menjadi terlalu padat.

**Perbaikan:** gunakan `grid-cols-1 xs:grid-cols-2 sm:grid-cols-3` sesuai kepadatan konten; prioritaskan status order aktif dan CTA berikutnya di atas metrik historis; tampilkan subtitle sebagai breadcrumb/status ringkas ketika dibutuhkan.

### UI-05 — P1: `body { overflow-x: hidden }` dapat menyamarkan overflow, bukan menyelesaikannya

`src/index.css:194-197` mematikan overflow horizontal global. Ini mencegah scrollbar horizontal terlihat, tetapi elemen yang terlalu lebar dapat terpotong tanpa sinyal visual. Untuk area chat, tabel, peta, dan kartu action, perilaku ini menyulitkan diagnosis responsivitas.

**Perbaikan:** pertahankan pencegahan overflow hanya pada shell yang terkontrol; gunakan `overflow-x-auto` untuk tabel/toolbar yang memang membutuhkan scroll; tambahkan visual test pada lebar minimum.

## Temuan chat realtime

### CHAT-01 — P0: Tidak ada retry/resubscribe yang efektif setelah channel gagal

`src/lib/chat/repository.ts:117-121` membuat channel `chat-conversation-${conversationId}` dan memanggil `.subscribe()`. `OrderChat.tsx:294-308` hanya memetakan status subscription ke state UI. Ketika status bukan `SUBSCRIBED`, komponen mengubah status menjadi `reconnecting`, tetapi tidak membuat channel baru, tidak melakukan exponential backoff, dan tidak melakukan polling sebagai fallback.

Cleanup pada `OrderChat.tsx:317-322` hanya menghapus channel saat unmount/perubahan konteks. Jadi jika channel menerima `CHANNEL_ERROR`, `TIMED_OUT`, atau `CLOSED`, pengguna dapat tetap berada dalam status reconnecting tanpa pesan baru masuk. Reload membuat lifecycle subscription dari awal, yang menjelaskan gejala “harus reload dulu”.

**Perbaikan wajib:** buat `useChatRealtime` atau `subscribeWithRetry` yang:

- menghentikan channel lama sebelum resubscribe;
- retry pada `CHANNEL_ERROR`, `TIMED_OUT`, dan `CLOSED` dengan backoff 1s, 2s, 5s, 10s;
- melakukan full history sync setelah berhasil reconnect, dengan dedup berdasarkan message ID;
- mengaktifkan polling ringan 10–15 detik hanya saat status bukan `SUBSCRIBED`;
- menampilkan status yang jujur: `Tersambung`, `Menghubungkan ulang`, atau `Offline`;
- membersihkan timer dan channel saat conversation berubah atau komponen unmount.

### CHAT-02 — P1: Callback status menyamarkan error sebagai “reconnecting” tanpa observability UI

`OrderChat.tsx:300-303` menganggap semua status selain `SUBSCRIBED` sebagai reconnecting. `normalizeConnectionStatus` sudah membedakan `offline`, `closed`, dan `reconnecting`, tetapi komponen tidak memanfaatkan pembedaan tersebut. Pengguna tidak tahu apakah chat sedang retry, offline, atau subscription ditolak karena konfigurasi database.

**Perbaikan:** teruskan hasil `normalizeConnectionStatus` ke UI. Pada `CHANNEL_ERROR`, tampilkan alasan singkat dan tombol `Coba sambungkan lagi`; pada `TIMED_OUT`, gunakan retry otomatis; pada `CLOSED`, buat channel baru. Catat `status`, `conversation_id`, jumlah retry, dan waktu reconnect.

### CHAT-03 — P1: Tidak ada initial gap recovery setelah subscription aktif

Alur saat ini memuat history di `OrderChat.tsx:274-287`, lalu baru membuat subscription pada `:294-308`. Jika pesan masuk di antara query history dan channel benar-benar `SUBSCRIBED`, pesan itu dapat berada pada race window. Tidak ada query “pesan sejak timestamp/message ID terakhir” setelah status `SUBSCRIBED` untuk menutup gap tersebut.

**Perbaikan:** simpan `lastSeenCreatedAt`/ID dari history, lalu setelah `SUBSCRIBED` panggil `listConversationMessagesSince` atau query dengan `(created_at, id)` cursor. Merge secara idempotent ke state.

### CHAT-04 — P1: Realtime database sudah dideklarasikan di source, tetapi status deployment perlu diverifikasi

`supabase/bootstrap/33_20260909100000_direct_chat_realtime.sql:85-92` menambahkan `public.chat_messages` ke publication `supabase_realtime` jika publication tersedia. Source client memang menggunakan `postgres_changes` pada `chat_messages`. Namun audit ini tidak memiliki akses ke database staging/production untuk memastikan:

- migration tersebut sudah diterapkan;
- `chat_messages` benar-benar tercantum pada publication;
- RLS SELECT mengizinkan kedua participant menerima event;
- channel tidak gagal karena konfigurasi Realtime/plan/environment;
- tidak ada lebih dari satu migration bundle yang tertinggal.

**Perbaikan/verification SQL di staging:**

```sql
select pubname, schemaname, tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
  and schemaname = 'public'
  and tablename = 'chat_messages';
```

Lanjutkan dengan dua akun participant yang membuka conversation sama, kirim pesan dari akun A, lalu ukur waktu sampai pesan tampil di akun B tanpa reload. Uji juga putus-sambung jaringan dan status channel `TIMED_OUT`/`CHANNEL_ERROR`.

### CHAT-05 — P2: Test realtime saat ini hanya menguji kontrak statis, bukan perilaku channel end-to-end

`src/lib/chat/realtime.test.ts` hanya menguji pemetaan status string. `src/hooks/chat/chatPresenceTyping.test.ts` membaca source dan memastikan hook tertentu digunakan. Belum ada test yang mensimulasikan:

- message INSERT masuk ke state receiver;
- channel error lalu resubscribe;
- dedup antara history, optimistic/local message, dan event realtime;
- gap recovery setelah reconnect;
- fallback polling ketika Realtime mati.

**Perbaikan:** tambahkan unit test dengan fake `RealtimeChannel` dan integration test memakai dua client Supabase staging. Acceptance criterion: pesan baru tampil tanpa reload dalam p95 < 2 detik pada koneksi normal.

## Prioritas implementasi

| Prioritas | Pekerjaan | Hasil |
|---|---|---|
| P0 | Implementasi retry/resubscribe + full sync chat | Chat pulih tanpa reload setelah channel putus |
| P0 | Verifikasi publication dan RLS pada staging | Memastikan event benar-benar dikirim dan diterima |
| P1 | Tambahkan polling fallback saat offline/reconnecting | Pesan tetap muncul walau Realtime sementara gagal |
| P1 | Satukan `StickyActionBar`, safe-area, dan scroll contract | CTA tidak tertutup/bertumpuk |
| P1 | Rework card action courier untuk mobile | Tidak ada overflow pada 320–375 px |
| P1 | Uji peta dengan `dvh` dan breakpoint | Layout stabil pada device pendek/tinggi |
| P2 | Tambahkan visual regression dan realtime integration test | Regresi responsivitas dan chat tertangkap CI |

## Acceptance criteria

1. Pada 320×568 dan 375×667, tidak ada horizontal clipping, tombol keluar viewport, atau CTA tertutup bottom navigation.
2. Pada halaman rides, kartu order dapat dibaca tanpa zoom; tombol `Terima` memiliki target tap minimal 44×44 px.
3. Saat channel chat terputus, UI berubah ke `Menghubungkan ulang`, melakukan retry otomatis, dan kembali ke `Tersambung` tanpa reload.
4. Pesan yang dikirim participant A tampil pada participant B tanpa reload; p95 latency target koneksi normal < 2 detik.
5. Pesan yang masuk selama gap reconnect tampil setelah full sync dan tidak muncul duplikat.
6. Jika Realtime tidak tersedia, polling fallback memberi pesan maksimal terlambat satu interval polling dan menampilkan status offline secara jujur.

## Hasil verifikasi lokal

| Pemeriksaan | Hasil |
|---|---:|
| Test realtime status | PASS — 5 test |
| Test presence/typing contract | PASS — 3 test |
| Test security migration chat | PASS — 3 test |
| Total test chat terarah | PASS — 11 test |
| Production build | PASS |
| Dynamic two-user Realtime test | Belum dilakukan; memerlukan staging fixture |
| Visual browser test pada device matrix | Belum dilakukan dalam audit ini |

## Kesimpulan

Keluhan tentang chat terlambat sangat mungkin berasal dari **recovery lifecycle yang tidak lengkap**, bukan semata-mata dari tidak adanya kode Realtime. Source sudah memasang subscription dan migration sudah mencoba memasukkan `chat_messages` ke publication, tetapi client tidak benar-benar melakukan resubscribe/gap recovery ketika channel gagal. Untuk UI, perbaikan terbaik bukan menambah CSS ad hoc, melainkan menyatukan kontrak shell, safe-area, sticky action, breakpoint kartu, dan pengujian pada lebar device nyata.

> Status akhir: **UI/UX kurir/ojek perlu hardening responsif; chat perlu perbaikan retry, gap recovery, fallback, dan verifikasi deployment sebelum dapat disebut realtime production-ready.**
