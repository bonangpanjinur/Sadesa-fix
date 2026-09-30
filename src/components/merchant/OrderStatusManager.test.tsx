import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const mocks = vi.hoisted(() => ({
  order: {
    id: 'order-1234',
    status: 'PENDING_PAYMENT',
    payment_status: 'PENDING',
    payment_method: 'TRANSFER',
    total: 50000,
    delivery_name: 'Budi',
    delivery_phone: '08123456789',
    delivery_address: 'Jl. Desa',
    notes: null,
    created_at: '2026-08-23T10:00:00.000Z',
    confirmation_deadline: null,
    payment_proof_url: 'https://storage.example/payment-proofs/order-1234.jpg',
  },
  from: vi.fn(),
  update: vi.fn(),
  rpc: vi.fn(),
  toast: { success: vi.fn(), error: vi.fn() },
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: mocks.from,
    rpc: mocks.rpc,
    storage: {
      from: vi.fn(() => ({
        createSignedUrl: vi.fn().mockResolvedValue({ data: { signedUrl: 'https://storage.example/signed-proof.jpg' }, error: null }),
      })),
    },
  },
}));
vi.mock('sonner', () => ({ toast: mocks.toast }));
vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: { id: 'buyer-1' } }),
}));
vi.mock('@/hooks/useMerchantGuard', () => ({
  useMerchantGuard: () => ({ merchantId: 'merchant-1', merchantName: 'Toko Uji', loading: false }),
}));
vi.mock('@/hooks/useRealtimeOrders', () => ({
  useRealtimeOrders: () => ({
    orders: [mocks.order],
    loading: false,
    updateOrderStatus: vi.fn(),
    refetch: vi.fn().mockResolvedValue(undefined),
  }),
}));

import { OrderStatusManager } from './OrderStatusManager';

function makeQuery(data: unknown) {
  const query = {
    select: vi.fn(() => query),
    eq: vi.fn(() => query),
    order: vi.fn(() => query),
    limit: vi.fn(() => Promise.resolve({ data, error: null })),
    update: vi.fn(() => query),
    rpc: vi.fn(() => Promise.resolve({ data: { success: true }, error: null })),
  };
  return query;
}

describe('OrderStatusManager payment and status transitions', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.rpc.mockResolvedValue({ data: { success: true }, error: null });
    mocks.from.mockImplementation(((table: string) => {
      if (table === 'orders') {
        const query = makeQuery([mocks.order]);
        query.update.mockImplementation((() => ({
          eq: vi.fn(() => Promise.resolve({ data: null, error: null })),
        })) as never);
        return query;
      }
      return makeQuery([]);
    }) as never);
  });

  it('verifies a payment proof and transitions pending payment to processed', async () => {
    const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={queryClient}>
        <MemoryRouter>
          <OrderStatusManager merchantId="merchant-1" />
        </MemoryRouter>
      </QueryClientProvider>,
    );

    const detailButton = await screen.findByRole('button', { name: /lihat detail pesanan/i });
    await act(async () => detailButton.click());
    const verifyButton = await screen.findByRole('button', { name: /verifikasi pembayaran/i });
    await act(async () => verifyButton.click());

    await waitFor(() => expect(mocks.toast.success).toHaveBeenCalledWith('Pembayaran berhasil diverifikasi'));
    expect(mocks.rpc).toHaveBeenCalledWith('merchant_verify_order_payment', {
      p_order_id: 'order-1234',
    });
  });
});
