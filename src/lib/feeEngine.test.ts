import { describe, expect, it } from 'vitest';
import {
  calculateFeeSnapshot,
  canPublishFeeSchedule,
  selectFeeSchedule,
  validateFeeSchedule,
  type FeeSchedule,
} from './feeEngine';

const schedule: FeeSchedule = {
  version: '2026-09-v1',
  effectiveFrom: '2026-09-10T00:00:00.000Z',
  rules: [
    { id: 'platform-commission', label: 'Komisi platform', kind: 'commission', payer: 'merchant', ratePercent: 5 },
    { id: 'booking-fee', label: 'Booking fee', kind: 'booking', payer: 'buyer', fixedAmount: 1250 },
  ],
};

describe('feeEngine', () => {
  it('creates an immutable fee snapshot with payer-specific totals', () => {
    const snapshot = calculateFeeSnapshot({
      baseAmount: 50000,
      schedule,
      at: new Date('2026-09-10T12:00:00.000Z'),
    });
    expect(snapshot.lines).toHaveLength(2);
    expect(snapshot.merchantFees).toBe(2500);
    expect(snapshot.buyerFees).toBe(1250);
    expect(snapshot.merchantNet).toBe(47500);
    expect(snapshot.buyerTotal).toBe(51250);
    expect(snapshot.scheduleVersion).toBe('2026-09-v1');
  });

  it('rejects retroactive or invalid fee schedules', () => {
    expect(validateFeeSchedule({
      ...schedule,
      rules: [{ ...schedule.rules[0], ratePercent: 101 }],
    })).toContain('Rate fee platform-commission harus berada di antara 0 dan 100');
    expect(canPublishFeeSchedule(null, schedule, new Date('2026-09-11T00:00:00.000Z'))).toBe(false);
    expect(canPublishFeeSchedule(null, schedule, new Date('2026-09-01T00:00:00.000Z'))).toBe(true);
  });

  it('selects the latest schedule effective at transaction time', () => {
    const later = { ...schedule, version: '2026-10-v1', effectiveFrom: '2026-10-01T00:00:00.000Z' };
    expect(selectFeeSchedule([schedule, later], new Date('2026-09-20T00:00:00.000Z'))?.version).toBe('2026-09-v1');
    expect(selectFeeSchedule([schedule, later], new Date('2026-10-01T00:00:00.000Z'))?.version).toBe('2026-10-v1');
  });
});