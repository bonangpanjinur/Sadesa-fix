import { describe, expect, it } from 'vitest';
import { buildPushDeliveryHourlyTrend, calculatePushDeliveryKpis } from './adminPushMonitoring';

describe('calculatePushDeliveryKpis', () => {
  it('calculates accepted-provider rate and combines failed and expired attempts', () => {
    expect(calculatePushDeliveryKpis({ total: 100, sent: 76, failed: 18, expired: 6 })).toEqual({
      successRate: 76,
      issueCount: 24,
    });
  });

  it('returns a zero rate without division by zero when no attempts exist', () => {
    expect(calculatePushDeliveryKpis({ total: 0, sent: 0, failed: 0, expired: 0 })).toEqual({
      successRate: 0,
      issueCount: 0,
    });
  });
});

describe('buildPushDeliveryHourlyTrend', () => {
  it('fills quiet hours and groups sent, failed, and expired attempts into UTC hour buckets', () => {
    const trend = buildPushDeliveryHourlyTrend([
      { hour_bucket: '2026-10-15T13:00:00.000Z', status: 'sent', attempt_count: 7 },
      { hour_bucket: '2026-10-15T13:00:00.000Z', status: 'failed', attempt_count: '2' },
      { hour_bucket: '2026-10-15T14:00:00.000Z', status: 'expired', attempt_count: 1 },
      { hour_bucket: '2026-10-15T14:00:00.000Z', status: 'unknown', attempt_count: 20 },
    ], new Date('2026-10-15T12:24:00.000Z'), new Date('2026-10-15T14:35:00.000Z'));

    expect(trend).toEqual([
      { hour: '2026-10-15T12:00:00.000Z', sent: 0, failed: 0, expired: 0 },
      { hour: '2026-10-15T13:00:00.000Z', sent: 7, failed: 2, expired: 0 },
      { hour: '2026-10-15T14:00:00.000Z', sent: 0, failed: 0, expired: 1 },
    ]);
  });

  it('returns no buckets for an invalid or reversed range', () => {
    expect(buildPushDeliveryHourlyTrend([], new Date('invalid'), new Date())).toEqual([]);
    expect(buildPushDeliveryHourlyTrend([], new Date('2026-10-15T15:00:00Z'), new Date('2026-10-15T14:00:00Z'))).toEqual([]);
  });
});
