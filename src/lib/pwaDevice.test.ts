import { describe, expect, it } from 'vitest';
import { allowsPwaDeviceRegistration, canRegisterPwaDeviceForSession, shouldForcePwaDeviceLogout } from './pwaDevice';

describe('canRegisterPwaDeviceForSession', () => {
  const ready = {
    userId: 'user-1',
    tenantId: 'tenant-1',
    posRole: 'owner',
    posEnabled: true,
    posLoading: false,
    posRoleLoading: false,
  };

  it('allows an authenticated POS member after the tenant and role have loaded', () => {
    expect(canRegisterPwaDeviceForSession(ready)).toBe(true);
  });

  it.each([
    ['missing user', { ...ready, userId: null }],
    ['missing tenant', { ...ready, tenantId: null }],
    ['missing POS role', { ...ready, posRole: null }],
    ['disabled POS tenant', { ...ready, posEnabled: false }],
    ['tenant still loading', { ...ready, posLoading: true }],
    ['POS role still loading', { ...ready, posRoleLoading: true }],
  ])('does not register while %s', (_label, scope) => {
    expect(canRegisterPwaDeviceForSession(scope)).toBe(false);
  });
});

describe('allowsPwaDeviceRegistration', () => {
  it('keeps the backend one-device default when there is no active subscription', () => {
    expect(allowsPwaDeviceRegistration({ enabled: false, source: 'none', limit_value: 0 })).toBe(true);
  });

  it('allows an explicitly enabled POS-device entitlement', () => {
    expect(allowsPwaDeviceRegistration({ enabled: true, subscription_id: 'subscription-1' })).toBe(true);
  });

  it('skips registration when an active subscription excludes POS devices', () => {
    expect(allowsPwaDeviceRegistration({ enabled: false, subscription_id: 'subscription-1' })).toBe(false);
  });

  it('fails closed for an unknown entitlement payload', () => {
    expect(allowsPwaDeviceRegistration(null)).toBe(false);
    expect(allowsPwaDeviceRegistration({ enabled: false })).toBe(false);
  });
});

describe('shouldForcePwaDeviceLogout', () => {
  it('forces a device out after an admin revokes its session', () => {
    expect(shouldForcePwaDeviceLogout('revoked')).toBe(true);
    expect(shouldForcePwaDeviceLogout('active')).toBe(false);
    expect(shouldForcePwaDeviceLogout('idle')).toBe(false);
  });
});
