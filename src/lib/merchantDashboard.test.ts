import { describe, expect, it } from 'vitest';
import { buildMerchantSalesChartData } from './merchantDashboard';

describe('merchant dashboard sales chart', () => {
  it('returns all 14 local calendar days including today and zero-fills missing dates', () => {
    const now = new Date(2026, 9, 10, 15, 30);
    const data = buildMerchantSalesChartData([], now);

    expect(data).toHaveLength(14);
    expect(data[0].date).toBe('2026-09-27');
    expect(data.at(-1)?.date).toBe('2026-10-10');
    expect(data.every((point) => point.orders === 0 && point.revenue === 0)).toBe(true);
  });

  it('groups timestamps by local calendar day and counts revenue only for completed orders', () => {
    const now = new Date(2026, 9, 10, 15, 30);
    const chart = buildMerchantSalesChartData([
      { created_at: new Date(2026, 9, 10, 0, 15).toISOString(), status: 'DONE', subtotal: 75_000, total: 80_000 },
      { created_at: new Date(2026, 9, 10, 12, 0).toISOString(), status: 'NEW', subtotal: 20_000, total: 20_000 },
      { created_at: new Date(2026, 9, 10, 13, 0).toISOString(), status: 'DONE', subtotal: 0, total: 5_000 },
      { created_at: new Date(2026, 9, 1, 12, 0).toISOString(), status: 'DONE', subtotal: 10_000, total: 10_000 },
    ], now);

    expect(chart.at(-1)).toEqual({ date: '2026-10-10', revenue: 75_000, orders: 3 });
    expect(chart.find((point) => point.date === '2026-10-01')).toEqual({ date: '2026-10-01', revenue: 10_000, orders: 1 });
  });
});
