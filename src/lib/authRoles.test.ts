import { describe, expect, it } from 'vitest';
import { ensureBuyerFallback, mergeCourierRole, mergeMerchantRole, shouldFetchRolesForAuthEvent } from './authRoles';
import { canAccessPath, getRedirectPathForRoles } from '@/types/auth';

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

  it('keeps the profile alias available to authenticated buyers', () => {
    expect(canAccessPath(['buyer'], '/profile')).toBe(true);
  });

  it('skips redundant role recovery when the same user only refreshes an access token', () => {
    expect(shouldFetchRolesForAuthEvent('TOKEN_REFRESHED', 'user-1', 'user-1')).toBe(false);
  });

  it('still loads roles for initial sessions, sign-ins, and a different refreshed user', () => {
    expect(shouldFetchRolesForAuthEvent('INITIAL_SESSION', null, 'user-1')).toBe(true);
    expect(shouldFetchRolesForAuthEvent('SIGNED_IN', 'user-1', 'user-1')).toBe(true);
    expect(shouldFetchRolesForAuthEvent('TOKEN_REFRESHED', 'user-1', 'user-2')).toBe(true);
  });

  it('does not load roles when an auth event has no session user', () => {
    expect(shouldFetchRolesForAuthEvent('SIGNED_OUT', 'user-1', null)).toBe(false);
  });
});
