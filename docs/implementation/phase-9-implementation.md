# Implementasi Tahap 9 — Operational scale-up setelah pilot

Roadmap repository sebelumnya berhenti pada tahap 8. Tahap 9 didefinisikan sebagai fase setelah pilot: memperluas cohort secara terkendali berdasarkan evidence operasional, bukan membuka traffic secara otomatis.

## Fitur yang dikerjakan

### 1. Evaluasi siklus observasi tujuh hari
`evaluatePhase9ScaleUp` mensyaratkan:

- minimal 7 hari observasi;
- minimal 7 hari rekonsiliasi harian order-payment-refund/COD;
- rollback drill telah lulus;
- feedback dari task nyata pilot tersedia;
- tidak ada pelanggaran SLA support yang belum selesai.

### 2. Metrik scale-up
Evaluator memeriksa baseline berikut:

- checkout success rate minimal 98%;
- order completion rate minimal 95%;
- dispatch acceptance rate minimal 80%;
- chat p95 latency maksimal 2 detik;
- jumlah cohort baru dibatasi maksimal 100 user/merchant sesuai keputusan operator.

### 3. Keputusan fail-closed

- **SCALE_LIMITED** — semua evidence dan threshold lulus; cohort boleh diperbesar sampai batas yang disetujui.
- **HOLD** — evidence atau metrik belum lengkap; cohort tetap pada ukuran saat ini dan feature baru tidak diperluas.
- **ROLLBACK** — ada tenant leakage, transaksi duplikat, mismatch rekonsiliasi, insiden kritis, feedback kritis, atau P0 terbuka; feature harus dinonaktifkan melalui kill switch.

### 4. Feedback dan support operations
Tahap ini menjadikan feedback task nyata dan support SLA sebagai input release, bukan sekadar catatan manual. Tanpa response feedback atau dengan pelanggaran SLA, evaluator tidak memberi izin scale-up.

### 5. CI gate
CI menjalankan:

```bash
pnpm exec vitest run src/lib/phase9ScaleUp.test.ts
```

Test mencakup clean scale-up, HOLD karena evidence/meterik, ROLLBACK karena integritas, dan pembatasan cohort maksimum.

## Batasan

Kontrak ini tidak mengubah feature flag, menambah user, atau melakukan deployment production. Dynamic reconciliation, provider sandbox, RLS, device/PWA/printer, support log, dan rollback aktual tetap harus dijalankan serta disetujui pada environment staging/production oleh owner terkait.
