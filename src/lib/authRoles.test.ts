import { describe, expect, it } from 'vitest';
import { ensureBuyerFallback, mergeCourierRole, mergeMerchantRole } from './authRoles';
import { getRedirectPathForRoles } from '@/types/auth';

describe('frontend role recovery', () => {
  it('adds merchant capability when the user owns a merchant profile', () => {
    expect(mergeMerchantRole(['admin', 'courier'], true)).toEqual([
      'admin',
      'courier',
      'merchant',
    ]);
  });

  it('does not grant merchant capability without a merchant profile', () => {
    expect(mergeMerchantRole(['admin', 'courier'], false)).toEqual(['admin', 'courier']);
  });

  it('does not duplicate an existing merchant role', () => {
    expect(mergeMerchantRole(['merchant'], true)).toEqual(['merchant']);
  });

  it('recovers courier capability when a courier profile exists', () => {
    expect(mergeCourierRole(['buyer'], true)).toEqual(['buyer', 'courier']);
  });

  it('keeps buyer as the safe fallback for users with no roles', () => {
    expect(ensureBuyerFallback([])).toEqual(['buyer']);
    expect(ensureBuyerFallback(['merchant'])).toEqual(['merchant', 'buyer']);
    expect(ensureBuyerFallback(['courier'])).toEqual(['courier', 'buyer']);
    expect(ensureBuyerFallback(['service_provider'])).toEqual(['service_provider', 'buyer']);
    expect(ensureBuyerFallback(['merchant', 'buyer'])).toEqual(['merchant', 'buyer']);
  });

  it('sends merchant and courier roles to their dashboards on app entry', () => {
    expect(getRedirectPathForRoles(['merchant', 'buyer'])).toBe('/merchant');
    expect(getRedirectPathForRoles(['courier', 'buyer'])).toBe('/courier');
  });
});
