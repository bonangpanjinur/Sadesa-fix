import { describe, expect, it } from 'vitest';
import { parseGdcCallbackPaymentDate, validateGdcMpmCallback } from '../../supabase/functions/_shared/gdcMpmCallback';

const payment = {
  partner_reference_no: 'order-1',
  reference_no: 'provider-1',
  external_id: 'external-1',
  amount: '12500.00',
  currency: 'IDR',
};
const validPayload = {
  originalPartnerReferenceNo: 'order-1',
  originalReferenceNo: 'provider-1',
  originalExternalId: 'external-1',
  latestTransactionStatus: '00',
  amount: { value: '12500.00', currency: 'IDR' },
};

describe('GDC QRIS MPM callback validation', () => {
  it('accepts exact references, external ID, amount, and IDR currency', () => {
    expect(validateGdcMpmCallback(validPayload, payment)).toEqual({ ok: true, paidAmount: 12500, currency: 'IDR' });
  });

  it('rejects a missing or mismatched original external ID', () => {
    expect(validateGdcMpmCallback({ ...validPayload, originalExternalId: undefined }, payment)).toMatchObject({ ok: false, reason: 'external_id_mismatch' });
    expect(validateGdcMpmCallback({ ...validPayload, originalExternalId: 'other' }, payment)).toMatchObject({ ok: false, reason: 'external_id_mismatch' });
  });

  it('allows a first provider reference to be bound only when the attempt identity matches', () => {
    expect(validateGdcMpmCallback(validPayload, { ...payment, reference_no: null })).toEqual({
      ok: true,
      paidAmount: 12500,
      currency: 'IDR',
    });
    expect(validateGdcMpmCallback({ ...validPayload, originalExternalId: 'other' }, { ...payment, reference_no: null }))
      .toMatchObject({ ok: false, reason: 'external_id_mismatch' });
  });

  it('rejects amount, currency, reference, and status mismatches', () => {
    expect(validateGdcMpmCallback({ ...validPayload, amount: { value: '12499.00', currency: 'IDR' } }, payment)).toMatchObject({ ok: false, reason: 'amount_mismatch' });
    expect(validateGdcMpmCallback({ ...validPayload, amount: { value: '12500.00', currency: 'USD' } }, payment)).toMatchObject({ ok: false, reason: 'currency_mismatch' });
    expect(validateGdcMpmCallback({ ...validPayload, originalReferenceNo: 'other' }, payment)).toMatchObject({ ok: false, reason: 'reference_mismatch' });
    expect(validateGdcMpmCallback({ ...validPayload, latestTransactionStatus: '03' }, payment)).toMatchObject({ ok: false, reason: 'unsupported_status' });
  });

  it('rejects conflicting amount fields and parses documented payment date locations', () => {
    expect(validateGdcMpmCallback({
      ...validPayload,
      paidAmount: { value: '12501.00', currency: 'IDR' },
    }, payment)).toMatchObject({ ok: false, reason: 'conflicting_amount_fields' });
    expect(parseGdcCallbackPaymentDate({ additionalInfo: { paymentDate: '2026-11-09T10:00:00+07:00' } })).toBe('2026-11-09T10:00:00+07:00');
    expect(parseGdcCallbackPaymentDate({ paidTime: 'not-a-date' })).toBeNull();
  });
});
