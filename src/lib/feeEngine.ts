export type FeeKind = 'commission' | 'fixed' | 'booking' | 'featured_listing' | 'usage';
export type FeePayer = 'buyer' | 'merchant' | 'provider';

export interface FeeRule {
  id: string;
  label: string;
  kind: FeeKind;
  payer: FeePayer;
  ratePercent?: number;
  fixedAmount?: number;
  appliesTo?: readonly string[];
}

export interface FeeSchedule {
  version: string;
  effectiveFrom: string;
  rules: readonly FeeRule[];
}

export interface FeeSnapshotLine {
  ruleId: string;
  label: string;
  kind: FeeKind;
  payer: FeePayer;
  amount: number;
  ratePercent: number | null;
  fixedAmount: number | null;
}

export interface FeeSnapshot {
  scheduleVersion: string;
  effectiveFrom: string;
  baseAmount: number;
  buyerFees: number;
  merchantFees: number;
  providerFees: number;
  buyerTotal: number;
  merchantNet: number;
  providerNet: number;
  lines: FeeSnapshotLine[];
}

const percentageKinds = new Set<FeeKind>(['commission', 'usage']);

function nonNegative(value: number | undefined): number {
  return Math.max(0, Number(value) || 0);
}

function feeAmount(rule: FeeRule, baseAmount: number): number {
  if (percentageKinds.has(rule.kind)) {
    return Math.round(baseAmount * nonNegative(rule.ratePercent) / 100);
  }
  return Math.round(nonNegative(rule.fixedAmount));
}

export function validateFeeSchedule(schedule: FeeSchedule): string[] {
  const errors: string[] = [];
  if (!schedule.version.trim()) errors.push('Versi fee wajib diisi');
  if (!Number.isFinite(Date.parse(schedule.effectiveFrom))) errors.push('Tanggal efektif fee tidak valid');
  const ids = new Set<string>();
  for (const rule of schedule.rules) {
    if (!rule.id.trim()) errors.push('Setiap fee rule wajib memiliki id');
    if (ids.has(rule.id)) errors.push(`Fee rule duplikat: ${rule.id}`);
    ids.add(rule.id);
    if (percentageKinds.has(rule.kind) && (rule.ratePercent === undefined || rule.ratePercent < 0 || rule.ratePercent > 100)) {
      errors.push(`Rate fee ${rule.id} harus berada di antara 0 dan 100`);
    }
    if (!percentageKinds.has(rule.kind) && (rule.fixedAmount === undefined || rule.fixedAmount < 0)) {
      errors.push(`Nominal fee ${rule.id} tidak valid`);
    }
  }
  return errors;
}

/**
 * Fee schedules are forward-only. Existing orders keep their fee snapshot;
 * a newly published schedule may not rewrite an earlier period.
 */
export function canPublishFeeSchedule(
  previous: FeeSchedule | null,
  next: FeeSchedule,
  now = new Date(),
): boolean {
  if (validateFeeSchedule(next).length > 0) return false;
  if (Date.parse(next.effectiveFrom) < now.getTime()) return false;
  return !previous || Date.parse(next.effectiveFrom) > Date.parse(previous.effectiveFrom);
}

export function selectFeeSchedule(schedules: readonly FeeSchedule[], at: Date): FeeSchedule | null {
  return schedules
    .filter((schedule) => validateFeeSchedule(schedule).length === 0 && Date.parse(schedule.effectiveFrom) <= at.getTime())
    .sort((a, b) => Date.parse(b.effectiveFrom) - Date.parse(a.effectiveFrom))[0] || null;
}

export function calculateFeeSnapshot(input: {
  baseAmount: number;
  schedule: FeeSchedule;
  at?: Date;
}): FeeSnapshot {
  const amount = nonNegative(input.baseAmount);
  const errors = validateFeeSchedule(input.schedule);
  if (errors.length > 0) throw new Error(errors.join('; '));
  const at = input.at || new Date();
  if (Date.parse(input.schedule.effectiveFrom) > at.getTime()) {
    throw new Error('Fee schedule belum efektif pada waktu transaksi');
  }

  const lines = input.schedule.rules.map((rule) => ({
    ruleId: rule.id,
    label: rule.label,
    kind: rule.kind,
    payer: rule.payer,
    amount: feeAmount(rule, amount),
    ratePercent: rule.ratePercent ?? null,
    fixedAmount: rule.fixedAmount ?? null,
  }));
  const buyerFees = lines.filter((line) => line.payer === 'buyer').reduce((sum, line) => sum + line.amount, 0);
  const merchantFees = lines.filter((line) => line.payer === 'merchant').reduce((sum, line) => sum + line.amount, 0);
  const providerFees = lines.filter((line) => line.payer === 'provider').reduce((sum, line) => sum + line.amount, 0);

  return {
    scheduleVersion: input.schedule.version,
    effectiveFrom: input.schedule.effectiveFrom,
    baseAmount: amount,
    buyerFees,
    merchantFees,
    providerFees,
    buyerTotal: amount + buyerFees,
    merchantNet: Math.max(0, amount - merchantFees),
    providerNet: Math.max(0, amount - providerFees),
    lines,
  };
}