import { describe, expect, it } from 'vitest';
import { evaluatePilotReadiness } from './pilotReadiness';

describe('pilotReadiness', () => {
  it('requires profile, listing, order, and fulfillment for marketplace-only merchants', () => {
    const result = evaluatePilotReadiness('marketplace_only', {
      merchantProfileComplete: true,
      publishedListingCount: 1,
      completedOrderCount: 1,
      completedFulfillmentCount: 0,
      posSetupComplete: false,
      completedPosTransactionCount: 0,
    });

    expect(result.readyForPilot).toBe(false);
    expect(result.nextMilestone).toBe('first_fulfillment');
    expect(result.milestones).toHaveLength(4);
  });

  it('requires POS setup and a completed POS transaction for POS merchants', () => {
    const result = evaluatePilotReadiness('pos', {
      merchantProfileComplete: true,
      publishedListingCount: 2,
      completedOrderCount: 1,
      completedFulfillmentCount: 1,
      posSetupComplete: true,
      completedPosTransactionCount: 1,
    });

    expect(result.readyForPilot).toBe(true);
    expect(result.activationComplete).toBe(true);
    expect(result.nextMilestone).toBeNull();
    expect(result.milestones).toHaveLength(6);
  });

  it('normalizes invalid counts without allowing false activation', () => {
    const result = evaluatePilotReadiness('pos', {
      merchantProfileComplete: true,
      publishedListingCount: Number.NaN,
      completedOrderCount: -1,
      completedFulfillmentCount: Number.POSITIVE_INFINITY,
      posSetupComplete: true,
      completedPosTransactionCount: 0,
    });

    expect(result.readyForPilot).toBe(false);
    expect(result.nextMilestone).toBe('first_listing');
  });
});
