
## Penguatan tahap 8

### Kontrak go/no-go executable

`evaluatePhase8Decision` memeriksa evidence berikut sebelum release:

- test lokal dan production build;
- migration checksum staging;
- RLS matrix dan concurrency test;
- realtime reconnect/recovery;
- retention evidence;
- visual regression baseline;
- alert operasional aktif;
- rollback drill berhasil.

Hasilnya bersifat fail-closed:

- **GO** hanya jika seluruh gate lulus;
- **HOLD** jika evidence wajib belum lengkap;
- **ROLLBACK** jika terdapat mismatch uang/data, kebocoran security/tenant, duplikasi pesan/transaksi, atau P0 terbuka.

Keputusan `GO` hanya menghasilkan rekomendasi readiness. Ia tidak mengubah feature flag atau traffic production secara otomatis.

### Production chat allowlist hardening

Production chat sekarang menolak akses jika `VITE_CHAT_PILOT_USER_IDS` kosong. Sebelumnya, allowlist kosong dapat membuat request yang role dan context-nya valid lolos saat rollout enabled. Alasan penolakan baru adalah `pilot_not_configured`, sehingga operator dapat membedakan konfigurasi pilot yang belum siap dari user yang tidak termasuk cohort.

### Quality gate

CI menjalankan acceptance matrix chat dan kontrak go/no-go tahap 8 sebagai test terpisah melalui:

```bash
pnpm run test:chat:phase8
pnpm exec vitest run src/lib/phase8GoNoGo.test.ts
```

Dynamic staging test, RLS runtime, provider sandbox, visual device matrix, scheduler/retention, dan rollback drill tetap harus dijalankan pada environment staging terisolasi sebelum production sign-off.
