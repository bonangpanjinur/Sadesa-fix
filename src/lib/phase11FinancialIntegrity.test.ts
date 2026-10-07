import { describe, expect, it } from 'vitest';
import { evaluateSettlementBatch, validateFinancialAction, type FinancialActionRequest, type SettlementBatchEvidence } from './phase11FinancialIntegrity';

const payout: FinancialActionRequest = {
  operation: 'payout',
  amount: 750_000,
  idempotencyKey: 'payout-1',
  requestedBy: 'ops-a',
  approvedBy: 'finance-a',
  externalReference: 'trf-1',
  paymentVerified: true,
  fulfillmentComplete: true,
  disputeClear: true,
  payoutAccountVerified: true,
  refundApproved: false,
  alreadySettled: false,
};

const balancedBatch: SettlementBatchEvidence = {
  ledgerBalanced: true,
  expectedAmount: 1_000_000,
  actualAmount: 1_000_000,
  operationCount: 2,
  duplicateIdempotencyCount: 0,
  missingExternalReferenceCount: 0,
  pendingRefundCount: 0,
  agedPayoutHoldCount: 0,
  auditEventCount: 2,
  allOperationsHaveIdempotency: true,
};

describe('phase 11 financial integrity contract', () => {
  it('allows a validated payout but labels it as reconciliation-required', () => {
    const result = validateFinancialAction(payout);
    expect(result.decision).toBe('ALLOW');
    expect(result.settlementLabel).toBe('SETTLED_REQUIRES_RECONCILIATION');
  });

  it('requires maker-checker for high-risk actions and rejects self-approval', () => {
    const result = validateFinancialAction({ ...payout, amount: 1_500_000, approvedBy: 'ops-a' });
    expect(result.decision).toBe('REVIEW');
    expect(result.requiresMakerChecker).toBe(true);
  });

  it('rejects duplicate settlement and missing idempotency keys', () => {
    expect(validateFinancialAction({ ...payout, alreadySettled: true }).decision).toBe('REJECT');
    expect(validateFinancialAction({ ...payout, idempotencyKey: '' }).decision).toBe('REJECT');
  });

  it('distinguishes pending transfer instructions from settled operations', () => {
    const result = validateFinancialAction({ ...payout, externalReference: undefined });
    expect(result.settlementLabel).toBe('APPROVED_PENDING_TRANSFER');
  });

  it('closes only a balanced, fully audited settlement batch', () => {
    expect(evaluateSettlementBatch(balancedBatch)).toEqual({
      decision: 'RECONCILED',
      reasons: ['Settlement batch seimbang dan seluruh operasi dapat diaudit.'],
      safeToClose: true,
    });
  });

  it('escalates pending refunds or aged payout holds', () => {
    const result = evaluateSettlementBatch({ ...balancedBatch, pendingRefundCount: 1 });
    expect(result.decision).toBe('ESCALATE');
    expect(result.safeToClose).toBe(false);
  });

  it('holds amount, audit, or idempotency mismatches', () => {
    const result = evaluateSettlementBatch({ ...balancedBatch, actualAmount: 999_000, auditEventCount: 1 });
    expect(result.decision).toBe('HOLD');
    expect(result.safeToClose).toBe(false);
  });
});
