import { calculateFeeSnapshot, type FeeSchedule } from './feeEngine';

export interface AdminFinanceOrder {
  total: number;
  subtotal: number;
  shipping_cost: number;
  status: string;
}

export interface AdminFinancialData {
  totalRevenue: number;
  platformFees: number;
  courierFees: number;
  merchantRevenue: number;
  shippingCollected: number;
  completedOrders: number;
}

const EFFECTIVE_FROM = '1970-01-01T00:00:00.000Z';

function nonNegativeFinite(value: number | null | undefined): number {
  return Number.isFinite(value) ? Math.max(0, value as number) : 0;
}

function percentageSchedule(version: string, ruleId: string, label: string, payer: 'merchant' | 'provider', ratePercent: number): FeeSchedule {
  return {
    version,
    effectiveFrom: EFFECTIVE_FROM,
    rules: [{ id: ruleId, label, kind: payer === 'provider' ? 'usage' : 'commission', payer, ratePercent }],
  };
}

export function calculateOrderPlatformFee(subtotal: number, platformFeePercent: number): number {
  return calculateFeeSnapshot({
    baseAmount: nonNegativeFinite(subtotal),
    schedule: percentageSchedule('admin-finance-platform-v1', 'platform-commission', 'Komisi platform', 'merchant', nonNegativeFinite(platformFeePercent)),
    at: new Date(),
  }).merchantFees;
}

export function calculateAdminFinancials(
  orders: readonly AdminFinanceOrder[],
  platformFeePercent: number,
  courierFeePercent: number,
): AdminFinancialData {
  const completed = orders.filter((order) => order.status === 'DONE' || order.status === 'DELIVERED');
  const platformSchedule = percentageSchedule('admin-finance-platform-v1', 'platform-commission', 'Komisi platform', 'merchant', nonNegativeFinite(platformFeePercent));
  const courierSchedule = percentageSchedule('admin-finance-courier-v1', 'courier-commission', 'Komisi kurir', 'provider', nonNegativeFinite(courierFeePercent));

  const totals = completed.reduce((result, order) => {
    const subtotal = nonNegativeFinite(order.subtotal);
    const shipping = nonNegativeFinite(order.shipping_cost);
    const platformSnapshot = calculateFeeSnapshot({ baseAmount: subtotal, schedule: platformSchedule, at: new Date() });
    const courierSnapshot = calculateFeeSnapshot({ baseAmount: shipping, schedule: courierSchedule, at: new Date() });
    result.totalRevenue += nonNegativeFinite(order.total);
    result.totalSubtotal += subtotal;
    result.shippingCollected += shipping;
    result.platformFees += platformSnapshot.merchantFees;
    result.courierFees += courierSnapshot.providerFees;
    return result;
  }, { totalRevenue: 0, totalSubtotal: 0, shippingCollected: 0, platformFees: 0, courierFees: 0 });

  return {
    totalRevenue: totals.totalRevenue,
    platformFees: totals.platformFees,
    courierFees: totals.courierFees,
    merchantRevenue: Math.max(0, totals.totalSubtotal - totals.platformFees),
    shippingCollected: totals.shippingCollected,
    completedOrders: completed.length,
  };
}
