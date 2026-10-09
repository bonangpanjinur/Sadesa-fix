import { describe, expect, it } from 'vitest';
import {
  FEATURE_TOUR_STEPS,
  getFeatureTourRole,
  getFeatureTourRoleForVisitor,
  getFeatureTourStorageKey,
  getFirstUnseenFeatureTip,
  markFeatureTipSeen,
  readSeenFeatureTips,
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

  it('shows the buyer guide to signed-out visitors on public pages, but not role workspaces', () => {
    expect(getFeatureTourRoleForVisitor([], '/', false)).toBe('buyer');
    expect(getFeatureTourRoleForVisitor([], '/products', false)).toBe('buyer');
    expect(getFeatureTourRoleForVisitor([], '/merchant/orders', false)).toBeNull();
    expect(getFeatureTourRoleForVisitor([], '/courier', false)).toBeNull();
    expect(getFeatureTourRoleForVisitor([], '/auth', false)).toBeNull();
    expect(getFeatureTourRoleForVisitor([], '/', true)).toBeNull();
  });

  it('keeps progress isolated by account and role', () => {
    expect(getFeatureTourStorageKey('user-a', 'buyer')).not.toBe(getFeatureTourStorageKey('user-a', 'merchant'));
    expect(getFeatureTourStorageKey('user-a', 'buyer')).not.toBe(getFeatureTourStorageKey('user-b', 'buyer'));
  });

  it('marks only the displayed tip and resumes at the first unseen feature', () => {
    const values = new Map<string, string>();
    const storage = {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => { values.set(key, value); },
    };
    const key = getFeatureTourStorageKey('user-a', 'buyer');
    const steps = FEATURE_TOUR_STEPS.buyer;

    expect(getFirstUnseenFeatureTip(steps, [])?.id).toBe('discover');
    const seen = markFeatureTipSeen(storage, key, 'discover');
    expect(seen).toEqual(['discover']);
    expect(getFirstUnseenFeatureTip(steps, readSeenFeatureTips(storage, key))?.id).toBe('checkout');
    expect(markFeatureTipSeen(storage, key, 'discover')).toEqual(['discover']);
  });
});
