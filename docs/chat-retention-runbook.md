# Chat Retention Runbook

## Kebijakan

Pesan chat normal selama 13 hari pertama. Pada hari ke-14, pesan di-soft-delete dan tidak lagi ditampilkan oleh client. Pada hari ke-30, row pesan dihapus permanen. Attachment path yang tersimpan pada `attachment_path` dihapus lebih dahulu melalui worker.

## Worker

Edge Function `process-chat-retention` hanya menerima `POST`. Panggilan harus menyertakan `x-worker-secret` yang sama dengan secret `WORKER_CRON_SECRET`, atau bearer token service role. Worker menjalankan batch soft delete, mengambil kandidat hard delete, menghapus object dari bucket `chat-images`, lalu memanggil hard-delete RPC.

Worker sengaja menggunakan batch maksimum 5.000 row. Scheduler dapat memanggilnya setiap jam. Pemanggilan bersifat idempotent; row yang sudah soft-deleted tidak diproses ulang dan hard-delete hanya menghapus row yang sudah melewati `hard_delete_at`.

## Scheduler production

Jadwalkan `POST https://<project-ref>.supabase.co/functions/v1/process-chat-retention` setiap jam dengan header berikut:

```text
x-worker-secret: <WORKER_CRON_SECRET>
content-type: application/json
```

Secret tidak boleh diletakkan pada frontend atau commit. Simpan pada secret manager/scheduler. Jika platform Supabase project memakai `pg_cron` dan `pg_net`, scheduler dapat memanggil Edge Function dari database, tetapi URL dan secret tetap harus disimpan melalui secret yang sesuai.

## Verifikasi manual

Gunakan service-role-only RPC untuk memverifikasi kandidat, bukan query client biasa:

```sql
select * from public.list_hard_expired_chat_messages(100);
select public.soft_delete_expired_chat_messages(100);
```

Jangan menjalankan `hard_delete_chat_messages` manual kecuali ada incident procedure dan daftar ID telah direview. Hard delete bersifat permanen.

## Monitoring

Catat hasil worker tanpa body pesan:

- `soft_deleted`;
- `hard_delete_candidates`;
- `hard_deleted`;
- `attachment_objects_removed`;
- HTTP 401 dari scheduler;
- HTTP 500 dari worker;
- retention lag, yaitu umur pesan tertua yang masih melewati `soft_delete_at` atau `hard_delete_at`.

## Rollback

Migration retention tidak boleh di-rollback dengan mengembalikan pesan yang sudah di-hard-delete. Jika worker bermasalah, hentikan scheduler dan perbaiki worker. Soft-deleted row masih tersedia sampai hari ke-30, sehingga dapat ditampilkan kembali hanya melalui migration/incident procedure yang disetujui. Setelah hard delete, pemulihan hanya mungkin dari backup yang sah.
