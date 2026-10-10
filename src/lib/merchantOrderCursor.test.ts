import { describe, expect, it } from 'vitest';
import { buildMerchantOrderCursorFilter } from './merchantOrderCursor';

describe('merchant order cursor pagination', () => {
  it('uses timestamp and id as a stable descending cursor', () => {
    expect(buildMerchantOrderCursorFilter({
      created_at: '2026-10-10T10:15:30.123+00:00',
      id: '12345678-1234-1234-1234-123456789abc',
    })).toBe('created_at.lt.2026-10-10T10:15:30.123+00:00,and(created_at.eq.2026-10-10T10:15:30.123+00:00,id.lt.12345678-1234-1234-1234-123456789abc)');
  });
});
