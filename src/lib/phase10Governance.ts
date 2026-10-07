export type Phase10Decision = 'CONTINUE' | 'IMPROVE' | 'PAUSE';

export interface Phase10Evidence {
  reviewWindowDays: number;
  metricReconciliationComplete: boolean;
  orderPaymentSupportParity: boolean;
  openP0Count: number;
  openP1Count: number;
  overdueIncidentCount: number;
  recurringIncidentCount: number;
  postmortemCompletionRate: number;
  supportSlaComplianceRate: number;
  auditCompletenessRate: number;
  unresolvedFinanceMismatchCount: number;
  unresolvedSecurityFindingCount: number;
  merchantFeedbackCount: number;
  criticalMerchantFeedbackCount: number;
  rollbackPlanCurrent: boolean;
}

export interface Phase10DecisionResult {
  decision: Phase10Decision;
  reasons: string[];
  followUpWithinDays: number;
  continueFeatures: boolean;
}

export const PHASE10_THRESHOLDS = {
  minimumReviewWindowDays: 30,
  maxOpenP1: 5,
  maxOverdueIncidents: 0,
  minPostmortemCompletionRate: 0.9,
  minSupportSlaComplianceRate: 0.95,
  minAuditCompletenessRate: 0.98,
  minMerchantFeedbackCount: 3,
} as const;

function count(value: number): number {
  return Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 0;
}

function rate(value: number): number {
  return Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : 0;
}

/**
 * Converts recurring operational evidence into an explicit governance decision.
 * It never mutates feature flags, financial records, or cohort membership.
 */
export function evaluatePhase10Governance(evidence: Phase10Evidence): Phase10DecisionResult {
  const reasons: string[] = [];
  const openP0 = count(evidence.openP0Count);
  const openP1 = count(evidence.openP1Count);
  const overdue = count(evidence.overdueIncidentCount);
  const recurring = count(evidence.recurringIncidentCount);
  const financeMismatch = count(evidence.unresolvedFinanceMismatchCount);
  const securityFinding = count(evidence.unresolvedSecurityFindingCount);
  const criticalFeedback = count(evidence.criticalMerchantFeedbackCount);

  if (openP0 > 0 || financeMismatch > 0 || securityFinding > 0 || criticalFeedback > 0) {
    if (openP0 > 0) reasons.push('Masih ada issue P0 terbuka.');
    if (financeMismatch > 0) reasons.push('Ada mismatch finance yang belum direkonsiliasi.');
    if (securityFinding > 0) reasons.push('Ada security finding yang belum ditutup.');
    if (criticalFeedback > 0) reasons.push('Ada feedback merchant kritis yang belum ditindaklanjuti.');
    return { decision: 'PAUSE', reasons, followUpWithinDays: 1, continueFeatures: false };
  }

  if (count(evidence.reviewWindowDays) < PHASE10_THRESHOLDS.minimumReviewWindowDays) reasons.push('Review window belum mencapai 30 hari.');
  if (!evidence.metricReconciliationComplete) reasons.push('Rekonsiliasi metrik belum selesai.');
  if (!evidence.orderPaymentSupportParity) reasons.push('KPI belum cocok dengan source of truth order/payment/support.');
  if (openP1 > PHASE10_THRESHOLDS.maxOpenP1) reasons.push('Jumlah issue P1 terbuka melewati batas.');
  if (overdue > PHASE10_THRESHOLDS.maxOverdueIncidents) reasons.push('Masih ada incident overdue.');
  if (rate(evidence.postmortemCompletionRate) < PHASE10_THRESHOLDS.minPostmortemCompletionRate) reasons.push('Postmortem incident belum lengkap.');
  if (rate(evidence.supportSlaComplianceRate) < PHASE10_THRESHOLDS.minSupportSlaComplianceRate) reasons.push('Kepatuhan SLA support di bawah threshold.');
  if (rate(evidence.auditCompletenessRate) < PHASE10_THRESHOLDS.minAuditCompletenessRate) reasons.push('Audit trail belum lengkap.');
  if (count(evidence.merchantFeedbackCount) < PHASE10_THRESHOLDS.minMerchantFeedbackCount) reasons.push('Feedback merchant belum cukup untuk review.');
  if (!evidence.rollbackPlanCurrent) reasons.push('Rollback plan sudah tidak current.');
  if (recurring > 0) reasons.push('Ada incident berulang yang memerlukan remediation permanen.');

  if (reasons.length > 0) return { decision: 'IMPROVE', reasons, followUpWithinDays: 7, continueFeatures: false };

  return {
    decision: 'CONTINUE',
    reasons: ['Review governance, rekonsiliasi, incident, support, audit, dan feedback lulus.'],
    followUpWithinDays: 30,
    continueFeatures: true,
  };
}
