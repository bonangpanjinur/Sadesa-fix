export type FinancialOperation = 'payout' | 'refund' | 'adjustment';
export type FinancialActionDecision = 'ALLOW' | 'REVIEW' | 'REJECT';
export type SettlementBatchDecision = 'RECONCILED' | 'HOLD' | 'ESCALATE';

export interface FinancialActionRequest {
  operation: FinancialOperation;
  amount: number;
  idempotencyKey: string;
  requestedBy: string;
  approvedBy?: string;
  externalReference?: string;
  paymentVerified: boolean;
  fulfillmentComplete: boolean;
  disputeClear: boolean;
  payoutAccountVerified: boolean;
  refundApproved: boolean;
  reason?: string;
  alreadySettled: boolean;
}

export interface FinancialActionResult {
  decision: FinancialActionDecision;
  reasons: string[];
  requiresMakerChecker: boolean;
  settlementLabel: 'INSTRUCTION_ONLY' | 'APPROVED_PENDING_TRANSFER' | 'SETTLED_REQUIRES_RECONCILIATION';
}

export interface SettlementBatchEvidence {
  ledgerBalanced: boolean;
  expectedAmount: number;
  actualAmount: number;
  operationCount: number;
  duplicateIdempotencyCount: number;
  missingExternalReferenceCount: number;
  pendingRefundCount: number;
  agedPayoutHoldCount: number;
  auditEventCount: number;
  allOperationsHaveIdempotency: boolean;
}

export interface SettlementBatchResult {
  decision: SettlementBatchDecision;
  reasons: string[];
  safeToClose: boolean;
}

export const HIGH_RISK_AMOUNT = 1_000_000;

function positiveFinite(value: number): number {
  return Number.isFinite(value) ? Math.max(0, value) : 0;
}

function hasText(value: string | undefined): boolean {
  return typeof value === 'string' && value.trim().length > 0;
}

/** Separates a business instruction from an actual transfer/refund settlement. */
export function validateFinancialAction(request: FinancialActionRequest): FinancialActionResult {
  const reasons: string[] = [];
  const amount = positiveFinite(request.amount);
  const requiresMakerChecker = amount >= HIGH_RISK_AMOUNT || request.operation === 'adjustment';
  const hasDistinctApprover = hasText(request.approvedBy) && request.approvedBy !== request.requestedBy;

  if (amount <= 0) reasons.push('Nominal harus lebih besar dari nol.');
  if (!hasText(request.idempotencyKey)) reasons.push('Idempotency key wajib tersedia.');
  if (!hasText(request.requestedBy)) reasons.push('Actor pengaju wajib tersedia.');
  if (requiresMakerChecker && !hasDistinctApprover) reasons.push('Tindakan berisiko membutuhkan approver berbeda dari pengaju.');
  if (request.alreadySettled) reasons.push('Operasi sudah settled dan tidak boleh diproses ulang.');

  if (request.operation === 'payout') {
    if (!request.paymentVerified) reasons.push('Payment belum terverifikasi.');
    if (!request.fulfillmentComplete) reasons.push('Fulfillment belum selesai.');
    if (!request.disputeClear) reasons.push('Dispute masih terbuka.');
    if (!request.payoutAccountVerified) reasons.push('Akun payout belum terverifikasi.');
  }
  if (request.operation === 'refund') {
    if (!request.refundApproved) reasons.push('Refund belum mendapat approval.');
  }
  if (request.operation === 'adjustment' && !hasText(request.reason)) reasons.push('Adjustment wajib memiliki alasan.');

  if (reasons.length > 0) {
    const hardStop = request.alreadySettled || !hasText(request.idempotencyKey) || amount <= 0;
    return {
      decision: hardStop ? 'REJECT' : 'REVIEW',
      reasons,
      requiresMakerChecker,
      settlementLabel: 'INSTRUCTION_ONLY',
    };
  }

  if (!hasText(request.externalReference)) {
    return {
      decision: 'ALLOW',
      reasons: ['Instruksi lolos validasi; transfer/refund aktual masih pending.'],
      requiresMakerChecker,
      settlementLabel: 'APPROVED_PENDING_TRANSFER',
    };
  }

  return {
    decision: 'ALLOW',
    reasons: ['Transfer/refund memiliki external reference dan menunggu rekonsiliasi.'],
    requiresMakerChecker,
    settlementLabel: 'SETTLED_REQUIRES_RECONCILIATION',
  };
}

/** A batch is closed only after amount, idempotency, reference, and audit checks agree. */
export function evaluateSettlementBatch(evidence: SettlementBatchEvidence): SettlementBatchResult {
  const reasons: string[] = [];
  const expected = positiveFinite(evidence.expectedAmount);
  const actual = positiveFinite(evidence.actualAmount);
  const difference = Math.abs(expected - actual);

  if (!evidence.ledgerBalanced || difference > 0.01) reasons.push('Ledger dan nominal settlement tidak seimbang.');
  if (evidence.duplicateIdempotencyCount > 0) reasons.push('Ada idempotency key duplikat.');
  if (evidence.missingExternalReferenceCount > 0) reasons.push('Ada operasi settlement tanpa external reference.');
  if (!evidence.allOperationsHaveIdempotency) reasons.push('Ada operasi tanpa idempotency key.');
  if (evidence.auditEventCount < evidence.operationCount) reasons.push('Audit event belum lengkap untuk seluruh operasi.');

  if (evidence.pendingRefundCount > 0 || evidence.agedPayoutHoldCount > 0) {
    if (evidence.pendingRefundCount > 0) reasons.push('Masih ada refund pending.');
    if (evidence.agedPayoutHoldCount > 0) reasons.push('Ada payout hold yang melewati SLA.');
    return { decision: 'ESCALATE', reasons, safeToClose: false };
  }
  if (reasons.length > 0) return { decision: 'HOLD', reasons, safeToClose: false };
  return { decision: 'RECONCILED', reasons: ['Settlement batch seimbang dan seluruh operasi dapat diaudit.'], safeToClose: true };
}
