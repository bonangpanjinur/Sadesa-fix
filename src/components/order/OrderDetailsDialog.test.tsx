import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const mocks = vi.hoisted(() => ({
  getPaymentProofSignedUrl: vi.fn(),
  toast: { success: vi.fn(), error: vi.fn() },
}));

vi.mock('@/lib/paymentProof', () => ({
  getPaymentProofSignedUrl: mocks.getPaymentProofSignedUrl,
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: vi.fn(),
    rpc: vi.fn(),
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

function renderOrderDetails(items = orderItems) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queryClient}>
      <OrderDetailsDialog
        open
        onOpenChange={vi.fn()}
        order={order}
        orderItems={items}
        onUpdateStatus={vi.fn()}
        onOpenAssignCourier={vi.fn()}
        getStatusBadge={() => <span>Selesai</span>}
        getPaymentBadge={() => <span>Lunas</span>}
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
});
