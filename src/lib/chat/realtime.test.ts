import { describe, expect, it } from 'vitest';
import { getChatReconnectDelay, normalizeConnectionStatus } from './realtime';

describe('chat realtime reliability', () => {
  it.each([
    ['SUBSCRIBED', 'subscribed'],
    ['CHANNEL_ERROR', 'offline'],
    ['TIMED_OUT', 'reconnecting'],
    ['CLOSED', 'closed'],
  ] as const)('normalizes %s status', (status, expected) => {
    expect(normalizeConnectionStatus(status)).toBe(expected);
  });

  it('treats unknown provider statuses as reconnecting', () => {
    expect(normalizeConnectionStatus('JOINING')).toBe('reconnecting');
  });

  it('uses bounded exponential backoff for reconnect attempts', () => {
    expect(getChatReconnectDelay(0)).toBe(1000);
    expect(getChatReconnectDelay(1)).toBe(2000);
    expect(getChatReconnectDelay(4)).toBe(15000);
    expect(getChatReconnectDelay(99)).toBe(15000);
  });
});
