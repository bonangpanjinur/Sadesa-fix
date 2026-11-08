import { describe, expect, it } from 'vitest';
import { getMerchantStorePath } from './merchantStoreLink';

describe('getMerchantStorePath', () => {
  it('uses the merchant slug for the public store URL', () => {
    expect(getMerchantStorePath({ id: 'merchant-id', slug: 'warung-sejahtera' })).toBe('/merchant/warung-sejahtera');
  });

  it('falls back to the merchant ID when no slug is available', () => {
    expect(getMerchantStorePath({ id: 'merchant-id', slug: null })).toBe('/merchant/merchant-id');
  });

  it('encodes the store identifier as a single URL path segment', () => {
    expect(getMerchantStorePath({ id: 'merchant/id', slug: 'warung satu' })).toBe('/merchant/warung%20satu');
  });
});
