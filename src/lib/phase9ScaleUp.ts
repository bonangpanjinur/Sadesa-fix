export type Phase9Decision = 'SCALE_LIMITED' | 'HOLD' | 'ROLLBACK';

export interface Phase9Evidence {
  observationDays: number;
  currentCohortSize: number;
  requestedCohortSize: number;
  dailyReconciliationDays: number;
  reconciliationMismatchCount: number;
  unresolvedCriticalIncidents: number;
  p0Count: number;
  tenantLeakageCount: number;
  duplicateTransactionCount: number;
  checkoutSuccessRate: number;
  orderCompletionRate: number;
  dispatchAcceptanceRate: number;
  chatP95LatencyMs: number;
  supportSlaBreachCount: number;
  feedbackResponseCount: number;
  feedbackCriticalCount: number;
  rollbackDrillPassed: boolean;
}

export interface Phase9DecisionResult {
  decision: Phase9Decision;
  reasons: string[];
  approvedCohortSize: number;
  featuresRemainEnabled: boolean;
}

export const PHASE9_THRESHOLDS = {
  minimumObservationDays: 7,
  minimumReconciliationDays: 7,
  maxCohortSize: 100,
  minCheckoutSuccessRate: 0.98,
  minOrderCompletionRate: 0.95,
  minDispatchAcceptanceRate: 0.8,
  maxChatP95LatencyMs: 2000,
} as const;

function count(value: number): number {
  return Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 0;
}

function rate(value: number): number {
  return Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : 0;
}

/**
 * Evaluates whether a pilot cohort can expand after a complete observation
 * cycle. This function does not mutate flags or provision users.
 */
export function evaluatePhase9ScaleUp(evidence: Phase9Evidence): Phase9DecisionResult {
  const reasons: string[] = [];
  const current = count(evidence.currentCohortSize);
  const requested = Math.min(PHASE9_THRESHOLDS.maxCohortSize, count(evidence.requestedCohortSize));
  const criticalIncidents = count(evidence.unresolvedCriticalIncidents);
  const p0 = count(evidence.p0Count);
  const leakage = count(evidence.tenantLeakageCount);
  const duplicates = count(evidence.duplicateTransactionCount);
  const mismatches = count(evidence.reconciliationMismatchCount);
  const criticalFeedback = count(evidence.feedbackCriticalCount);

  if (criticalIncidents > 0 || p0 > 0 || leakage > 0 || duplicates > 0 || mismatches > 0 || criticalFeedback > 0) {
    if (criticalIncidents > 0) reasons.push('Ada insiden kritis yang belum selesai.');
    if (p0 > 0) reasons.push('Masih ada issue P0 terbuka.');
    if (leakage > 0) reasons.push('Ada indikasi kebocoran antar-tenant.');
    if (duplicates > 0) reasons.push('Ada transaksi duplikat.');
    if (mismatches > 0) reasons.push('Rekonsiliasi harian memiliki mismatch.');
    if (criticalFeedback > 0) reasons.push('Ada feedback kritis yang belum ditutup.');
    return { decision: 'ROLLBACK', reasons, approvedCohortSize: 0, featuresRemainEnabled: false };
  }

  if (count(evidence.observationDays) < PHASE9_THRESHOLDS.minimumObservationDays) reasons.push('Siklus observasi belum mencapai 7 hari.');
  if (count(evidence.dailyReconciliationDays) < PHASE9_THRESHOLDS.minimumReconciliationDays) reasons.push('Rekonsiliasi harian belum lengkap selama 7 hari.');
  if (!evidence.rollbackDrillPassed) reasons.push('Rollback drill belum lulus.');
  if (count(evidence.supportSlaBreachCount) > 0) reasons.push('Masih ada pelanggaran SLA support.');
  if (count(evidence.feedbackResponseCount) === 0) reasons.push('Belum ada feedback task nyata dari pilot.');
  if (rate(evidence.checkoutSuccessRate) < PHASE9_THRESHOLDS.minCheckoutSuccessRate) reasons.push('Checkout success rate di bawah threshold.');
  if (rate(evidence.orderCompletionRate) < PHASE9_THRESHOLDS.minOrderCompletionRate) reasons.push('Order completion rate di bawah threshold.');
  if (rate(evidence.dispatchAcceptanceRate) < PHASE9_THRESHOLDS.minDispatchAcceptanceRate) reasons.push('Dispatch acceptance rate di bawah threshold.');
  if (!Number.isFinite(evidence.chatP95LatencyMs) || evidence.chatP95LatencyMs > PHASE9_THRESHOLDS.maxChatP95LatencyMs) reasons.push('Chat p95 latency di atas threshold.');

  if (reasons.length > 0) {
    return { decision: 'HOLD', reasons, approvedCohortSize: current, featuresRemainEnabled: false };
  }

  const approvedCohortSize = Math.max(current, Math.min(requested, PHASE9_THRESHOLDS.maxCohortSize));
  return {
    decision: 'SCALE_LIMITED',
    reasons: ['Siklus observasi, rekonsiliasi, metrik, feedback, dan rollback drill lulus.'],
    approvedCohortSize,
    featuresRemainEnabled: true,
  };
}
