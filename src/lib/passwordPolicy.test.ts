import { describe, expect, it } from 'vitest';
import { passwordSchema, resetPasswordSchema } from './validationSchemas';

describe('shared account password policy', () => {
  it('accepts a compliant password for both profile settings and reset flows', () => {
    const password = 'SecurePass123';
    expect(passwordSchema.safeParse(password).success).toBe(true);
    expect(resetPasswordSchema.safeParse({ password, confirmPassword: password }).success).toBe(true);
  });

  it.each(['password123', 'PASSWORD123', 'SecurePassword', 'Short1'])('rejects a password that misses a shared policy requirement: %s', (password) => {
    expect(passwordSchema.safeParse(password).success).toBe(false);
    expect(resetPasswordSchema.safeParse({ password, confirmPassword: password }).success).toBe(false);
  });

  it('requires matching confirmation when resetting a password', () => {
    const result = resetPasswordSchema.safeParse({
      password: 'SecurePass123',
      confirmPassword: 'DifferentPass123',
    });
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues.some((issue) => issue.path[0] === 'confirmPassword')).toBe(true);
    }
  });
});
