interface POSHistoryViewError {
  code?: unknown;
  message?: unknown;
}

/**
 * Returns true only when the unified history view is absent from PostgreSQL or
 * the PostgREST schema cache. Permission, connectivity, and query errors must
 * remain visible instead of being disguised as an empty legacy history.
 */
export function isMissingPOSHistoryViewError(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;

  const { code, message } = error as POSHistoryViewError;
  if (code === '42P01' || code === 'PGRST205') return true;

  return typeof message === 'string'
    && /pos_unified_transaction_history/i.test(message)
    && /(does not exist|not found|could not find|schema cache)/i.test(message);
}
