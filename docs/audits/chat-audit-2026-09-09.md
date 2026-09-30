# Audit dan Perbaikan Chat SaDesa

**Tanggal:** 9 September 2026  
**Fokus:** Kegagalan pengiriman pesan pada RPC `send_chat_message` dan stabilitas alur chat.

## Kesimpulan

Akar kegagalan pengiriman pesan adalah regresi pada migrasi `41_20260909152000_role_aware_chat_notifications.sql`. Migrasi tersebut mengembalikan pola `FULL JOIN` ke trigger `notify_chat_message`, padahal migrasi 32 sebelumnya sudah menghapus pola yang sama karena PostgreSQL dapat menolaknya dengan SQLSTATE `0A000`. Trigger dijalankan setelah INSERT pesan. Ketika trigger gagal, seluruh transaksi INSERT dibatalkan dan PostgREST menampilkan kegagalan RPC sebagai HTTP 400.

## Temuan Utama

| Area | Temuan | Dampak | Status |
|---|---|---|---|
| Pengiriman pesan | Trigger notifikasi memakai `FULL JOIN` dengan kondisi disjungtif | INSERT pesan rollback; frontend menerima HTTP 400 | Diperbaiki |
| Notifikasi | Trigger role-aware memakai `send_notification` lama | Idempotensi dan metadata chat baru tidak digunakan secara konsisten | Diperbaiki dengan `send_chat_notification` |
| Deep link | Helper notifikasi memakai `conversation`, sedangkan halaman chat membaca `conversationId` | Klik notifikasi tidak selalu membuka percakapan yang benar | Diperbaiki |
| Error frontend | Error terstruktur Supabase dapat kehilangan `code`, `details`, dan `hint` | UI hanya menampilkan pesan umum | Diperbaiki |
| Validasi frontend | Payload kosong, terlalu panjang, atau sender=receiver tetap dapat mencapai RPC | Error terlambat dan kurang jelas | Diperbaiki |
| PWA device | Error `54000` adalah batas perangkat aktif, bukan penyebab langsung chat gagal | Registrasi PWA/heartbeat dapat gagal secara terpisah | Tidak diubah; perlu operasionalisasi terpisah |

## Perubahan yang Diterapkan

### Database

Trigger `notify_chat_message` sekarang mengambil nama pengirim melalui tiga subquery independen untuk profil, merchant, dan kurir. Pola outer join yang bermasalah telah dihilangkan.

Trigger juga menggunakan `send_chat_notification`, sehingga notifikasi memakai `conversation_id`, `message_id`, deep link role-aware, dan idempotency key.

Deep link telah diseragamkan ke format `conversationId`, sesuai dengan parameter yang dibaca oleh halaman buyer, merchant, dan courier.

### Frontend

`sendConversationMessage` sekarang memangkas whitespace, menolak pesan kosong atau lebih dari 4.000 karakter, dan menolak sender serta receiver yang sama sebelum memanggil RPC.

Error Supabase sekarang membaca `code`, `message`, `details`, dan `hint`. Error juga dikelompokkan menjadi akses ditolak, percakapan tertutup, koneksi/server, dan validasi.

Kegagalan RPC dicatat dengan konteks aman berupa kode error dan ID percakapan. Isi pesan tidak dicatat.

### Regression Test

Acceptance test chat sekarang memastikan migrasi role-aware tidak mengandung `FULL JOIN` dan menggunakan `send_chat_notification`.

## Verifikasi

| Pemeriksaan | Hasil |
|---|---|
| Acceptance test chat | Lulus: 5/5 |
| Seluruh unit test | Lulus: 55 file, 201 test lulus, 20 dilewati sesuai konfigurasi |
| Lint | Lulus tanpa error; terdapat 6 warning Fast Refresh yang sudah ada di area lain |
| Production build | Lulus; Vite dan service worker berhasil dibuat |
| Validasi migrasi | Lulus: 42 file SQL tervalidasi |
| Validasi bootstrap | Lulus: 222 migrasi dalam 37 bundle |
| `git diff --check` | Lulus |

## Langkah Deployment

Perubahan SQL harus diterapkan ke database Supabase melalui mekanisme deployment proyek. Setelah deployment, lakukan smoke test berikut:

1. Login sebagai buyer dan buka percakapan aktif.
2. Kirim pesan teks biasa.
3. Pastikan request `send_chat_message` mengembalikan HTTP 200.
4. Pastikan pesan muncul di pengirim dan penerima.
5. Pastikan notifikasi penerima membuka route dengan parameter `conversationId`.
6. Uji pengiriman pesan 4.001 karakter dan pastikan ditolak di frontend tanpa request RPC.
7. Periksa log database bila masih terjadi error; error `FULL JOIN` pada trigger seharusnya sudah tidak muncul.

Error `54000` pada `register_pwa_device` tetap perlu ditangani sebagai pekerjaan operasional terpisah dengan mencabut perangkat lama atau meninjau batas entitlement POS. Error tersebut tidak memblokir akar masalah pengiriman chat yang diaudit di sini.

## File yang Diubah

- `supabase/bootstrap/41_20260909152000_role_aware_chat_notifications.sql`
- `supabase/bootstrap/38_20260909150000_chat_notification_observability.sql`
- `src/lib/chat/repository.ts`
- `src/lib/chat/errors.ts`
- `src/lib/chat/phase8Acceptance.test.ts`

## Catatan Deployment

Perubahan ini telah diterapkan pada working tree repository lokal `/home/ubuntu/Sadesa-fix`. Belum ada tindakan publish atau deployment eksternal yang dijalankan.

## References

[1]: https://www.postgresql.org/docs/current/errcodes-appendix.html "PostgreSQL error codes"
[2]: https://supabase.com/docs/guides/database/functions "Supabase Database Functions"
