import { describe, expect, it } from 'vitest';
import { isMissingPOSHistoryViewError } from './posTransactionHistory';

describe('isMissingPOSHistoryViewError', () => {
  it('recognizes a missing relation and a stale PostgREST schema cache', () => {
    expect(isMissingPOSHistoryViewError({ code: '42P01', message: 'relation does not exist' })).toBe(true);
    expect(isMissingPOSHistoryViewError({
      code: 'PGRST205',
      message: "Could not find the table 'public.pos_unified_transaction_history' in the schema cache",
    })).toBe(true);
  });

  it('does not turn permission, connection, or unrelated schema failures into a partial success', () => {
    expect(isMissingPOSHistoryViewError({ code: '42501', message: 'permission denied' })).toBe(false);
    expect(isMissingPOSHistoryViewError({ code: 'PGRST204', message: 'column not found' })).toBe(false);
    expect(isMissingPOSHistoryViewError(new Error('network unavailable'))).toBe(false);
    expect(isMissingPOSHistoryViewError(null)).toBe(false);
  });
});
