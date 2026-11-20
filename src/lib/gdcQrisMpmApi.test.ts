import { beforeEach, describe, expect, it, vi } from 'vitest';

const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: { functions: { invoke } },
}));

import { createOrGetGdcQrisMpm, previewGdcQrisMpm, queryGdcQrisMpmStatus } from './gdcQrisMpmApi';

describe('GDC QRIS MPM client contract', () => {
  beforeEach(() => invoke.mockReset());

  it('requests QR creation through the authenticated server function', async () => {
    const payment = { order_id: 'order-1', status: 'PENDING', amount: 25000, currency: 'IDR', qr_content: 'emv', reference_no: 'gdc-1', paid_at: null };
    invoke.mockResolvedValue({ data: payment, error: null });
    await expect(createOrGetGdcQrisMpm('order-1')).resolves.toEqual(payment);
    expect(invoke).toHaveBeenCalledWith('gdc-qris-mpm', { body: { action: 'create', order_id: 'order-1' } });
  });

  it('queries provider status through the server function and does not accept malformed responses', async () => {
    invoke.mockResolvedValue({ data: { order_id: 'order-2', status: 'PAID', amount: 10000, currency: 'IDR', qr_content: null, reference_no: 'gdc-2', paid_at: '2026-11-01T06:00:00Z' }, error: null });
    const result = await queryGdcQrisMpmStatus('order-2');
    expect(result.status).toBe('PAID');
    expect(invoke).toHaveBeenCalledWith('gdc-qris-mpm', { body: { action: 'status', order_id: 'order-2' } });

    invoke.mockResolvedValue({ data: null, error: null });
    await expect(queryGdcQrisMpmStatus('order-2')).rejects.toThrow('Respons pembayaran QRIS tidak valid.');
  });

  it('surfaces backend errors without requiring provider secrets in the browser', async () => {
    invoke.mockResolvedValue({ data: null, error: new Error('401 Unauthorized') });
    await expect(createOrGetGdcQrisMpm('order-3')).rejects.toThrow('401 Unauthorized');
  });

  it('requests a sandbox preview by application ID and validates the fixed Rp1,000 response', async () => {
    const preview = { status: 'PREVIEW', amount: 1000, currency: 'IDR', qr_content: 'sandbox-emv', reference_no: 'sandbox-ref-1' };
    invoke.mockResolvedValue({ data: preview, error: null });
    await expect(previewGdcQrisMpm('application-1')).resolves.toEqual(preview);
    expect(invoke).toHaveBeenCalledWith('gdc-qris-mpm', { body: { action: 'admin_preview', application_id: 'application-1' } });

    invoke.mockResolvedValue({ data: { ...preview, amount: 10000 }, error: null });
    await expect(previewGdcQrisMpm('application-1')).rejects.toThrow('Respons QR uji GDC tidak valid.');
  });
});
