import { describe, expect, it } from 'vitest';
import { isPOSModuleEnabled, isPOSOperational, isPOSSetupStatus, isPOSStatus, shouldShowPOSNavigation } from './posFeatureGate';

describe('POS feature gate', () => {
  it('only treats active and trial tenants as operational', () => {
    expect(isPOSOperational('active')).toBe(true);
    expect(isPOSOperational('trial')).toBe(true);
    expect(isPOSOperational('inactive')).toBe(false);
    expect(isPOSOperational('suspended')).toBe(false);
    expect(isPOSOperational('cancelled')).toBe(false);
  });

  it('recognizes setup states separately from suspended subscriptions', () => {
    expect(isPOSSetupStatus('inactive')).toBe(true);
    expect(isPOSSetupStatus('setup_required')).toBe(true);
    expect(isPOSSetupStatus('suspended')).toBe(false);
  });

  it('keeps POS navigation visible while a provisioned tenant needs setup', () => {
    expect(shouldShowPOSNavigation('setup_required')).toBe(true);
    expect(shouldShowPOSNavigation('trial')).toBe(true);
    expect(shouldShowPOSNavigation('active')).toBe(true);
    expect(shouldShowPOSNavigation(undefined)).toBe(false);
    expect(shouldShowPOSNavigation('suspended')).toBe(false);
  });

  it('rejects unknown status values', () => {
    expect(isPOSStatus('ACTIVE')).toBe(false);
    expect(isPOSStatus('unknown')).toBe(false);
    expect(isPOSStatus(null)).toBe(false);
  });

  it('keeps legacy tenants compatible while filtering configured modules', () => {
    expect(isPOSModuleEnabled([], 'kds')).toBe(true);
    expect(isPOSModuleEnabled(['cashier'], 'cashier')).toBe(true);
    expect(isPOSModuleEnabled(['cashier'], 'kds')).toBe(false);
    expect(isPOSModuleEnabled(['cashier'])).toBe(true);
  });
});
