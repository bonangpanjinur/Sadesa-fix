# Audit Chat Realtime SaDesa

**Tanggal audit:** 10 September 2026  
**Cakupan:** percakapan kurir–pembeli/penyewa jasa, pedagang–pembeli, realtime delivery, inbox, notifikasi, lifecycle percakapan, dan otorisasi database.  
**Metode:** inspeksi statis source code frontend, repository chat, halaman entry point, fungsi RPC, RLS, trigger database, route, serta dokumentasi kontrak chat. Audit ini belum mencakup pengujian terhadap instance Supabase produksi.

## Kesimpulan eksekutif

Fondasi keamanan chat sudah cukup baik. Penulisan pesan telah diarahkan melalui RPC `SECURITY DEFINER`, keanggotaan percakapan divalidasi di database, pesan memiliki idempotensi berbasis `client_message_id`, dan RLS membatasi pembacaan berdasarkan peserta percakapan.

Namun, **alur chat ride antara kurir/driver dan penyewa jasa belum memenuhi kontrak realtime**. UI mengirim percakapan ride sebagai `passenger_courier`, tetapi handler realtime pada `OrderChat` menyaring pesan berdasarkan prop `chatType` yang diisi `buyer_courier`. Akibatnya, histori awal dapat tampil, tetapi pesan baru dari lawan bicara tidak masuk ke layar secara realtime. Bug ini berdampak langsung pada komunikasi saat perjalanan dan dikategorikan **P0**.

Alur pedagang–pembeli dan kurir delivery–pembeli secara umum memakai conversation canonical dan dapat berlangganan ke channel pesan. Akan tetapi, implementasinya masih memiliki beberapa risiko **P1**: inbox memuat seluruh histori tanpa batas, sebagian daftar chat menggunakan query legacy langsung ke `chat_messages`, subscriber daftar chat tidak memakai filter percakapan, dan deep link notifikasi ride mengarah ke route yang tidak sesuai dengan route aplikasi.

## Matriks cakupan alur

| Alur | Konteks database | Tipe percakapan | Entry point utama | Status audit |
|---|---|---|---|---|
| Pembeli–pedagang pada pesanan | `order` | `buyer_merchant` | `BuyerChatPage`, `OrderDetailSheet`, `MerchantChatPage` | Berfungsi secara konseptual, tetapi query inbox dan histori belum efisien. |
| Pembeli–kurir delivery | `order` | `buyer_courier` | `BuyerChatPage`, `CourierChatPage` | Berfungsi secara konseptual, tetapi masih bergantung pada query legacy dan subscriber broad. |
| Pedagang–kurir delivery | `order` | `merchant_courier` | `MerchantChatPage`, `CourierChatPage` | Berfungsi secara konseptual, dengan risiko refresh inbox dan query besar. |
| Penyewa jasa–driver/kurir ojek | `ride` | `passenger_courier` | `RideTrackingPage`, `CourierRidesPage` | **Realtime rusak karena mismatch tipe percakapan dengan filter handler.** |

## Temuan prioritas

| ID | Prioritas | Area | Temuan | Dampak |
|---|---|---|---|---|
| CHAT- P0-01 | P0 | Ride realtime | `OrderChat` memfilter pesan masuk menggunakan `chatType`, sedangkan database mengisi `chat_type = passenger_courier` untuk konteks ride. Entry point ride mengirim `chatType="buyer_courier"`. | Pesan lawan bicara tidak muncul realtime pada chat penyewa jasa–driver. Pengguna harus menutup/membuka ulang atau memuat histori ulang. |
| CHAT-P1-02 | P1 | Ride notification | Deep link untuk role `passenger` dibentuk sebagai `/ride/tracking?conversationId=...`, sedangkan route aplikasi yang terdaftar adalah `/ride/:id`. | Klik notifikasi chat ride dapat jatuh ke `NotFound` atau tidak dapat membuka ride yang benar karena ID ride tidak disertakan sebagai path parameter. |
| CHAT-P1-03 | P1 | Histori | `listConversationMessages` mengambil maksimum 50 pesan pertama secara ascending. Tidak ada flow UI yang memuat halaman pesan lama. | Percakapan lebih panjang dari 50 pesan kehilangan akses ke pesan lama dari UI. Pagination helper tersedia, tetapi belum terhubung ke kontrol “muat pesan sebelumnya”. |
| CHAT-P1-04 | P1 | Inbox scalability | `BuyerChatPage`, `CourierChatPage`, dan `MerchantChatPage` mengambil seluruh pesan terkait lalu mengurutkan di client. Tidak ada limit, cursor, atau agregasi last-message per conversation pada query halaman. | Beban query dan render tumbuh linear terhadap seluruh histori. Waktu buka inbox dan penggunaan memori memburuk seiring volume chat. |
| CHAT-P1-05 | P1 | Realtime list | Halaman buyer dan courier membuat subscriber `postgres_changes` pada seluruh `chat_messages` tanpa filter conversation atau recipient, kemudian memanggil `fetchThreads()` penuh pada setiap insert. | Satu pesan yang terlihat oleh user dapat memicu query inbox penuh. Pada akun dengan banyak conversation atau trafik tinggi, ini meningkatkan beban database dan dapat menyebabkan hasil balapan antar-fetch. |
| CHAT-P1-06 | P1 | Ride inbox | `BuyerChatPage` hanya membaca membership dengan role `buyer` dan tipe `buyer_merchant`/`buyer_courier`. Conversation ride menggunakan role `passenger` dan tipe `passenger_courier`. | Chat ride tidak muncul dalam inbox chat umum pembeli. Chat hanya tersedia dari halaman tracking selama route tersebut masih terbuka. |
| CHAT-P2-07 | P2 | Error state | `CourierChatPage` dan `MerchantChatPage` menangkap error melalui `console.error` lalu menampilkan empty state atau daftar kosong. | Kegagalan RLS, jaringan, atau query dapat terlihat sebagai “Belum ada percakapan”, sehingga diagnosis pengguna keliru. |
| CHAT-P2-08 | P2 | Consistency | Ada dua stack chat: `OrderChat`/repository lama dan `ConversationView`/`useConversation` yang lebih canonical. Beberapa halaman masih melakukan query langsung ke `chat_messages`. | Perilaku unread, retry, reconnect, filtering tipe, dan pagination dapat berbeda antar-entry point. Perubahan kontrak database berisiko hanya memperbaiki satu stack. |

## Analisis detail

### CHAT-P0-01 — Realtime ride menyaring tipe pesan yang salah

Database menetapkan tipe conversation ride sebagai `passenger_courier`. Aturan ini terlihat pada `chat_domain_participants` dan validasi `get_or_create_chat_conversation`, yang hanya menerima `passenger_courier` untuk konteks `ride`.

`RideTrackingPage` dan `CourierRidesPage` tetap mengoper prop `chatType="buyer_courier"` ke `OrderChat`. Di sisi lain, `OrderChat` menjalankan filter berikut pada setiap payload realtime:

```ts
if (!active || (chatType && incoming.chat_type !== chatType)) return;
```

Saat pesan dikirim, `OrderChat` memang mengubah tipe request menjadi `passenger_courier` jika `contextType === 'ride'`. Karena itu pesan berhasil masuk database, tetapi pesan realtime yang diterima memiliki `incoming.chat_type === 'passenger_courier'` dan dibuang oleh filter `buyer_courier`.

**Perbaikan yang disarankan:** turunkan expected conversation type dari `contextType`, bukan dari prop presentasional. Untuk `contextType === 'ride'`, gunakan `passenger_courier` pada filter realtime, label, dan metadata. Prop `chatType` sebaiknya tidak dipakai untuk menentukan tipe canonical database pada ride.

**Acceptance criteria:** ketika penyewa jasa dan driver membuka chat ride yang sama, pesan baru muncul pada kedua layar tanpa reload; histori dan realtime memakai tipe `passenger_courier`; chat order tetap memakai tiga tipe order yang sudah ada.

### CHAT-P1-02 — Deep link notifikasi ride tidak cocok dengan route

Fungsi `chat_notification_deep_link` menghasilkan `/ride/tracking?conversationId=<id>` untuk participant dengan role `passenger`. Route aplikasi mendaftarkan halaman tracking sebagai `/ride/:id`, bukan `/ride/tracking`.

Selain mismatch path, conversation ID tidak dapat menggantikan parameter `id` karena `RideTrackingPage` mengambil `id` dari `useParams` dan memuat `ride_requests` berdasarkan nilai tersebut. Fungsi deep link juga tidak mengambil `ride_request_id` dari conversation untuk membentuk URL tracking.

**Perbaikan yang disarankan:** bentuk deep link dari `chat_conversations.ride_request_id`, misalnya `/ride/<ride_request_id>?conversationId=<conversation_id>`. Tambahkan test database atau test kontrak yang memastikan seluruh role menghasilkan route yang benar-benar terdaftar di frontend.

### CHAT-P1-03 — Pagination histori belum selesai di UI

Repository memiliki `listConversationPage`, tetapi `OrderChat` memakai `listConversationMessages` satu kali dengan default limit 50. Hook `useConversation` juga memakai histori awal dan catch-up untuk pesan yang lebih baru, bukan untuk mengambil halaman yang lebih lama.

**Perbaikan yang disarankan:** mulai histori dari pesan terbaru, simpan cursor pesan tertua, dan tambahkan tombol atau infinite scroll “Muat pesan sebelumnya”. Cursor harus memakai pasangan `(created_at, id)` untuk urutan deterministik. Jangan mengubah seluruh histori menjadi satu query tanpa batas.

### CHAT-P1-04 dan CHAT-P1-05 — Inbox terlalu mahal dan subscriber terlalu luas

Buyer, courier, dan merchant melakukan query seluruh pesan yang dapat mereka lihat, lalu membentuk thread dengan `Map` di browser. Buyer dan courier juga membuat channel realtime tanpa filter `conversation_id` atau `receiver_id`; setiap insert yang lolos Realtime memanggil `fetchThreads()` penuh.

RLS tetap menjadi batas keamanan, sehingga temuan ini bukan bypass otorisasi. Masalahnya adalah efisiensi dan stabilitas. Dengan banyak pesan, satu event dapat menyebabkan query besar berulang, dan beberapa fetch yang selesai tidak berurutan dapat menimpa state yang lebih baru.

**Perbaikan yang disarankan:** gunakan query inbox berbasis `chat_conversations` yang sudah menyimpan `last_message_at`, `last_message_body`, dan `last_message_id`. Ambil membership aktif, last message, dan unread count melalui RPC atau view terproteksi. Gunakan subscription terfilter pada conversation atau perubahan `chat_conversations`, debounce refresh, dan tambahkan request sequence untuk menolak hasil fetch usang.

### CHAT-P1-06 — Chat ride tidak masuk inbox umum pembeli

Conversation ride dibuat dengan participant role `passenger`. `BuyerChatPage` hanya mencari participant role `buyer`, kemudian hanya menerima tipe `buyer_merchant` dan `buyer_courier`. Dengan demikian, chat ride memang dapat dibuka dari `RideTrackingPage`, tetapi tidak terdaftar di `BuyerChatPage`.

**Perbaikan yang disarankan:** pisahkan “Chat Pesanan” dan “Chat Perjalanan” pada inbox pembeli, atau ubah query inbox agar mendukung role `passenger` serta tipe `passenger_courier`. Jangan mengganti tipe ride menjadi `buyer_courier` karena kontrak database sudah membedakan domain order dan ride.

## Hal yang sudah baik

Otorisasi database sudah memiliki beberapa kontrol penting. RLS pada conversation, participant, message, dan read receipt membatasi pembacaan pada participant aktif atau admin. RPC `send_chat_message` memeriksa bahwa sender dan receiver adalah participant aktif dari conversation yang sama. RPC tersebut juga memeriksa status conversation aktif, memangkas isi pesan, membatasi panjang 4.000 karakter, dan menggunakan `client_message_id` untuk retry idempotent.

Trigger validasi participant memastikan `sender_id` sama dengan `auth.uid()` dan receiver merupakan participant lain. Trigger immutability mencegah perubahan identitas, isi, konteks, dan timestamp pesan. Notifikasi dibuat dari participant conversation, bukan dari ID penerima yang bebas dikirim client. Kontrol ini perlu dipertahankan saat memperbaiki alur frontend.

## Rekomendasi urutan perbaikan

| Tahap | Pekerjaan | Hasil |
|---|---|---|
| 1 | Perbaiki expected type pada `OrderChat` untuk konteks ride. | Realtime passenger–courier tampil dua arah. |
| 2 | Perbaiki deep link passenger dengan `ride_request_id` dan route `/ride/:id`. | Klik notifikasi membuka perjalanan yang tepat. |
| 3 | Tambahkan test kontrak untuk order dan ride. | Mismatch `buyer_courier` versus `passenger_courier` tertangkap otomatis. |
| 4 | Implementasikan inbox query berbasis conversation summary dan unread RPC. | Tidak ada full-scan histori pada setiap buka inbox. |
| 5 | Tambahkan filter/debounce subscriber dan proteksi terhadap hasil fetch usang. | Beban realtime stabil pada trafik tinggi. |
| 6 | Hubungkan pagination histori ke UI. | Percakapan panjang tetap dapat dibaca lengkap. |
| 7 | Satukan stack chat menjadi satu repository/hook canonical. | Reconnect, retry, unread, dan error state konsisten. |

## Rencana pengujian minimum

| Skenario | Ekspektasi |
|---|---|
| Buyer dan merchant mengirim pesan pada order aktif | Kedua pesan muncul realtime dan hanya pada participant order tersebut. |
| Courier dan buyer mengirim pesan pada order delivery aktif | Kedua pesan muncul realtime dan unread count berubah tepat. |
| Passenger dan driver mengirim pesan pada ride aktif | Payload memakai `passenger_courier`; pesan baru muncul tanpa reload. |
| Klik notifikasi chat passenger | Route menjadi `/ride/<ride_request_id>?conversationId=<id>` dan tracking memuat ride yang benar. |
| User yang tidak terkait membuka conversation ID lain | RPC dan RLS menolak akses. |
| Retry dengan client message ID sama | Tidak membuat pesan duplikat. |
| Retry dengan client message ID sama tetapi body/receiver berbeda | Ditolak. |
| Conversation lebih dari 50 pesan | UI dapat memuat halaman pesan lama. |
| Banyak insert dalam waktu singkat | Inbox tidak melakukan full fetch berulang tanpa debounce dan tidak menimpa state baru dengan hasil usang. |
| Query/RLS gagal | UI menampilkan error dan tombol retry, bukan empty state. |

## Batasan audit

Audit ini adalah audit source code dan kontrak SQL. Tidak ada sesi uji dengan akun buyer, merchant, courier, dan passenger nyata pada environment staging dalam pekerjaan ini. Status deployment migration, status publication Realtime, performa query aktual, dan konfigurasi RLS pada database produksi tetap perlu diverifikasi melalui smoke test staging.

## Referensi

[1]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/components/chat/OrderChat.tsx "OrderChat frontend implementation"

[2]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/pages/ride/RideTrackingPage.tsx "Ride tracking chat entry point"

[3]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/pages/courier/CourierRidesPage.tsx "Courier ride chat entry point"

[4]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/pages/buyer/BuyerChatPage.tsx "Buyer chat inbox implementation"

[5]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/lib/chat/repository.ts "Canonical chat repository"

[6]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/supabase/bootstrap/18_20260907040000_live_chat_realtime.sql "Chat domain participant and realtime schema"

[7]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/supabase/bootstrap/36_20260909130000_chat_rls_rpc_abuse_control.sql "Chat RLS and canonical RPC security"

[8]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/supabase/bootstrap/42_20260909170000_chat_notification_final_repair.sql "Chat notification deep-link implementation"
