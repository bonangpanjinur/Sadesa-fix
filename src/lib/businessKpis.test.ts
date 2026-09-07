import { describe, expect, it } from 'vitest';
import { calculatePosBusinessMetrics } from './businessKpis';

const baseDate = new Date('2026-09-08T00:00:00.000Z');

describe('calculatePosBusinessMetrics', () => {
  it('calculates attach, conversion, MRR, churn, and sync health from canonical rows', () => {
    const metrics = calculatePosBusinessMetrics(
      {
        totalMerchants: 4,
        tenants: [{ merchant_id: 'm1' }, { merchant_id: 'm2' }, { merchant_id: null }],
        subscriptions: [
          {
            merchant_id: 'm1',
            is_trial: true,
            status: 'EXPIRED',
            payment_status: 'FREE',
            payment_amount: 0,
            created_at: '2026-07-01T00:00:00.000Z',
            updated_at: '2026-07-15T00:00:00.000Z',
            started_at: '2026-07-01T00:00:00.000Z',
          },
          {
            merchant_id: 'm1',
            is_trial: false,
            status: 'ACTIVE',
            payment_status: 'PAID',
            payment_amount: 100000,
            created_at: '2026-07-16T00:00:00.000Z',
            updated_at: '2026-07-16T00:00:00.000Z',
            started_at: '2026-07-16T00:00:00.000Z',
            package_duration_months: 1,
          },
          {
            merchant_id: 'm2',
            is_trial: false,
            status: 'CANCELLED',
            payment_status: 'PAID',
            payment_amount: 240000,
            created_at: '2026-06-01T00:00:00.000Z',
            updated_at: '2026-08-20T00:00:00.000Z',
            started_at: '2026-06-01T00:00:00.000Z',
            package_duration_months: 3,
          },
          {
            merchant_id: 'm3',
            is_trial: true,
            status: 'trial',
            payment_status: 'FREE',
            payment_amount: 0,
            created_at: '2026-08-20T00:00:00.000Z',
            updated_at: '2026-08-20T00:00:00.000Z',
            started_at: '2026-08-20T00:00:00.000Z',
          },
        ],
        integrationHealth: [
          { status: 'READY', sync_gap_count: 0 },
          { status: 'NEEDS_SYNC', sync_gap_count: 2 },
          { status: 'NEEDS_OUTLET', sync_gap_count: null },
        ],
      },
      baseDate,
    );

    expect(metrics.attachRate).toBe(50);
    expect(metrics.trialToPaidRate).toBe(50);
    expect(metrics.mrr).toBe(100000);
    expect(metrics.churnRate).toBe(50);
    expect(metrics.integrationReady).toBe(1);
    expect(metrics.integrationAttention).toBe(2);
    expect(metrics.openSyncGapCount).toBe(2);
  });

  it('returns null for rates that have no meaningful denominator', () => {
    const metrics = calculatePosBusinessMetrics({
      totalMerchants: 0,
      tenants: [],
      subscriptions: [],
      integrationHealth: [],
    });

    expect(metrics.attachRate).toBeNull();
    expect(metrics.trialToPaidRate).toBeNull();
    expect(metrics.churnRate).toBeNull();
    expect(metrics.mrr).toBe(0);
  });
});