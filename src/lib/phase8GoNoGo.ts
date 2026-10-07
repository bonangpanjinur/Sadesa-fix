export type Phase8Decision = 'GO' | 'HOLD' | 'ROLLBACK';

export interface Phase8Evidence {
  localTestsPassed: boolean;
  buildPassed: boolean;
  migrationChecksumMatched: boolean;
  rlsMatrixPassed: boolean;
  concurrencyPassed: boolean;
  realtimeRecoveryPassed: boolean;
  retentionEvidencePassed: boolean;
  visualBaselineAvailable: boolean;
  alertsActive: boolean;
  rollbackDrillPassed: boolean;
  moneyOrDataMismatch: boolean;
  securityLeakage: boolean;
  duplicateMessageOrTransaction: boolean;
  openP0Count: number;
}

export interface Phase8DecisionResult {
  decision: Phase8Decision;
  reasons: string[];
  enabled: boolean;
}

const REQUIRED_GATES: readonly [keyof Phase8Evidence, string][] = [
  ['localTestsPassed', 'test lokal'],
  ['buildPassed', 'production build'],
  ['migrationChecksumMatched', 'migration checksum staging'],
  ['rlsMatrixPassed', 'RLS matrix'],
  ['concurrencyPassed', 'concurrency test'],
  ['realtimeRecoveryPassed', 'realtime recovery'],
  ['retentionEvidencePassed', 'retention evidence'],
  ['visualBaselineAvailable', 'visual baseline'],
  ['alertsActive', 'alert operasional'],
  ['rollbackDrillPassed', 'rollback drill'],
];

/**
 * Production release remains disabled unless every required staging gate passes.
 * Any money/data mismatch, security leakage, duplicate transaction/message, or P0
 * issue is an immediate rollback signal rather than a normal hold.
 */
export function evaluatePhase8Decision(evidence: Phase8Evidence): Phase8DecisionResult {
  const reasons: string[] = [];
  const p0Count = Number.isFinite(evidence.openP0Count) ? Math.max(0, evidence.openP0Count) : 0;

  if (evidence.moneyOrDataMismatch) reasons.push('Ditemukan mismatch uang atau data.');
  if (evidence.securityLeakage) reasons.push('Ditemukan kebocoran security atau tenant.');
  if (evidence.duplicateMessageOrTransaction) reasons.push('Ditemukan duplikasi pesan atau transaksi.');
  if (p0Count > 0) reasons.push(`Masih ada ${p0Count} issue P0 terbuka.`);
  if (reasons.length > 0) return { decision: 'ROLLBACK', reasons, enabled: false };

  for (const [key, label] of REQUIRED_GATES) {
    if (evidence[key] !== true) reasons.push(`Gate ${label} belum lulus.`);
  }
  if (reasons.length > 0) return { decision: 'HOLD', reasons, enabled: false };

  return { decision: 'GO', reasons: ['Seluruh gate staging dan rollout lulus.'], enabled: true };
}
