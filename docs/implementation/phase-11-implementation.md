# Implementasi Tahap 11 — Financial integrity dan admin control tower

Tahap 11 menutup gap produksi yang tersisa setelah governance tahap 10. Fokusnya adalah memastikan payout, refund, adjustment, fee, dan rekonsiliasi memiliki pemisahan state yang jelas, idempotency, maker-checker, external reference, serta audit trail.

## Fitur yang dikerjakan

### 1. Validator tindakan finansial
`validateFinancialAction` mendukung operasi:

- payout;
- refund;
- adjustment.

Validator memeriksa:

- nominal positif dan finite;
- idempotency key wajib;
- actor pengaju wajib tercatat;
- maker-checker untuk adjustment dan nominal berisiko tinggi;
- payout hanya setelah payment verified, fulfillment selesai, dispute clear, dan akun payout terverifikasi;
- refund wajib memiliki approval;
- adjustment wajib memiliki alasan;
- operasi settled tidak boleh diproses ulang.

### 2. Pemisahan status instruksi dan settlement
Tindakan finansial tidak lagi dianggap selesai hanya karena instruksi dibuat. Kontrak membedakan:

- `INSTRUCTION_ONLY` — validasi belum menghasilkan settlement;
- `APPROVED_PENDING_TRANSFER` — approval ada, transfer/refund aktual belum memiliki external reference;
- `SETTLED_REQUIRES_RECONCILIATION` — external reference tersedia, tetapi tetap harus direkonsiliasi.

### 3. Maker-checker dan risk hold
Self-approval ditolak untuk tindakan berisiko. Nominal minimal Rp1.000.000 dan seluruh adjustment memerlukan approver yang berbeda dari pengaju. Ini mencegah koreksi saldo, payout, atau refund berisiko dijalankan oleh satu actor tanpa kontrol kedua.

### 4. Settlement batch reconciliation
`evaluateSettlementBatch` menutup batch hanya jika:

- ledger seimbang;
- nominal expected dan actual sama;
- tidak ada duplicate idempotency key;
- semua operasi memiliki idempotency key;
- semua operasi memiliki external reference;
- audit event lengkap.

Batch dengan refund pending atau payout hold yang melewati SLA menghasilkan **ESCALATE**. Mismatch nominal, audit, atau idempotency menghasilkan **HOLD**.

### 5. Keputusan control tower
Kontrak tahap 11 menggunakan status:

- **RECONCILED** — batch aman ditutup;
- **HOLD** — perlu koreksi/review sebelum ditutup;
- **ESCALATE** — ada pending refund atau payout aging yang perlu owner dan tindakan segera.

## CI gate

CI menjalankan:

```bash
pnpm exec vitest run src/lib/phase11FinancialIntegrity.test.ts
```

Test mencakup maker-checker, duplicate settlement, pending transfer, balanced batch, aged payout/refund escalation, dan mismatch hold.

## Batasan

Kontrak ini belum mengirim transfer ke provider, mengubah ledger production, atau menggantikan approval workflow database. Dynamic RLS, RPC, provider sandbox, bank/acquirer reconciliation, audit sample, dan control tower UI tetap memerlukan staging terisolasi serta approval Finance, Operations, Security, dan Product.
