import { describe, expect, it } from 'vitest';
import { normalizeConnectionStatus } from './realtime';

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
});
