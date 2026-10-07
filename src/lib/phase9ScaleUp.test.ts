import { describe, expect, it } from 'vitest';
import { evaluatePhase9ScaleUp, type Phase9Evidence } from './phase9ScaleUp';

const passingEvidence: Phase9Evidence = {
  observationDays: 7,
  currentCohortSize: 20,
  requestedCohortSize: 40,
  dailyReconciliationDays: 7,
  reconciliationMismatchCount: 0,
  unresolvedCriticalIncidents: 0,
  p0Count: 0,
  tenantLeakageCount: 0,
  duplicateTransactionCount: 0,
  checkoutSuccessRate: 0.99,
  orderCompletionRate: 0.97,
  dispatchAcceptanceRate: 0.85,
  chatP95LatencyMs: 1500,
  supportSlaBreachCount: 0,
  feedbackResponseCount: 12,
  feedbackCriticalCount: 0,
  rollbackDrillPassed: true,
};

describe('phase 9 scale-up contract', () => {
  it('approves limited cohort expansion after a clean seven-day cycle', () => {
    const result = evaluatePhase9ScaleUp(passingEvidence);
    expect(result.decision).toBe('SCALE_LIMITED');
    expect(result.approvedCohortSize).toBe(40);
    expect(result.featuresRemainEnabled).toBe(true);
  });

  it('holds expansion when evidence or metrics are incomplete', () => {
    const result = evaluatePhase9ScaleUp({
      ...passingEvidence,
      dailyReconciliationDays: 4,
      chatP95LatencyMs: 2500,
      supportSlaBreachCount: 1,
    });
    expect(result.decision).toBe('HOLD');
    expect(result.approvedCohortSize).toBe(20);
    expect(result.featuresRemainEnabled).toBe(false);
  });

  it('rolls back immediately for leakage, duplicates, mismatch, or open P0', () => {
    const result = evaluatePhase9ScaleUp({ ...passingEvidence, tenantLeakageCount: 1, duplicateTransactionCount: 1 });
    expect(result.decision).toBe('ROLLBACK');
    expect(result.approvedCohortSize).toBe(0);
    expect(result.featuresRemainEnabled).toBe(false);
  });

  it('caps an approved cohort at the phase 9 maximum', () => {
    const result = evaluatePhase9ScaleUp({ ...passingEvidence, requestedCohortSize: 1000 });
    expect(result.decision).toBe('SCALE_LIMITED');
    expect(result.approvedCohortSize).toBe(100);
  });
});
