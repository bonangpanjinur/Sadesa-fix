import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const mocks = vi.hoisted(() => ({
  getPaymentProofSignedUrl: vi.fn(),
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

vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }));

import { OrderDetailsDialog } from './OrderDetailsDialog';

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe('OrderDetailsDialog payment proof', () => {
  it('shows the buyer-uploaded proof using a signed storage URL', async () => {
    mocks.getPaymentProofSignedUrl.mockResolvedValue('https://storage.example/signed-proof.jpg');
    const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const order = {
      id: '665f3cb3-1234-4567-8901-123456789abc',
      status: 'DONE',
      payment_status: 'PAID',
      payment_method: 'TRANSFER',
      payment_proof_url: 'orders/665f3cb3-1234-4567-8901-123456789abc/buyer/proof.jpg',
      delivery_type: 'PICKUP',
      delivery_name: 'Pembeli',
      delivery_phone: null,
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

    render(
      <QueryClientProvider client={queryClient}>
        <OrderDetailsDialog
          open
          onOpenChange={vi.fn()}
          order={order}
          orderItems={[]}
          onUpdateStatus={vi.fn()}
          onOpenAssignCourier={vi.fn()}
          getStatusBadge={() => <span>Selesai</span>}
          getPaymentBadge={() => <span>Lunas</span>}
        />
      </QueryClientProvider>,
    );

    const proofImage = await screen.findByRole('img', { name: 'Bukti pembayaran yang diunggah pembeli' });
    expect(proofImage).toHaveAttribute('src', 'https://storage.example/signed-proof.jpg');
    expect(mocks.getPaymentProofSignedUrl).toHaveBeenCalledWith(order.payment_proof_url);
  });
});
