import { describe, expect, it } from 'vitest';
import { evaluatePilotDecision, isPilotFeatureAllowed, type PilotGateEvidence } from './pilotRollout';

const baseEvidence: PilotGateEvidence = {
  stagingApproved: true,
  rollbackVerified: true,
  securityApproved: true,
  dataSeeded: true,
  financeReconciled: true,
  supportReady: true,
  merchantCount: 10,
  readyMerchantCount: 10,
  criticalIncidents: 0,
  duplicateTransactions: 0,
  unresolvedReconciliation: 0,
  supportSlaBreaches: 0,
  syncSuccessRate: 0.995,
  conflictRate: 0.01,
  trackMix: { marketplace_only: 2, pos: 8 },
};

describe('pilot rollout decision contract', () => {
  it('allows only a limited GO when all gates and thresholds pass', () => {
    const result = evaluatePilotDecision(baseEvidence);
    expect(result.decision).toBe('GO_LIMITED');
    expect(result.safeToEnableFeatures).toBe(true);
    expect(result.recommendedMaxMerchants).toBe(10);
  });

  it('fails closed with HOLD when staging evidence is missing', () => {
    const result = evaluatePilotDecision({ ...baseEvidence, stagingApproved: false });
    expect(result.decision).toBe('HOLD');
    expect(result.safeToEnableFeatures).toBe(false);
    expect(result.reasons.join(' ')).toContain('staging');
  });

  it('extends observation when reliability metrics are below threshold', () => {
    const result = evaluatePilotDecision({ ...baseEvidence, syncSuccessRate: 0.9, conflictRate: 0.1 });
    expect(result.decision).toBe('EXTEND_PILOT');
    expect(result.safeToEnableFeatures).toBe(false);
  });

  it('stops and rolls back for duplicate or unreconciled transactions', () => {
    const result = evaluatePilotDecision({ ...baseEvidence, duplicateTransactions: 1 });
    expect(result.decision).toBe('STOP_ROLLBACK');
    expect(result.recommendedMaxMerchants).toBe(0);
  });

  it('requires both GO decision and explicit wave allowlist for each feature', () => {
    expect(isPilotFeatureAllowed('chat_retry', 'GO_LIMITED', ['chat_retry'])).toBe(true);
    expect(isPilotFeatureAllowed('ride', 'GO_LIMITED', ['chat_retry'])).toBe(false);
    expect(isPilotFeatureAllowed('chat_retry', 'HOLD', ['chat_retry'])).toBe(false);
  });
});
