import { describe, expect, it } from 'vitest';
import {
  CHAT_PRODUCT_POLICY,
  getRetentionDates,
  isConversationTypeAllowed,
  isValidChatBody,
} from './productPolicy';

describe('chat product policy', () => {
  it('defines the four supported two-way chat relationships', () => {
    expect(CHAT_PRODUCT_POLICY.contexts.order).toEqual([
      'buyer_merchant',
      'buyer_courier',
      'merchant_courier',
    ]);
    expect(CHAT_PRODUCT_POLICY.contexts.ride).toEqual(['passenger_courier']);
    expect(CHAT_PRODUCT_POLICY.contexts.direct).toEqual(['buyer_merchant']);
  });

  it('allows only the correct conversation type for each context', () => {
    expect(isConversationTypeAllowed('order', 'buyer_merchant')).toBe(true);
    expect(isConversationTypeAllowed('ride', 'passenger_courier')).toBe(true);
    expect(isConversationTypeAllowed('direct', 'buyer_courier')).toBe(false);
    expect(isConversationTypeAllowed('ride', 'buyer_merchant')).toBe(false);
  });

  it('enforces the 4,000-character non-empty body contract', () => {
    expect(isValidChatBody(' halo ')).toBe(true);
    expect(isValidChatBody('   ')).toBe(false);
    expect(isValidChatBody('a'.repeat(4000))).toBe(true);
    expect(isValidChatBody('a'.repeat(4001))).toBe(false);
  });

  it('calculates soft delete at day 14 and hard delete at day 30', () => {
    const createdAt = new Date('2026-09-09T00:00:00.000Z');
    const { softDeleteAt, hardDeleteAt } = getRetentionDates(createdAt);
    expect(softDeleteAt.toISOString()).toBe('2026-09-23T00:00:00.000Z');
    expect(hardDeleteAt.toISOString()).toBe('2026-10-09T00:00:00.000Z');
  });
});
