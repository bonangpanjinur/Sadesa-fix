import { describe, expect, it } from 'vitest';
import { evaluatePhase10Governance, type Phase10Evidence } from './phase10Governance';

const passingEvidence: Phase10Evidence = {
  reviewWindowDays: 30,
  metricReconciliationComplete: true,
  orderPaymentSupportParity: true,
  openP0Count: 0,
  openP1Count: 2,
  overdueIncidentCount: 0,
  recurringIncidentCount: 0,
  postmortemCompletionRate: 1,
  supportSlaComplianceRate: 0.98,
  auditCompletenessRate: 1,
  unresolvedFinanceMismatchCount: 0,
  unresolvedSecurityFindingCount: 0,
  merchantFeedbackCount: 8,
  criticalMerchantFeedbackCount: 0,
  rollbackPlanCurrent: true,
};

describe('phase 10 governance contract', () => {
  it('continues operations when 30-day evidence is complete', () => {
    const result = evaluatePhase10Governance(passingEvidence);
    expect(result).toEqual({
      decision: 'CONTINUE',
      reasons: ['Review governance, rekonsiliasi, incident, support, audit, dan feedback lulus.'],
      followUpWithinDays: 30,
      continueFeatures: true,
    });
  });

  it('requires improvement when operational evidence is incomplete', () => {
    const result = evaluatePhase10Governance({
      ...passingEvidence,
      supportSlaComplianceRate: 0.8,
      auditCompletenessRate: 0.9,
      recurringIncidentCount: 1,
      rollbackPlanCurrent: false,
    });
    expect(result.decision).toBe('IMPROVE');
    expect(result.continueFeatures).toBe(false);
    expect(result.followUpWithinDays).toBe(7);
  });

  it('pauses immediately for financial, security, critical feedback, or P0 risk', () => {
    const result = evaluatePhase10Governance({ ...passingEvidence, unresolvedFinanceMismatchCount: 1, openP0Count: 1 });
    expect(result.decision).toBe('PAUSE');
    expect(result.continueFeatures).toBe(false);
    expect(result.followUpWithinDays).toBe(1);
  });

  it('fails closed for invalid rates and insufficient feedback', () => {
    const result = evaluatePhase10Governance({
      ...passingEvidence,
      supportSlaComplianceRate: Number.NaN,
      merchantFeedbackCount: 0,
    });
    expect(result.decision).toBe('IMPROVE');
  });
});
