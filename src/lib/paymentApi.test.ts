import { describe, expect, it } from 'vitest';

import { getPaymentIdempotencyKey } from './paymentApi';

describe('getPaymentIdempotencyKey', () => {
  it('creates a deterministic key for the same order', () => {
    const orderId = '11111111-1111-4111-8111-111111111111';
    expect(getPaymentIdempotencyKey(orderId)).toBe(`payment-invoice:${orderId}`);
    expect(getPaymentIdempotencyKey(orderId)).toBe(getPaymentIdempotencyKey(orderId));
  });

  it('trims and preserves a caller-supplied key', () => {
    expect(getPaymentIdempotencyKey('order-id', '  retry-key-123456  ')).toBe('retry-key-123456');
  });

  it('falls back to the deterministic key for an empty override', () => {
    expect(getPaymentIdempotencyKey('order-id', '   ')).toBe('payment-invoice:order-id');
  });
});
