export interface MerchantDashboardOrder {
  status: string;
  total: number;
  subtotal?: number | null;
  created_at: string;
}

export interface MerchantDashboardSalesPoint {
  date: string;
  revenue: number;
  orders: number;
}

export function getLocalDateKey(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/** Build a 14-calendar-day chart in the user's local timezone. */
export function buildMerchantSalesChartData(
  orders: readonly MerchantDashboardOrder[],
  now: Date = new Date(),
): MerchantDashboardSalesPoint[] {
  const dateMap = new Map<string, MerchantDashboardSalesPoint>();
  for (const order of orders) {
    const date = getLocalDateKey(new Date(order.created_at));
    const current = dateMap.get(date) ?? { date, revenue: 0, orders: 0 };
    current.orders += 1;
    if (order.status === 'DONE') current.revenue += order.subtotal ?? order.total;
    dateMap.set(date, current);
  }

  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const result: MerchantDashboardSalesPoint[] = [];
  for (let offset = 13; offset >= 0; offset -= 1) {
    const date = new Date(today);
    date.setDate(today.getDate() - offset);
    const key = getLocalDateKey(date);
    result.push(dateMap.get(key) ?? { date: key, revenue: 0, orders: 0 });
  }
  return result;
}
