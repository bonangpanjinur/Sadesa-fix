import { beforeEach, describe, expect, it } from 'vitest';
import { checkPersistentRateLimit } from './rateLimit';

describe('checkPersistentRateLimit', () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it('allows configured requests and blocks the next one', () => {
    const config = { maxRequests: 2, windowMs: 60_000 };
    const identifier = `otp-${Date.now()}`;

    expect(checkPersistentRateLimit(identifier, 'signupOtp', config).allowed).toBe(true);
    expect(checkPersistentRateLimit(identifier, 'signupOtp', config).allowed).toBe(true);
    const blocked = checkPersistentRateLimit(identifier, 'signupOtp', config);

    expect(blocked.allowed).toBe(false);
    expect(blocked.remaining).toBe(0);
    expect(blocked.resetIn).toBeGreaterThan(0);
  });

  it('keeps separate limits for separate actions', () => {
    const config = { maxRequests: 1, windowMs: 60_000 };
    const identifier = `otp-${Date.now()}`;

    expect(checkPersistentRateLimit(identifier, 'signupOtp', config).allowed).toBe(true);
    expect(checkPersistentRateLimit(identifier, 'resendOtp', config).allowed).toBe(true);
    expect(checkPersistentRateLimit(identifier, 'signupOtp', config).allowed).toBe(false);
  });
});
