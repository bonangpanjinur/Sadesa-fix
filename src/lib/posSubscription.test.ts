import { describe, expect, it } from 'vitest';
import { getPOSSubscriptionState, isPOSSubscriptionActive } from './posSubscription';

const now = new Date('2026-08-28T00:00:00.000Z');

describe('POS subscription lifecycle', () => {
  it('distinguishes active and expiring subscriptions', () => {
    expect(getPOSSubscriptionState({ status: 'ACTIVE', expired_at: '2026-09-30T00:00:00.000Z' }, now)).toBe('ACTIVE');
    expect(getPOSSubscriptionState({ status: 'ACTIVE', expired_at: '2026-09-02T00:00:00.000Z' }, now)).toBe('EXPIRING_SOON');
    expect(isPOSSubscriptionActive({ status: 'ACTIVE', expired_at: '2026-09-02T00:00:00.000Z' }, now)).toBe(true);
  });

  it('does not grant access to pending, rejected, suspended, or expired subscriptions', () => {
    expect(getPOSSubscriptionState(null, now)).toBe('NO_SUBSCRIPTION');
    expect(getPOSSubscriptionState({ status: 'PENDING' }, now)).toBe('PENDING_REVIEW');
    expect(getPOSSubscriptionState({ status: 'REJECTED' }, now)).toBe('REJECTED');
    expect(getPOSSubscriptionState({ status: 'SUSPENDED' }, now)).toBe('SUSPENDED');
    expect(getPOSSubscriptionState({ status: 'ACTIVE', expired_at: '2026-08-27T23:59:59.000Z' }, now)).toBe('EXPIRED');
    expect(isPOSSubscriptionActive({ status: 'PENDING', expired_at: '2026-09-30T00:00:00.000Z' }, now)).toBe(false);
  });
});
