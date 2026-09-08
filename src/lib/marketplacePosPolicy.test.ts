import { describe, expect, it } from 'vitest';
import {
  canOperatePOS,
  canUseTableQr,
  isMarketplaceAvailable,
  MARKETPLACE_POS_POLICY,
} from './marketplacePosPolicy';

describe('marketplace/POS product policy', () => {
  it('keeps marketplace access independent from POS entitlement', () => {
    expect(isMarketplaceAvailable()).toBe(true);
    expect(MARKETPLACE_POS_POLICY.marketplace.requiresPOS).toBe(false);
    expect(MARKETPLACE_POS_POLICY.marketplace.remainsAvailableWhenPOSIsSuspended).toBe(true);
  });

  it('only allows POS operations for operational tenant statuses', () => {
    expect(canOperatePOS('trial')).toBe(true);
    expect(canOperatePOS('active')).toBe(true);
    expect(canOperatePOS('grace')).toBe(true);
    expect(canOperatePOS('suspended')).toBe(false);
    expect(canOperatePOS('cancelled')).toBe(false);
  });

  it('requires both operational POS and an active table context for QR ordering', () => {
    expect(canUseTableQr('active', true)).toBe(true);
    expect(canUseTableQr('active', false)).toBe(false);
    expect(canUseTableQr('suspended', true)).toBe(false);
  });
});