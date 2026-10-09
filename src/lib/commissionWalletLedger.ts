export const COMMISSION_WALLET_LEDGER_PAGE_SIZE = 50;

export interface CommissionWalletLedgerCursor {
  created_at: string;
  id: string;
}

/** PostgREST disjunction for the next descending page with deterministic tie-breaking. */
export function commissionWalletLedgerCursorFilter(cursor: CommissionWalletLedgerCursor): string {
  return `created_at.lt.${cursor.created_at},and(created_at.eq.${cursor.created_at},id.lt.${cursor.id})`;
}

export function hasNextCommissionWalletLedgerPage(remainingCount: number | null, pageLength: number): boolean {
  return Number(remainingCount ?? 0) > pageLength;
}
