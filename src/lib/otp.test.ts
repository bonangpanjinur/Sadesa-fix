import { describe, expect, it } from 'vitest';
import { OTP_EXPIRATION_MS, createOtpExpiration, formatOtpTimeRemaining, isOtpExpired } from './otp';

describe('OTP expiration', () => {
  it('creates a ten-minute expiration deadline', () => {
    expect(createOtpExpiration(1_000)).toBe(1_000 + OTP_EXPIRATION_MS);
  });

  it('detects expiration at and after the deadline', () => {
    expect(isOtpExpired(10_000, 9_999)).toBe(false);
    expect(isOtpExpired(10_000, 10_000)).toBe(true);
    expect(isOtpExpired(10_000, 10_001)).toBe(true);
  });

  it('formats remaining time as minutes and seconds', () => {
    expect(formatOtpTimeRemaining(125_000, 5_000)).toBe('02:00');
    expect(formatOtpTimeRemaining(5_000, 10_000)).toBe('00:00');
  });
});
