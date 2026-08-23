import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';

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
  toast: { success: vi.fn(), error: vi.fn() },
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: mocks.from },
}));
vi.mock('sonner', () => ({ toast: mocks.toast }));

import { OrderStatusManager } from './OrderStatusManager';

function makeQuery(data: unknown) {
  const query = {
    select: vi.fn(() => query),
    eq: vi.fn(() => query),
    order: vi.fn(() => query),
    limit: vi.fn(() => Promise.resolve({ data, error: null })),
    update: vi.fn(() => query),
  };
  return query;
}

describe('OrderStatusManager payment and status transitions', () => {
  beforeEach(() => {
    vi.clearAllMocks();
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
    render(
      <MemoryRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        <OrderStatusManager merchantId="merchant-1" />
      </MemoryRouter>,
    );

    const verifyButton = await screen.findByRole('button', { name: /verifikasi bayar/i });
    await act(async () => verifyButton.click());

    await waitFor(() => expect(mocks.toast.success).toHaveBeenCalledWith('Pembayaran berhasil diverifikasi'));
    const orderQuery = mocks.from.mock.results.at(-1)?.value;
    expect(orderQuery.update).toHaveBeenCalledWith(expect.objectContaining({
      payment_status: 'PAID',
      status: 'PROCESSED',
    }));
  });
});
