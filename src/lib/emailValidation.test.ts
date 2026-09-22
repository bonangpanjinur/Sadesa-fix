import { describe, expect, it } from 'vitest';
import { normalizeEmail, signupEmailSchema } from './emailValidation';

describe('signupEmailSchema', () => {
  it('accepts a valid mailbox and normalizes it for auth', () => {
    expect(signupEmailSchema.safeParse('  User.Name@Example.COM  ').success).toBe(true);
    expect(normalizeEmail('  User.Name@Example.COM  ')).toBe('user.name@example.com');
  });

  it.each([
    'not-an-email',
    'user@localhost',
    'user@example',
    'user@.example.com',
    'user..name@example.com',
  ])('rejects malformed or non-domain email: %s', (email) => {
    expect(signupEmailSchema.safeParse(email).success).toBe(false);
  });
});
