import { describe, expect, it } from 'vitest';
import { evaluatePhase8Decision, type Phase8Evidence } from './phase8GoNoGo';

const passingEvidence: Phase8Evidence = {
  localTestsPassed: true,
  buildPassed: true,
  migrationChecksumMatched: true,
  rlsMatrixPassed: true,
  concurrencyPassed: true,
  realtimeRecoveryPassed: true,
  retentionEvidencePassed: true,
  visualBaselineAvailable: true,
  alertsActive: true,
  rollbackDrillPassed: true,
  moneyOrDataMismatch: false,
  securityLeakage: false,
  duplicateMessageOrTransaction: false,
  openP0Count: 0,
};

describe('phase 8 go/no-go contract', () => {
  it('returns GO only when every staging gate passes', () => {
    expect(evaluatePhase8Decision(passingEvidence)).toEqual({
      decision: 'GO',
      reasons: ['Seluruh gate staging dan rollout lulus.'],
      enabled: true,
    });
  });

  it('returns HOLD when a required evidence item is missing', () => {
    const result = evaluatePhase8Decision({ ...passingEvidence, alertsActive: false, visualBaselineAvailable: false });
    expect(result.decision).toBe('HOLD');
    expect(result.enabled).toBe(false);
    expect(result.reasons).toEqual(expect.arrayContaining([
      'Gate visual baseline belum lulus.',
      'Gate alert operasional belum lulus.',
    ]));
  });

  it('returns ROLLBACK for P0, leakage, duplicate, or mismatch signals', () => {
    const result = evaluatePhase8Decision({ ...passingEvidence, openP0Count: 1, securityLeakage: true });
    expect(result.decision).toBe('ROLLBACK');
    expect(result.enabled).toBe(false);
    expect(result.reasons).toEqual(expect.arrayContaining([
      'Ditemukan kebocoran security atau tenant.',
      'Masih ada 1 issue P0 terbuka.',
    ]));
  });

  it('normalizes invalid P0 count without allowing a false rollback', () => {
    expect(evaluatePhase8Decision({ ...passingEvidence, openP0Count: Number.NaN }).decision).toBe('GO');
  });
});
