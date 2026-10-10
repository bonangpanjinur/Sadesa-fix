export interface MerchantOrderCursor {
  created_at: string;
  id: string;
}

/** PostgREST OR expression for descending (created_at, id) keyset pagination. */
export function buildMerchantOrderCursorFilter(cursor: MerchantOrderCursor): string {
  return `created_at.lt.${cursor.created_at},and(created_at.eq.${cursor.created_at},id.lt.${cursor.id})`;
}
