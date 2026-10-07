# Evidence implementasi Fase 7 — Notification, observability, dan operations

Migration `38_20260909150000_chat_notification_observability.sql` melengkapi kontrak operasional chat tanpa menghapus kolom atau RPC legacy. Notifikasi chat sekarang menyimpan `conversation_id`, `message_id`, `sender_display_name`, preview yang telah dipotong, deep-link berdasarkan role participant, serta `idempotency_key` unik per penerima dan pesan. Trigger memakai RPC `send_chat_notification`, sehingga retry trigger tidak membuat baris notifikasi ganda.

Metrik chat disimpan pada `chat_observability_events` melalui RPC `record_chat_observability`. Daftar metric dibatasi oleh `CHECK` dan RPC agar dashboard tidak menerima event arbitrer. Client merekam delivery latency, status channel (`SUBSCRIBED`, timeout, closed, error), reconnect success, duplicate retry recovery, inbox/history latency, unread/active conversation hooks, dan retention metric hooks. Instrumentasi tidak mengirim body pesan, token, signed URL, nomor telepon, email, atau lokasi.

## Operasional

Worker retention yang sudah ada tetap menjadi sumber metrik cleanup melalui `chat_retention_runs`; metric table menyediakan kanal seragam untuk dashboard dan alert. Index pada `(metric_name, occurred_at)` memungkinkan query time-window tanpa membaca tabel chat. Akses baca metric dibatasi ke `service_role`; aplikasi hanya dapat menulis melalui RPC.

## Rollback strategy

Jika deployment perlu di-rollback, hentikan pemanggilan dashboard terhadap metric baru dan disable trigger notification baru dengan `DROP TRIGGER ... chat_messages_notify_recipient`. Kolom tambahan dan data notifikasi lama tetap kompatibel sehingga tidak perlu destructive rollback. Migration tidak menghapus `send_notification` legacy.

## Gate yang masih memerlukan staging

Migration dan kontrak client telah ditambahkan di repository, tetapi persentase channel, delivery push provider, alert threshold, scheduler lag, dan dashboard produksi tetap harus divalidasi pada Supabase staging sebelum Gate 7/production sign-off.

## Implementasi tahap 7 — Pilot terbatas dan rollout bertahap

### Fitur yang dikerjakan

1. **Pilot readiness dan gate fail-closed**
   - Profil usaha lengkap.
   - Listing pertama terbit.
   - Order pertama selesai.
   - Fulfillment pertama selesai.
   - Setup POS dan transaksi POS pertama untuk track POS.
   - Kontrak existing `evaluatePilotReadiness` tetap menjadi sumber kebenaran milestone merchant.

2. **Keputusan operasional pilot**
   `evaluatePilotDecision` mengembalikan salah satu keputusan:
   - **GO_LIMITED** — semua gate dan threshold lulus; hanya rollout terbatas yang boleh dibuka.
   - **EXTEND_PILOT** — metrik belum stabil, masa observasi diperpanjang.
   - **HOLD** — evidence staging, rollback, security, data, finance, atau support belum lengkap.
   - **STOP_ROLLBACK** — ada insiden kritis, transaksi duplikat, atau selisih rekonsiliasi.

   `GO_LIMITED` tidak otomatis mengubah konfigurasi production. Operator tetap harus mengaktifkan feature flag melalui prosedur yang disetujui.

3. **Threshold baseline**
   - Maksimal 20 merchant pada cohort pilot.
   - Sync success rate minimal 98%.
   - Conflict rate maksimal 5%.
   - Transaksi duplikat atau selisih rekonsiliasi yang belum dijelaskan langsung memicu STOP/ROLLBACK.
   - Pelanggaran SLA support memicu EXTEND_PILOT.

4. **Feature allowlist per wave**
   Feature pilot hanya boleh aktif jika tercantum pada allowlist wave:
   - `ride`
   - `courier_booking`
   - `chat_retry`
   - `settlement_worker`
   - `guest_checkout`

   `isPilotFeatureAllowed` bersifat fail-closed: keputusan selain `GO_LIMITED` atau feature yang tidak ada di allowlist selalu ditolak.

### Prosedur wave

1. Luluskan Gate A staging/security/data/rollback.
2. Masukkan merchant dengan milestone lengkap ke cohort kecil.
3. Aktifkan hanya feature yang ada di allowlist wave.
4. Pantau activation, first order, fulfillment, sync success, conflict, reconciliation, SLA support, dan incident.
5. Review harian selama observasi tujuh hari.
6. Pilih GO_LIMITED, EXTEND_PILOT, HOLD, atau STOP_ROLLBACK.
7. Jangan memperluas cohort bila ada mismatch order/payment/refund/COD, tenant leakage, duplicate transaction, atau rollback yang belum terbukti.

### Batasan

Kontrak dan test ini tidak mengklaim pilot staging/production telah dijalankan. Dynamic RLS, provider sandbox, backup/restore, cron, device/PWA/printer, dan rekonsiliasi nyata tetap membutuhkan environment staging terisolasi serta persetujuan owner Product, Engineering, Operations, Finance, dan Security.
