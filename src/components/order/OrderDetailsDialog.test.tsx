import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const mocks = vi.hoisted(() => ({
  getPaymentProofSignedUrl: vi.fn(),
  rpc: vi.fn(),
  onVerifyPayment: vi.fn().mockResolvedValue(true),
  onRejectPayment: vi.fn().mockResolvedValue(true),
  toast: { success: vi.fn(), error: vi.fn() },
}));

vi.mock('@/lib/paymentProof', () => ({
  getPaymentProofSignedUrl: mocks.getPaymentProofSignedUrl,
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: vi.fn(),
    rpc: mocks.rpc,
  },
}));

vi.mock('sonner', () => ({ toast: mocks.toast }));

import { OrderDetailsDialog } from './OrderDetailsDialog';

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.clearAllMocks();
});

const order = {
  id: '665f3cb3-1234-4567-8901-123456789abc',
  status: 'DONE',
  payment_status: 'PAID',
  payment_method: 'TRANSFER',
  payment_proof_url: 'orders/665f3cb3-1234-4567-8901-123456789abc/buyer/proof.jpg',
  delivery_type: 'PICKUP',
  delivery_name: 'Pembeli',
  delivery_phone: '08123456789',
  delivery_address: null,
  subtotal: 40000,
  shipping_cost: 0,
  total: 40000,
  cod_service_fee: null,
  notes: null,
  created_at: '2026-10-06T09:00:00.000Z',
  courier_id: null,
  merchants: { name: 'Toko Uji' },
  is_self_delivery: false,
};

const orderItems = [{ id: 'item-1', product_name: 'Mie ayam Pangsit', quantity: 4, product_price: 10000, subtotal: 40000 }];

function renderOrderDetails(items = orderItems, orderOverride: Partial<typeof order> = {}) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queryClient}>
      <OrderDetailsDialog
        open
        onOpenChange={vi.fn()}
        order={{ ...order, ...orderOverride }}
        orderItems={items}
        onUpdateStatus={vi.fn()}
        onOpenAssignCourier={vi.fn()}
        getStatusBadge={() => <span>Selesai</span>}
        getPaymentBadge={() => <span>Lunas</span>}
        onVerifyPayment={mocks.onVerifyPayment}
        onRejectPayment={mocks.onRejectPayment}
      />
    </QueryClientProvider>,
  );
}

describe('OrderDetailsDialog payment proof', () => {
  it('shows the buyer-uploaded proof using a signed storage URL', async () => {
    mocks.getPaymentProofSignedUrl.mockResolvedValue('https://storage.example/signed-proof.jpg');
    renderOrderDetails([]);

    const proofImage = await screen.findByRole('img', { name: 'Bukti pembayaran yang diunggah pembeli' });
    expect(proofImage).toHaveAttribute('src', 'https://storage.example/signed-proof.jpg');
    expect(mocks.getPaymentProofSignedUrl).toHaveBeenCalledWith(order.payment_proof_url);
  });

  it('shares an order summary without exposing delivery contact details', async () => {
    const share = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, 'share', { configurable: true, value: share });
    renderOrderDetails();

    fireEvent.click(screen.getByRole('button', { name: 'Bagikan' }));

    await waitFor(() => expect(share).toHaveBeenCalledOnce());
    expect(share).toHaveBeenCalledWith(expect.objectContaining({
      title: 'Detail Pesanan #665F3CB3',
      text: expect.stringContaining('Mie ayam Pangsit × 4'),
    }));
    expect(share.mock.calls[0][0].text).toMatch(/Total: Rp[\s\u00a0]?40\.000/);
    expect(share.mock.calls[0][0].text).not.toContain('08123456789');
  });

  it('copies the order summary when native sharing is unavailable', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, 'share', { configurable: true, value: undefined });
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText } });
    renderOrderDetails();

    fireEvent.click(screen.getByRole('button', { name: 'Bagikan' }));

    await waitFor(() => expect(writeText).toHaveBeenCalledOnce());
    expect(writeText.mock.calls[0][0]).toContain('Detail Pesanan #665F3CB3');
    expect(mocks.toast.success).toHaveBeenCalledWith('Detail pesanan disalin. Silakan tempel untuk membagikannya.');
  });

  it('downloads the signed proof as an order-specific file', async () => {
    mocks.getPaymentProofSignedUrl.mockResolvedValue('https://storage.example/signed-proof.jpg');
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      blob: async () => new Blob(['proof'], { type: 'image/png' }),
    });
    vi.stubGlobal('fetch', fetchMock);
    vi.spyOn(URL, 'createObjectURL').mockReturnValue('blob:https://test/proof');
    const clickedDownloads: string[] = [];
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function () {
      clickedDownloads.push(this.download);
    });
    renderOrderDetails();

    await screen.findByRole('img', { name: 'Bukti pembayaran yang diunggah pembeli' });
    fireEvent.click(screen.getByRole('button', { name: 'Unduh bukti pembayaran' }));

    await waitFor(() => expect(clickedDownloads).toEqual(['bukti-pembayaran-665F3CB3.png']));
    expect(fetchMock).toHaveBeenCalledWith('https://storage.example/signed-proof.jpg');
    expect(mocks.toast.success).toHaveBeenCalledWith('Bukti pembayaran berhasil diunduh');
  });

  it('lets an admin confirm a pending transfer with uploaded proof', async () => {
    renderOrderDetails([], { status: 'PENDING_PAYMENT', payment_status: 'PENDING_TRANSFER' });

    fireEvent.click(screen.getByRole('button', { name: 'Konfirmasi Pembayaran' }));

    await waitFor(() => expect(mocks.onVerifyPayment).toHaveBeenCalledWith(order.id));
  });

  it('requires a reason before rejecting the uploaded payment proof', async () => {
    renderOrderDetails([], { status: 'PENDING_PAYMENT', payment_status: 'PENDING_TRANSFER' });

    fireEvent.click(screen.getByRole('button', { name: 'Tolak Bukti Pembayaran' }));
    const reason = screen.getByRole('textbox', { name: 'Alasan penolakan (wajib)' });
    const submit = screen.getByRole('button', { name: 'Konfirmasi Penolakan' });
    expect(submit).toBeDisabled();

    fireEvent.change(reason, { target: { value: 'Nominal transfer tidak sesuai' } });
    fireEvent.click(submit);

    await waitFor(() => expect(mocks.onRejectPayment).toHaveBeenCalledWith(order.id, 'Nominal transfer tidak sesuai'));
  });

  it('does not show payment review actions when no proof is uploaded', () => {
    renderOrderDetails([], { status: 'PENDING_PAYMENT', payment_status: 'PENDING_TRANSFER', payment_proof_url: null });

    expect(screen.queryByRole('button', { name: 'Konfirmasi Pembayaran' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Tolak Bukti Pembayaran' })).not.toBeInTheDocument();
  });

  it('waits for a replacement proof after the current proof has been rejected', () => {
    renderOrderDetails([], { status: 'PENDING_PAYMENT', payment_status: 'FAILED' });

    expect(screen.getByText('Bukti sebelumnya ditolak. Menunggu pembeli mengunggah bukti pembayaran baru.')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Konfirmasi Pembayaran' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Tolak Bukti Pembayaran' })).not.toBeInTheDocument();
  });

  it('uses valid server transitions when accepting an internal order for self-delivery', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: null });
    renderOrderDetails([], { status: 'NEW', delivery_type: 'INTERNAL' });

    fireEvent.click(screen.getByRole('radio', { name: /Kirim Sendiri/i }));
    fireEvent.click(screen.getByRole('button', { name: 'Proses & Kirim Sendiri' }));

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledTimes(2));
    expect(mocks.rpc.mock.calls[0][0]).toBe('merchant_transition_order');
    expect(mocks.rpc.mock.calls[0][1]).toMatchObject({ p_to_status: 'PROCESSED' });
    expect(mocks.rpc.mock.calls[1][0]).toBe('merchant_transition_order');
    expect(mocks.rpc.mock.calls[1][1]).toMatchObject({ p_to_status: 'DELIVERING' });
  });

  it('offers courier assignment instead of an invalid SENT transition for internal orders', () => {
    renderOrderDetails([], { status: 'PROCESSED', delivery_type: 'INTERNAL' });

    expect(screen.queryByRole('button', { name: /^Kirim$/i })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Tugaskan Kurir Desa' })).toBeInTheDocument();
  });
});
