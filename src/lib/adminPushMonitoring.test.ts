import { describe, expect, it } from 'vitest';
import { calculatePushDeliveryKpis } from './adminPushMonitoring';

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
