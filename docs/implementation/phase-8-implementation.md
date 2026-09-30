# Evidence implementasi Fase 8 — Testing, pilot, dan rollout

Fase 8 menambahkan acceptance matrix executable dan kontrol rollout yang fail-closed. Test `src/lib/chat/phase8Acceptance.test.ts` memeriksa kontrak security/database, realtime/reliability, retention, notification/observability, serta feature flag pilot. Test ini adalah guardrail repository; ia tidak menggantikan uji staging terhadap RLS, Supabase Realtime, storage, scheduler, atau provider push.

## Acceptance matrix

| Kelompok | Kontrak yang diuji di repository | Evidence staging yang masih wajib |
|---|---|---|
| Security | Pair isolation, participant validation, immutable send RPC, authenticated caller | Buyer A/B pada merchant sama, cross-order/ride, spoof sender/receiver, admin audit |
| Database | Unique pair, RPC authorization, client ID idempotency, restricted mutation | Constraint/RLS SELECT-INSERT-UPDATE-DELETE dan race condition pada clone staging |
| Realtime | Subscribe, timeout, channel error, closed, reconnect metric, delivery latency | Dua tab, background tab, network switch, duplicate event, catch-up setelah reconnect |
| Reliability | Retry recovery dan client message ID | Timeout setelah commit, reload setelah event, cursor pagination |
| Retention | Claims dengan `SKIP LOCKED`, batch worker, attachment path validation | Simulasi H+13/H+14/H+29/H+30, retry cleanup, scheduler failure, storage cleanup |
| UI | Existing chat UI states dan shared repository contracts | Mobile keyboard, screen reader, focus management, offline/closed state |
| Performance | Query latency/active conversation metrics | Inbox/history besar, concurrent send, rate limit, cleanup batch |
| Domain | Rollout role/context matrix | Buyer–merchant, buyer–courier, passenger–courier, merchant–courier end-to-end |

## Rollout control

`src/lib/chat/rollout.ts` membaca `VITE_CHAT_ROLLOUT_ENABLED`, `VITE_CHAT_ROLLOUT_ROLES`, `VITE_CHAT_ROLLOUT_CONTEXTS`, dan `VITE_CHAT_PILOT_USER_IDS`. Production default-nya disabled. Pilot production hanya mengizinkan role, context, dan user ID yang tercantum. Rekomendasi wave adalah order chat internal/staging terlebih dahulu, lalu satu cohort buyer–merchant–courier yang disetujui. Ride (`ride`) dan direct pra-order tidak dibuka pada wave awal.

Feature flag harus dievaluasi sebelum entry point chat dibuat. Perubahan environment variables harus melalui release record dan tidak boleh menjadi cara untuk melewati RLS. RLS/RPC tetap otorisasi final.

## Go/no-go checklist

Go hanya jika seluruh test lokal lulus, migration checksum staging cocok, RLS matrix tidak memiliki leakage, reconnect dan retry tidak menggandakan pesan, retention evidence tersedia, alert aktif, rollback drill berhasil, dan product/operations/security/privacy memberikan sign-off. Jika salah satu guardrail gagal, keputusan adalah **hold** atau **rollback**, bukan memperluas cohort.

Staging/pilot execution belum diklaim selesai oleh commit ini karena memerlukan project Supabase staging, data uji terisolasi, scheduler, storage, dan approver bisnis. Runbook eksekusi dan rollback tersedia pada `docs/operations/chat-phase-8-runbook.md`.
