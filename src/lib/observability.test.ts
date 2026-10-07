import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  clearObservabilityEvents,
  getObservabilityEvents,
  reportObservability,
  sanitizeObservabilityText,
} from './observability';

describe('observability hardening contract', () => {
  afterEach(() => {
    clearObservabilityEvents();
    vi.restoreAllMocks();
  });

  it('redacts email, phone, and bearer material from free-form text', () => {
    expect(sanitizeObservabilityText('contact user@example.com +62 812-3456-7890 bearer abc123'))
      .toBe('contact [REDACTED_EMAIL] [REDACTED_PHONE] bearer [REDACTED]');
  });

  it('redacts sensitive context keys and caps diagnostic cardinality', () => {
    const context = Object.fromEntries([
      ['phone', '+628123456789'],
      ['address', 'Jl. Rahasia 1'],
      ...Array.from({ length: 30 }, (_, index) => [`field_${index}`, index]),
    ]);
    const event = reportObservability('security', 'test_event', 'warn', context);

    expect(event.context?.phone).toBe('[REDACTED]');
    expect(event.context?.address).toBe('[REDACTED]');
    expect(Object.keys(event.context ?? {})).toHaveLength(24);
  });

  it('preserves an explicit trace ID across lifecycle events', () => {
    const traceId = 'payment-test-trace';
    reportObservability('payment', 'request_started', 'info', undefined, undefined, { traceId });
    reportObservability('payment', 'request_failed', 'error', undefined, new Error('failed'), { traceId });

    expect(getObservabilityEvents().map((event) => event.traceId)).toEqual([traceId, traceId]);
  });
});
