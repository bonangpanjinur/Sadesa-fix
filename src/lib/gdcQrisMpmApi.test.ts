import { beforeEach, describe, expect, it, vi } from 'vitest';

const { invoke, getSession } = vi.hoisted(() => ({ invoke: vi.fn(), getSession: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: { functions: { invoke }, auth: { getSession } },
}));

import { createOrGetGdcQrisMpm, previewGdcQrisMpm, queryGdcQrisMpmStatus } from './gdcQrisMpmApi';

const authOptions = { headers: { Authorization: 'Bearer buyer-token' } };

describe('GDC QRIS MPM client contract', () => {
  beforeEach(() => {
    invoke.mockReset();
    getSession.mockReset().mockResolvedValue({ data: { session: { access_token: 'buyer-token' } }, error: null });
  });

  it('requests QR creation with the current authenticated user JWT', async () => {
    const payment = { order_id: 'order-1', status: 'PENDING', amount: 25000, currency: 'IDR', qr_content: 'emv', reference_no: 'gdc-1', paid_at: null };
    invoke.mockResolvedValue({ data: payment, error: null });
    await expect(createOrGetGdcQrisMpm('order-1')).resolves.toEqual(payment);
    expect(invoke).toHaveBeenCalledWith('gdc-qris-mpm', {
      body: { action: 'create', order_id: 'order-1' },
      ...authOptions,
    });
  });

  it('does not invoke a payment action if there is no authenticated session', async () => {
    getSession.mockResolvedValue({ data: { session: null }, error: null });
    await expect(createOrGetGdcQrisMpm('order-1')).rejects.toThrow(
      'Sesi login tidak ditemukan. Silakan masuk kembali lalu coba lagi.',
    );
    expect(invoke).not.toHaveBeenCalled();
  });

  it('queries provider status through the server function and does not accept malformed responses', async () => {
    invoke.mockResolvedValue({ data: { order_id: 'order-2', status: 'PAID', amount: 10000, currency: 'IDR', qr_content: null, reference_no: 'gdc-2', paid_at: '2026-11-01T06:00:00Z' }, error: null });
    const result = await queryGdcQrisMpmStatus('order-2');
    expect(result.status).toBe('PAID');
    expect(invoke).toHaveBeenCalledWith('gdc-qris-mpm', {
      body: { action: 'status', order_id: 'order-2' },
      ...authOptions,
    });

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
    expect(invoke).toHaveBeenCalledWith('gdc-qris-mpm', {
      body: { action: 'admin_preview', application_id: 'application-1' },
      ...authOptions,
    });

    invoke.mockResolvedValue({ data: { ...preview, amount: 10000 }, error: null });
    await expect(previewGdcQrisMpm('application-1')).rejects.toThrow('Respons QR uji GDC tidak valid.');
  });

  it('shows the QRIS Edge Function JSON error instead of the generic non-2xx message', async () => {
    invoke.mockResolvedValue({
      data: null,
      error: Object.assign(new Error('Edge Function returned a non-2xx status code'), {
        context: new Response(JSON.stringify({ error: 'Sesi login tidak ditemukan. Silakan masuk kembali lalu coba lagi.' }), { status: 401 }),
      }),
    });
    await expect(createOrGetGdcQrisMpm('order-1')).rejects.toThrow(
      'Sesi login tidak ditemukan. Silakan masuk kembali lalu coba lagi.',
    );
  });

  it('shows sandbox preview JSON errors returned by the Edge Function', async () => {
    invoke.mockResolvedValue({
      data: null,
      error: Object.assign(new Error('Edge Function returned a non-2xx status code'), {
        context: new Response(JSON.stringify({ error: 'Preview QRIS hanya diizinkan pada endpoint sandbox GDC.' }), { status: 409 }),
      }),
    });
    await expect(previewGdcQrisMpm('application-1')).rejects.toThrow('Preview QRIS hanya diizinkan pada endpoint sandbox GDC.');
  });
});
