import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { formatPrice } from '@/lib/utils';

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
  channel: vi.fn(),
  removeChannel: vi.fn(),
  navigate: vi.fn(),
  user: { id: 'buyer-1' },
  searchParams: new URLSearchParams(),
  createGdcPayment: vi.fn(),
  queryGdcPayment: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: mocks.from, rpc: vi.fn(), channel: mocks.channel, removeChannel: mocks.removeChannel },
}));

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: mocks.user, loading: false }),
}));

vi.mock('react-router-dom', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-router-dom')>();
  return {
    ...actual,
    useNavigate: () => mocks.navigate,
    useParams: () => ({ orderId: 'order-1' }),
    useSearchParams: () => [mocks.searchParams],
  };
});

vi.mock('@/lib/gdcQrisMpmApi', () => ({
  createOrGetGdcQrisMpm: mocks.createGdcPayment,
  queryGdcQrisMpmStatus: mocks.queryGdcPayment,
}));

vi.mock('@/components/checkout/PaymentProofUpload', () => ({
  PaymentProofUpload: () => null,
}));

vi.mock('@/components/checkout/PaymentCountdown', () => ({
  PaymentCountdown: () => null,
}));

import PaymentConfirmationPage from './PaymentConfirmationPage';

describe('PaymentConfirmationPage authoritative order total', () => {
  beforeEach(() => {
    mocks.user = { id: 'buyer-1' };
    mocks.searchParams = new URLSearchParams();
    mocks.createGdcPayment.mockReset();
    mocks.queryGdcPayment.mockReset();
    const realtimeChannel = { on: vi.fn(), subscribe: vi.fn() };
    realtimeChannel.on.mockReturnValue(realtimeChannel);
    mocks.channel.mockReturnValue(realtimeChannel);
    mocks.from.mockImplementation((table: string) => {
      const result = table === 'orders'
        ? {
            data: {
              id: 'order-1',
              total: 125_000,
              payment_method: 'TRANSFER',
              payment_status: 'PENDING_TRANSFER',
              merchant_id: 'merchant-1',
              created_at: '2026-10-13T00:00:00.000Z',
              payment_destination_snapshot: {
                bank_name: 'Bank Test',
                bank_account_number: '123456789',
                bank_account_name: 'Pemilik Test',
                qris_image_url: 'https://example.com/merchant-qris.png',
              },
            },
            error: null,
          }
        : table === 'merchants'
          ? {
              data: {
                name: 'Merchant Test',
                bank_name: 'Bank Test',
                bank_account_number: '123456789',
                bank_account_name: 'Pemilik Test',
                qris_image_url: null,
              },
              error: null,
            }
          : { data: { value: {} }, error: null };
      const query = {
        select: vi.fn(() => query),
        eq: vi.fn(() => query),
        maybeSingle: vi.fn(async () => result),
      };
      return query;
    });
  });

  afterEach(() => {
    cleanup();
    vi.clearAllMocks();
  });

  it('renders the persisted database total as the amount to pay', async () => {
    render(<PaymentConfirmationPage />);

    await waitFor(() => expect(screen.getByText('Total Pembayaran')).toBeInTheDocument());
    expect(screen.getByText((content) => content.replace(/[\s\u00a0]/g, '') === formatPrice(125_000).replace(/[\s\u00a0]/g, ''))).toBeInTheDocument();
    expect(screen.getByAltText('QRIS Payment')).toHaveAttribute('src', 'https://example.com/merchant-qris.png');
    expect(screen.getByText('123456789')).toBeInTheDocument();
    expect(screen.getByText('Bank Test')).toBeInTheDocument();
  });

  it('stops automatic QRIS retries after a failure and permits a manual retry', async () => {
    mocks.searchParams = new URLSearchParams('provider=gdc-mpm');
    mocks.createGdcPayment
      .mockRejectedValueOnce(new Error('Sesi login tidak ditemukan. Silakan masuk kembali lalu coba lagi.'))
      .mockResolvedValueOnce({
        order_id: 'order-1',
        status: 'PENDING',
        amount: 125000,
        currency: 'IDR',
        qr_content: 'qris-payload',
        reference_no: 'gdc-1',
        paid_at: null,
      });

    render(<PaymentConfirmationPage />);

    await waitFor(() => expect(screen.getByText('Sesi login tidak ditemukan. Silakan masuk kembali lalu coba lagi.')).toBeInTheDocument());
    await new Promise(resolve => setTimeout(resolve, 25));
    expect(mocks.createGdcPayment).toHaveBeenCalledTimes(1);

    fireEvent.click(screen.getByRole('button', { name: 'Coba Lagi' }));
    await waitFor(() => expect(mocks.createGdcPayment).toHaveBeenCalledTimes(2));
    await waitFor(() => expect(screen.getByText(/Scan kode QRIS di atas/)).toBeInTheDocument());
  });

  it('does not call the protected QRIS function without a logged-in buyer', async () => {
    mocks.user = null;
    mocks.searchParams = new URLSearchParams('provider=gdc-mpm');

    render(<PaymentConfirmationPage />);

    await waitFor(() => expect(screen.getByText('Sesi login tidak ditemukan. Silakan masuk kembali lalu coba lagi.')).toBeInTheDocument());
    expect(mocks.createGdcPayment).not.toHaveBeenCalled();
  });
});
