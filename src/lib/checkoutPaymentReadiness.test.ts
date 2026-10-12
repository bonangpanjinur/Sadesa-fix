import { describe, expect, it } from 'vitest';
import { isCheckoutPaymentMethodAvailable, isCheckoutPaymentSettingsReady } from './checkoutPaymentReadiness';

describe('isCheckoutPaymentSettingsReady', () => {
  it('requires successful settings for the current merchant', () => {
    expect(isCheckoutPaymentSettingsReady('ready', 'merchant-1', 'merchant-1')).toBe(true);
    expect(isCheckoutPaymentSettingsReady('loading', 'merchant-1', 'merchant-1')).toBe(false);
    expect(isCheckoutPaymentSettingsReady('error', 'merchant-1', 'merchant-1')).toBe(false);
    expect(isCheckoutPaymentSettingsReady('ready', 'merchant-1', 'merchant-2')).toBe(false);
    expect(isCheckoutPaymentSettingsReady('ready', 'merchant-1', undefined)).toBe(false);
  });
});

describe('isCheckoutPaymentMethodAvailable', () => {
  it('allows an enabled bank-transfer method even when account details need seller follow-up', () => {
    expect(isCheckoutPaymentMethodAvailable('TRANSFER', true, false)).toBe(true);
  });

  it('blocks transfer when the merchant has disabled it', () => {
    expect(isCheckoutPaymentMethodAvailable('TRANSFER', false, true)).toBe(false);
  });

  it('allows online payment only for an authenticated buyer with an available provider', () => {
    expect(isCheckoutPaymentMethodAvailable('ONLINE', true, true)).toBe(true);
    expect(isCheckoutPaymentMethodAvailable('ONLINE', true, false)).toBe(false);
  });
});
