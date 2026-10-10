export interface DashboardOrderTimestamps {
  status: string;
  created_at: string;
  updated_at?: string | null;
  status_updated_at?: string | null;
  delivered_at?: string | null;
}

export interface DashboardPeriodOrder {
  status: string;
  total: number | null;
}

export function calculatePeriodOrderStats(orders: DashboardPeriodOrder[]) {
  const completed = orders.filter((order) => order.status === 'DONE');
  return {
    orders: orders.length,
    revenue: completed.reduce((sum, order) => sum + Number(order.total || 0), 0),
    pending: orders.filter((order) => order.status === 'NEW').length,
    processing: orders.filter((order) => ['PROCESSED', 'SENT'].includes(order.status)).length,
    completed: completed.length,
  };
}

export function getLocalDayBounds(now = new Date()) {
  const start = new Date(now);
  start.setHours(0, 0, 0, 0);

  const end = new Date(start);
  end.setDate(end.getDate() + 1);

  return { start, end };
}

export function getCompletionTimestamp(order: DashboardOrderTimestamps) {
  // DONE orders set delivered_at when the final transition occurs. The other
  // fields are fallbacks for legacy rows and older transition implementations.
  return order.delivered_at || order.status_updated_at || order.updated_at || order.created_at;
}

export function isCompletedToday(order: DashboardOrderTimestamps, now = new Date()) {
  if (order.status !== 'DONE') return false;

  const completedAt = new Date(getCompletionTimestamp(order));
  const { start, end } = getLocalDayBounds(now);
  return completedAt >= start && completedAt < end;
}
