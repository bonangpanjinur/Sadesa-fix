import { cleanup, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { formatPrice } from '@/lib/utils';

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
  channel: vi.fn(),
  removeChannel: vi.fn(),
  navigate: vi.fn(),
  user: { id: 'buyer-1' },
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: mocks.from, rpc: vi.fn(), channel: mocks.channel, removeChannel: mocks.removeChannel },
}));

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: mocks.user }),
}));

vi.mock('react-router-dom', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-router-dom')>();
  return {
    ...actual,
    useNavigate: () => mocks.navigate,
    useParams: () => ({ orderId: 'order-1' }),
    useSearchParams: () => [new URLSearchParams()],
  };
});

vi.mock('@/components/checkout/PaymentProofUpload', () => ({
  PaymentProofUpload: () => null,
}));

vi.mock('@/components/checkout/PaymentCountdown', () => ({
  PaymentCountdown: () => null,
}));

import PaymentConfirmationPage from './PaymentConfirmationPage';

describe('PaymentConfirmationPage authoritative order total', () => {
  beforeEach(() => {
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
});
