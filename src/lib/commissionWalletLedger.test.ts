import { describe, expect, it } from 'vitest';
import {
  COMMISSION_WALLET_LEDGER_PAGE_SIZE,
  commissionWalletLedgerCursorFilter,
  hasNextCommissionWalletLedgerPage,
} from './commissionWalletLedger';

describe('commission wallet ledger pagination', () => {
  it('uses a stable descending cursor with timestamp and id tie-breaker', () => {
    expect(commissionWalletLedgerCursorFilter({
      created_at: '2026-10-09T03:00:00.000Z',
      id: 'f8b80000-0000-4000-8000-000000000001',
    })).toBe('created_at.lt.2026-10-09T03:00:00.000Z,and(created_at.eq.2026-10-09T03:00:00.000Z,id.lt.f8b80000-0000-4000-8000-000000000001)');
  });

  it('detects more rows only when count exceeds the current page length', () => {
    expect(COMMISSION_WALLET_LEDGER_PAGE_SIZE).toBe(50);
    expect(hasNextCommissionWalletLedgerPage(51, 50)).toBe(true);
    expect(hasNextCommissionWalletLedgerPage(50, 50)).toBe(false);
    expect(hasNextCommissionWalletLedgerPage(null, 0)).toBe(false);
  });
});
