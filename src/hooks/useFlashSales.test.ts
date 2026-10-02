import { renderHook, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const { query, response, channel, removeChannel } = vi.hoisted(() => ({
  query: {
    select: vi.fn(),
    eq: vi.fn(),
    gt: vi.fn(),
    order: vi.fn(),
    then: vi.fn(),
  },
  response: { current: { data: [], error: null } as { data: unknown[] | null; error: Error | null } },
  channel: {
    on: vi.fn(),
    subscribe: vi.fn(),
  },
  removeChannel: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => ({ select: query.select }),
    channel: () => channel,
    removeChannel,
  },
}));

import { useFlashSales } from './useFlashSales';

beforeEach(() => {
  query.select.mockReset().mockReturnValue(query);
  query.eq.mockReset().mockReturnValue(query);
  query.gt.mockReset().mockReturnValue(query);
  query.order.mockReset().mockReturnValue(query);
  query.then.mockReset().mockImplementation((resolve) => Promise.resolve(response.current).then(resolve));
  response.current = { data: [], error: null };
  channel.on.mockReset().mockReturnValue(channel);
  channel.subscribe.mockReset().mockReturnValue(channel);
  removeChannel.mockReset();
});

describe('useFlashSales', () => {
  it('uses a numeric PostgREST stock filter and only returns sales with remaining stock', async () => {
    response.current = {
      data: [
        {
          id: 'sold-out', product_id: 'p0', merchant_id: 'm0', original_price: 100, flash_price: 80,
          stock_available: 3, stock_sold: 3, end_time: '2026-10-03T00:00:00Z', reason: null,
          products: { name: 'Habis', image_url: null }, merchants: { name: 'Toko 0' },
        },
        {
          id: 'available-1', product_id: 'p1', merchant_id: 'm1', original_price: 100, flash_price: 70,
          stock_available: 5, stock_sold: 2, end_time: '2026-10-03T01:00:00Z', reason: null,
          products: { name: 'Tersedia 1', image_url: null }, merchants: { name: 'Toko 1' },
        },
        {
          id: 'available-2', product_id: 'p2', merchant_id: 'm2', original_price: 100, flash_price: 75,
          stock_available: 4, stock_sold: 1, end_time: '2026-10-03T02:00:00Z', reason: null,
          products: { name: 'Tersedia 2', image_url: null }, merchants: { name: 'Toko 2' },
        },
      ],
      error: null,
    };

    const { result, unmount } = renderHook(() => useFlashSales({ limit: 1 }));

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(query.gt).toHaveBeenCalledWith('stock_available', 0);
    expect(result.current.error).toBeNull();
    expect(result.current.flashSales.map((sale) => sale.id)).toEqual(['available-1']);
    unmount();
    expect(removeChannel).toHaveBeenCalled();
  });

  it('preserves query errors instead of treating a failed request as an empty result', async () => {
    const queryError = new Error('query failed');
    response.current = { data: null, error: queryError };

    const { result } = renderHook(() => useFlashSales());
    await waitFor(() => expect(result.current.error).toBe(queryError));
  });
});
