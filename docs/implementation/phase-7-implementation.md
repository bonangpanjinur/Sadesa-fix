# Evidence implementasi Fase 7 — Notification, observability, dan operations

Migration `38_20260909150000_chat_notification_observability.sql` melengkapi kontrak operasional chat tanpa menghapus kolom atau RPC legacy. Notifikasi chat sekarang menyimpan `conversation_id`, `message_id`, `sender_display_name`, preview yang telah dipotong, deep-link berdasarkan role participant, serta `idempotency_key` unik per penerima dan pesan. Trigger memakai RPC `send_chat_notification`, sehingga retry trigger tidak membuat baris notifikasi ganda.

Metrik chat disimpan pada `chat_observability_events` melalui RPC `record_chat_observability`. Daftar metric dibatasi oleh `CHECK` dan RPC agar dashboard tidak menerima event arbitrer. Client merekam delivery latency, status channel (`SUBSCRIBED`, timeout, closed, error), reconnect success, duplicate retry recovery, inbox/history latency, unread/active conversation hooks, dan retention metric hooks. Instrumentasi tidak mengirim body pesan, token, signed URL, nomor telepon, email, atau lokasi.

## Operasional

Worker retention yang sudah ada tetap menjadi sumber metrik cleanup melalui `chat_retention_runs`; metric table menyediakan kanal seragam untuk dashboard dan alert. Index pada `(metric_name, occurred_at)` memungkinkan query time-window tanpa membaca tabel chat. Akses baca metric dibatasi ke `service_role`; aplikasi hanya dapat menulis melalui RPC.

## Rollback strategy

Jika deployment perlu di-rollback, hentikan pemanggilan dashboard terhadap metric baru dan disable trigger notification baru dengan `DROP TRIGGER ... chat_messages_notify_recipient`. Kolom tambahan dan data notifikasi lama tetap kompatibel sehingga tidak perlu destructive rollback. Migration tidak menghapus `send_notification` legacy.

## Gate yang masih memerlukan staging

Migration dan kontrak client telah ditambahkan di repository, tetapi persentase channel, delivery push provider, alert threshold, scheduler lag, dan dashboard produksi tetap harus divalidasi pada Supabase staging sebelum Gate 7/production sign-off.
