import { beforeEach, describe, expect, it } from 'vitest';
import {
  getGuestCheckoutSessionKey,
  getGuestOrderAccess,
  guestOrderUrl,
  rememberGuestOrderAccess,
} from './guestCheckout';

describe('guest checkout access', () => {
  beforeEach(() => {
    sessionStorage.clear();
    localStorage.clear();
  });

  it('keeps checkout session and token access in sessionStorage only', () => {
    const sessionKey = getGuestCheckoutSessionKey();
    expect(sessionKey).toHaveLength(36);
    expect(sessionStorage.getItem('sadesa_guest_checkout_session')).toBe(sessionKey);
    expect(localStorage.getItem('sadesa_guest_checkout_session')).toBeNull();

    const access = { orderIds: ['order-a'], token: 'token-a-1234567890', expiresAt: new Date(Date.now() + 86_400_000).toISOString() };
    rememberGuestOrderAccess(access);
    expect(getGuestOrderAccess('order-a')?.token).toBe(access.token);
    expect(localStorage.getItem('sadesa_guest_order_access')).toBeNull();
  });

  it('drops expired access and never matches another order', () => {
    rememberGuestOrderAccess({ orderIds: ['order-a'], token: 'valid-token-123456', expiresAt: new Date(Date.now() + 60_000).toISOString() });
    rememberGuestOrderAccess({ orderIds: ['order-expired'], token: 'expired-token-123456', expiresAt: new Date(Date.now() - 60_000).toISOString() });
    expect(getGuestOrderAccess('order-a')?.token).toBe('valid-token-123456');
    expect(getGuestOrderAccess('order-b')).toBeNull();
    expect(getGuestOrderAccess('order-expired')).toBeNull();
  });

  it('requires the matching order and token when a URL token is supplied', () => {
    rememberGuestOrderAccess({ orderIds: ['order-a'], token: 'valid-token-123456', expiresAt: new Date(Date.now() + 60_000).toISOString() });
    expect(getGuestOrderAccess('order-a', 'wrong-token-123456')).toBeNull();
    expect(guestOrderUrl('order-a', 'valid-token-123456')).toBe('/guest-orders/order-a?guest_token=valid-token-123456');
  });
});
