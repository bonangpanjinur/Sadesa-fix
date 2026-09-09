# Runbook Fase 8 — Chat pilot dan rollback

## Persiapan staging

Terapkan migration secara berurutan pada staging clone, cocokkan checksum bootstrap manifest, dan ambil backup point sebelum test. Buat akun uji untuk buyer A/B, merchant, courier, dan passenger. Pastikan worker retention, push provider, Realtime publication, dashboard metric, serta alert dapat dijalankan tanpa memakai data pengguna nyata.

## Urutan acceptance test

Jalankan unit/contract test dan build terlebih dahulu. Selanjutnya jalankan security matrix: buyer A dan B harus memiliki direct conversation berbeda pada merchant yang sama; masing-masing hanya dapat membaca conversation dan event miliknya. Uji cross-order dan cross-ride, spoof sender/receiver, anonymous request, admin access audit, serta UPDATE/DELETE message.

Uji realtime pada dua tab dengan network switch dan background tab. Kirim pesan ketika koneksi timeout, retry dengan `client_message_id` yang sama, reload setelah commit, dan pastikan satu row tampil tanpa duplicate. Uji cursor pagination dan UPDATE soft-delete. Setelah itu uji retention pada H+13, H+14, H+29, dan H+30, termasuk cleanup retry, scheduler failure, dan attachment path yang tidak aman.

## Pilot wave

Wave 0 hanya internal/staging dengan `order` context. Wave 1 memakai cohort terbatas yang tercantum pada `VITE_CHAT_PILOT_USER_IDS`, roles buyer/merchant/courier, dan context order. Catat baseline active conversations, channel subscribed rate, reconnect success, event latency, notification delivery, query latency, retention lag, error rate, dan support incidents. Jangan mengaktifkan ride atau direct pra-order sebelum domain matrix dan privacy review lulus.

## Guardrails

Hold wave berikutnya jika terjadi cross-user leakage, duplicate message yang tidak pulih, channel error berulang, notification delivery failure, retention lag melewati satu periode, atau error rate meningkat melewati threshold yang disepakati operations. Threshold final wajib diisi pada dashboard/alert staging sebelum pilot; repository tidak menetapkan angka bisnis tanpa approval.

## Rollback

1. Set `VITE_CHAT_ROLLOUT_ENABLED=false` untuk menghentikan entry point chat pada wave yang terdampak.
2. Jangan menghapus data atau migration sebagai tindakan pertama; pertahankan evidence untuk investigasi.
3. Hentikan scheduler/worker retention hanya bila worker menyebabkan kerusakan, lalu catat backlog dan jalankan recovery terkontrol.
4. Jika notifikasi menyebabkan duplikasi, disable trigger `chat_messages_notify_recipient` setelah memastikan jalur fallback dan deduplication state terdokumentasi.
5. Revert deployment client ke commit sebelumnya hanya setelah flag kill switch aktif.
6. Validasi kembali RLS, unread state, retention queue, dan delivery metrics sebelum membuka wave.

Rollback tidak boleh menghapus audit event, notification idempotency keys, retention run records, atau message rows secara manual. Pengecualian legal/dispute harus mengikuti keputusan privacy/legal terpisah.
