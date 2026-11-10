export interface GdcMpmLedgerReference {
  partner_reference_no: string;
  reference_no: string | null;
  external_id: string;
  amount: number | string;
  currency: string;
}

export interface GdcMpmCallbackPayload {
  originalPartnerReferenceNo?: unknown;
  originalReferenceNo?: unknown;
  originalExternalId?: unknown;
  latestTransactionStatus?: unknown;
  amount?: unknown;
  paidAmount?: unknown;
}

function parseAmountCents(value: unknown): number | null {
  if (typeof value !== 'string' && typeof value !== 'number') return null;
  if (typeof value === 'string' && !/^\d+(?:\.\d{1,2})?$/.test(value)) return null;
  const amount = Number(value);
  if (!Number.isFinite(amount) || amount <= 0) return null;
  const cents = Math.round(amount * 100);
  return Number.isSafeInteger(cents) ? cents : null;
}

function parseAmountObject(value: unknown): { cents: number; currency: string } | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const amount = value as { value?: unknown; currency?: unknown };
  const cents = parseAmountCents(amount.value);
  if (cents === null || typeof amount.currency !== 'string') return null;
  return { cents, currency: amount.currency };
}

function ledgerAmountCents(value: number | string): number | null {
  const amount = Number(value);
  if (!Number.isFinite(amount) || amount <= 0) return null;
  const cents = Math.round(amount * 100);
  return Number.isSafeInteger(cents) ? cents : null;
}

export function validateGdcMpmCallback(
  payload: GdcMpmCallbackPayload,
  payment: GdcMpmLedgerReference,
): { ok: true; paidAmount: number; currency: 'IDR' } | { ok: false; reason: string } {
  if (payload.latestTransactionStatus !== '00' && payload.latestTransactionStatus !== '06') {
    return { ok: false, reason: 'unsupported_status' };
  }
  if (payload.originalPartnerReferenceNo !== payment.partner_reference_no) {
    return { ok: false, reason: 'partner_reference_mismatch' };
  }
  if (typeof payload.originalReferenceNo !== 'string'
    || !payload.originalReferenceNo.trim()
    || (payment.reference_no !== null && payload.originalReferenceNo !== payment.reference_no)) {
    return { ok: false, reason: 'reference_mismatch' };
  }
  if (typeof payload.originalExternalId !== 'string' || payload.originalExternalId !== payment.external_id) {
    return { ok: false, reason: 'external_id_mismatch' };
  }

  const amountObjects = [payload.amount, payload.paidAmount]
    .filter((value) => value !== undefined && value !== null)
    .map(parseAmountObject);
  if (amountObjects.length === 0 || amountObjects.some((value) => value === null)) {
    return { ok: false, reason: 'invalid_amount' };
  }
  const normalizedAmounts = amountObjects as Array<{ cents: number; currency: string }>;
  if (normalizedAmounts.some((value) => value.currency !== 'IDR') || payment.currency !== 'IDR') {
    return { ok: false, reason: 'currency_mismatch' };
  }
  if (normalizedAmounts.some((value) => value.cents !== normalizedAmounts[0].cents)) {
    return { ok: false, reason: 'conflicting_amount_fields' };
  }
  const expectedCents = ledgerAmountCents(payment.amount);
  if (expectedCents === null || normalizedAmounts[0].cents !== expectedCents) {
    return { ok: false, reason: 'amount_mismatch' };
  }
  return { ok: true, paidAmount: normalizedAmounts[0].cents / 100, currency: 'IDR' };
}

export function parseGdcCallbackPaymentDate(payload: Record<string, unknown>): string | null {
  const additionalInfo = payload.additionalInfo && typeof payload.additionalInfo === 'object'
    ? payload.additionalInfo as Record<string, unknown>
    : {};
  const value = payload.paidTime ?? payload.paymentDate ?? additionalInfo.paymentDate;
  if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) return null;
  return value;
}
