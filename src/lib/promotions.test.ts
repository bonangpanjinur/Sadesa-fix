import { beforeEach, describe, expect, it, vi } from 'vitest';

const { query } = vi.hoisted(() => ({
  query: {
    select: vi.fn(),
    order: vi.fn(),
    eq: vi.fn(),
    lte: vi.fn(),
    or: vi.fn(),
    is: vi.fn(),
    then: vi.fn(),
  },
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => query,
  },
}));

import { fetchPromotions } from './promotions';

beforeEach(() => {
  query.select.mockReset().mockReturnValue(query);
  query.order.mockReset().mockReturnValue(query);
  query.eq.mockReset().mockReturnValue(query);
  query.lte.mockReset().mockReturnValue(query);
  query.or.mockReset().mockReturnValue(query);
  query.is.mockReset().mockReturnValue(query);
  query.then.mockReset().mockImplementation((resolve) => Promise.resolve({ data: [], error: null }).then(resolve));
});

describe('fetchPromotions banner category scope', () => {
  it('limits homepage-wide banners to rows without a category target', async () => {
    await fetchPromotions('banner', null);

    expect(query.eq).toHaveBeenCalledWith('type', 'banner');
    expect(query.is).toHaveBeenCalledWith('category_id', null);
  });

  it('limits a category page to banners assigned to that category', async () => {
    const categoryId = 'category-food-id';
    await fetchPromotions('banner', categoryId);

    expect(query.eq).toHaveBeenCalledWith('category_id', categoryId);
    expect(query.is).not.toHaveBeenCalled();
  });
});
