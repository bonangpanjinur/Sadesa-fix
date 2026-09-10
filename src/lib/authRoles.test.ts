import { describe, expect, it } from 'vitest';
import { ensureBuyerFallback, mergeMerchantRole } from './authRoles';

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

  it('keeps buyer as the safe fallback for users with no roles', () => {
    expect(ensureBuyerFallback([])).toEqual(['buyer']);
    expect(ensureBuyerFallback(['merchant'])).toEqual(['merchant']);
  });
});
