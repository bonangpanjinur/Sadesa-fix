import { describe, expect, it } from 'vitest';
import { isValidKtpNumber, normalizeKtpNumber } from './identityValidation';

describe('identity validation', () => {
  it('normalizes KTP input to at most 16 digits', () => {
    expect(normalizeKtpNumber('3273-0101 1234 56789')).toBe('3273010112345678');
  });

  it('accepts only a complete 16-digit KTP number', () => {
    expect(isValidKtpNumber('3273010112345678')).toBe(true);
    expect(isValidKtpNumber('327301011234567')).toBe(false);
    expect(isValidKtpNumber('')).toBe(false);
  });
});
