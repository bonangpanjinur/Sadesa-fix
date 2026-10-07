import type { PilotMerchantTrack } from './pilotReadiness';

export type PilotDecision = 'GO_LIMITED' | 'EXTEND_PILOT' | 'HOLD' | 'STOP_ROLLBACK';
export type PilotFeature = 'ride' | 'courier_booking' | 'chat_retry' | 'settlement_worker' | 'guest_checkout';

export interface PilotGateEvidence {
  stagingApproved: boolean;
  rollbackVerified: boolean;
  securityApproved: boolean;
  dataSeeded: boolean;
  financeReconciled: boolean;
  supportReady: boolean;
  merchantCount: number;
  readyMerchantCount: number;
  criticalIncidents: number;
  duplicateTransactions: number;
  unresolvedReconciliation: number;
  supportSlaBreaches: number;
  syncSuccessRate: number;
  conflictRate: number;
  trackMix: Partial<Record<PilotMerchantTrack, number>>;
}

export interface PilotDecisionResult {
  decision: PilotDecision;
  reasons: string[];
  safeToEnableFeatures: boolean;
  recommendedMaxMerchants: number;
}

export const PILOT_THRESHOLDS = {
  minMerchants: 1,
  maxMerchants: 20,
  minSyncSuccessRate: 0.98,
  maxConflictRate: 0.05,
} as const;

function nonNegative(value: number): number {
  return Number.isFinite(value) ? Math.max(0, value) : 0;
}

function boundedRate(value: number): number {
  return Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : 0;
}

/**
 * Computes a conservative pilot decision. Production traffic must still be
 * enabled through the operator's approved feature flag/configuration path.
 */
export function evaluatePilotDecision(evidence: PilotGateEvidence): PilotDecisionResult {
  const reasons: string[] = [];
  const merchantCount = nonNegative(evidence.merchantCount);
  const readyMerchantCount = nonNegative(evidence.readyMerchantCount);
  const criticalIncidents = nonNegative(evidence.criticalIncidents);
  const duplicateTransactions = nonNegative(evidence.duplicateTransactions);
  const unresolvedReconciliation = nonNegative(evidence.unresolvedReconciliation);
  const supportSlaBreaches = nonNegative(evidence.supportSlaBreaches);
  const syncSuccessRate = boundedRate(evidence.syncSuccessRate);
  const conflictRate = boundedRate(evidence.conflictRate);

  if (criticalIncidents > 0 || duplicateTransactions > 0 || unresolvedReconciliation > 0) {
    if (criticalIncidents > 0) reasons.push('Ada insiden kritis yang belum ditutup.');
    if (duplicateTransactions > 0) reasons.push('Ditemukan transaksi duplikat.');
    if (unresolvedReconciliation > 0) reasons.push('Ada selisih rekonsiliasi yang belum dijelaskan.');
    return { decision: 'STOP_ROLLBACK', reasons, safeToEnableFeatures: false, recommendedMaxMerchants: 0 };
  }

  const missingGates = [
    ['staging', evidence.stagingApproved],
    ['rollback', evidence.rollbackVerified],
    ['security', evidence.securityApproved],
    ['data seed', evidence.dataSeeded],
    ['finance', evidence.financeReconciled],
    ['support', evidence.supportReady],
  ].filter(([, passed]) => !passed).map(([name]) => name);
  if (missingGates.length > 0) reasons.push(`Gate belum lulus: ${missingGates.join(', ')}.`);
  if (merchantCount < PILOT_THRESHOLDS.minMerchants) reasons.push('Belum ada merchant pilot yang terdaftar.');
  if (readyMerchantCount < merchantCount) reasons.push('Sebagian merchant belum menyelesaikan readiness milestone.');
  if (syncSuccessRate < PILOT_THRESHOLDS.minSyncSuccessRate) reasons.push('Sync success rate di bawah threshold pilot.');
  if (conflictRate > PILOT_THRESHOLDS.maxConflictRate) reasons.push('Conflict rate di atas threshold pilot.');
  if (supportSlaBreaches > 0) reasons.push('Ada pelanggaran SLA support yang belum ditindaklanjuti.');

  if (missingGates.length > 0 || merchantCount < PILOT_THRESHOLDS.minMerchants || readyMerchantCount < merchantCount) {
    return { decision: 'HOLD', reasons, safeToEnableFeatures: false, recommendedMaxMerchants: 0 };
  }

  if (syncSuccessRate < PILOT_THRESHOLDS.minSyncSuccessRate || conflictRate > PILOT_THRESHOLDS.maxConflictRate || supportSlaBreaches > 0) {
    return { decision: 'EXTEND_PILOT', reasons, safeToEnableFeatures: false, recommendedMaxMerchants: Math.min(merchantCount, PILOT_THRESHOLDS.maxMerchants) };
  }

  if (merchantCount > PILOT_THRESHOLDS.maxMerchants) {
    reasons.push(`Jumlah merchant melebihi batas pilot ${PILOT_THRESHOLDS.maxMerchants}.`);
    return { decision: 'HOLD', reasons, safeToEnableFeatures: false, recommendedMaxMerchants: PILOT_THRESHOLDS.maxMerchants };
  }

  return {
    decision: 'GO_LIMITED',
    reasons: ['Semua gate dan threshold pilot lulus.'],
    safeToEnableFeatures: true,
    recommendedMaxMerchants: merchantCount,
  };
}

/** Feature flags are subordinate to the pilot decision and explicit wave allowlist. */
export function isPilotFeatureAllowed(
  feature: PilotFeature,
  decision: PilotDecision,
  allowlist: readonly PilotFeature[],
): boolean {
  return decision === 'GO_LIMITED' && allowlist.includes(feature);
}
