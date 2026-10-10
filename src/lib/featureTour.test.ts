import { describe, expect, it } from 'vitest';
import {
  FEATURE_TOUR_STEPS,
  PUBLIC_BUYER_FEATURE_TOUR_STEPS,
  getFeatureTourRole,
  getFeatureTourRoleForVisitor,
  getFeatureTourStorageKey,
  getFirstUnseenFeatureTip,
  markFeatureTipSeen,
  readSeenFeatureTips,
  shouldAutoStartFeatureTour,
} from './featureTour';

describe('feature tour targeting and progress', () => {
  it('shows the relevant guide only in buyer, merchant, or courier workspaces', () => {
    expect(getFeatureTourRole(['buyer'], '/')).toBe('buyer');
    expect(getFeatureTourRole(['buyer', 'merchant'], '/merchant/orders')).toBe('merchant');
    expect(getFeatureTourRole(['buyer', 'courier'], '/courier/rides')).toBe('courier');
    expect(getFeatureTourRole(['buyer'], '/merchant/orders')).toBeNull();
    expect(getFeatureTourRole(['buyer'], '/courier/rides')).toBeNull();
    expect(getFeatureTourRole(['buyer'], '/merchant/toko-lokal')).toBe('buyer');
    expect(getFeatureTourRole(['buyer'], '/checkout')).toBeNull();
    expect(getFeatureTourRole(['buyer'], '/auth')).toBeNull();
  });

  it('never shows a customer guide to admin or internal staff', () => {
    expect(getFeatureTourRole(['admin', 'buyer'], '/')).toBeNull();
    expect(getFeatureTourRole(['admin_desa', 'buyer'], '/')).toBeNull();
    expect(getFeatureTourRole(['verifikator', 'buyer'], '/')).toBeNull();
  });

  it('keeps subscription journeys separated after retiring the merchant quota page', () => {
    expect(getFeatureTourRole(['merchant'], '/merchant/wallet')).toBe('merchant');
    expect(getFeatureTourRole(['merchant'], '/merchant/subscription')).toBeNull();
    expect(getFeatureTourRole(['buyer'], '/langganan')).toBe('buyer');
  });

  it('shows the buyer guide to signed-out visitors on public pages, but not role workspaces', () => {
    expect(getFeatureTourRoleForVisitor([], '/', false)).toBe('buyer');
    expect(getFeatureTourRoleForVisitor([], '/products', false)).toBe('buyer');
    expect(getFeatureTourRoleForVisitor([], '/merchant/orders', false)).toBeNull();
    expect(getFeatureTourRoleForVisitor([], '/courier', false)).toBeNull();
    expect(getFeatureTourRoleForVisitor([], '/auth', false)).toBeNull();
    expect(getFeatureTourRoleForVisitor([], '/orders', false)).toBeNull();
    expect(getFeatureTourRoleForVisitor([], '/account', false)).toBeNull();
    expect(getFeatureTourRoleForVisitor([], '/', true)).toBeNull();
  });

  it('anchors every step to a feature and keeps the guest guide on public destinations', () => {
    for (const step of Object.values(FEATURE_TOUR_STEPS).flat()) {
      expect(step.target).toBeTruthy();
      expect(step.href.startsWith('/')).toBe(true);
    }
    expect(PUBLIC_BUYER_FEATURE_TOUR_STEPS.map((step) => step.id)).not.toContain('orders');
    expect(PUBLIC_BUYER_FEATURE_TOUR_STEPS.map((step) => step.id)).not.toContain('account-support');
  });

  it('keeps progress isolated by account and role', () => {
    expect(getFeatureTourStorageKey('user-a', 'buyer')).not.toBe(getFeatureTourStorageKey('user-a', 'merchant'));
    expect(getFeatureTourStorageKey('user-a', 'buyer')).not.toBe(getFeatureTourStorageKey('user-b', 'buyer'));
  });

  it('starts automatically only before the first tip has been displayed', () => {
    const values = new Map<string, string>();
    const storage = {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => { values.set(key, value); },
    };
    const key = getFeatureTourStorageKey('user-a', 'buyer');
    const steps = FEATURE_TOUR_STEPS.buyer;

    expect(shouldAutoStartFeatureTour(storage, key)).toBe(true);
    expect(getFirstUnseenFeatureTip(steps, [])?.id).toBe('discover');
    const seen = markFeatureTipSeen(storage, key, 'discover');
    expect(seen).toEqual(['discover']);
    expect(shouldAutoStartFeatureTour(storage, key)).toBe(false);
    expect(getFirstUnseenFeatureTip(steps, readSeenFeatureTips(storage, key))?.id).toBe('checkout');
    expect(markFeatureTipSeen(storage, key, 'discover')).toEqual(['discover']);
  });
});
