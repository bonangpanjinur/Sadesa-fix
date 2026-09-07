export interface AdminSubscriptionMetricRow {
  merchant_id: string;
  is_trial: boolean;
  status: string | null;
  payment_status: string | null;
  payment_amount: number | string | null;
  created_at: string;
  updated_at: string;
  started_at: string | null;
  package_duration_months?: number | string | null;
}

export interface AdminTenantMetricRow {
  merchant_id: string | null;
}

export interface AdminIntegrationMetricRow {
  status: string | null;
  sync_gap_count: number | string | null;
}

export interface PosBusinessMetrics {
  attachRate: number | null;
  linkedMerchantCount: number;
  trialToPaidRate: number | null;
  trialMerchantCount: number;
  convertedTrialMerchantCount: number;
  mrr: number;
  churnRate: number | null;
  churnedMerchantCount: number;
  paidMerchantBase: number;
  integrationTotal: number;
  integrationReady: number;
  integrationAttention: number;
  openSyncGapCount: number;
}

const ACTIVE_STATUSES = new Set(['active', 'ACTIVE', 'grace', 'GRACE']);
const CANCELLED_STATUSES = new Set(['cancelled', 'CANCELLED']);

function isPaidSubscription(subscription: AdminSubscriptionMetricRow) {
  return !subscription.is_trial && subscription.payment_status === 'PAID';
}

function uniqueMerchantIds(rows: AdminSubscriptionMetricRow[]) {
  return new Set(rows.map((row) => row.merchant_id).filter(Boolean));
}

function percentage(numerator: number, denominator: number) {
  return denominator > 0 ? Math.round((numerator / denominator) * 100) : null;
}

export function calculatePosBusinessMetrics(
  input: {
    totalMerchants: number;
    subscriptions: AdminSubscriptionMetricRow[];
    tenants: AdminTenantMetricRow[];
    integrationHealth: AdminIntegrationMetricRow[];
  },
  now = new Date(),
): PosBusinessMetrics {
  const paidSubscriptions = input.subscriptions.filter(isPaidSubscription);
  const trialMerchantIds = new Set(
    input.subscriptions.filter((subscription) => subscription.is_trial).map((subscription) => subscription.merchant_id),
  );
  const paidMerchantIds = uniqueMerchantIds(paidSubscriptions);
  const convertedTrialMerchantIds = new Set(
    paidSubscriptions
      .filter((subscription) => trialMerchantIds.has(subscription.merchant_id))
      .map((subscription) => subscription.merchant_id),
  );

  const linkedMerchantIds = new Set(input.tenants.map((tenant) => tenant.merchant_id).filter(Boolean));
  const periodStart = new Date(now);
  periodStart.setDate(periodStart.getDate() - 30);

  const paidMerchantBaseIds = new Set(
    paidSubscriptions
      .filter((subscription) => new Date(subscription.started_at || subscription.created_at) <= periodStart)
      .map((subscription) => subscription.merchant_id),
  );
  const churnedMerchantIds = new Set(
    paidSubscriptions
      .filter((subscription) => {
        const updatedAt = new Date(subscription.updated_at);
        return CANCELLED_STATUSES.has(subscription.status || '') &&
          updatedAt >= periodStart &&
          updatedAt <= now;
      })
      .map((subscription) => subscription.merchant_id),
  );

  const mrr = paidSubscriptions
    .filter((subscription) => ACTIVE_STATUSES.has(subscription.status || ''))
    .reduce((total, subscription) => {
      const amount = Number(subscription.payment_amount) || 0;
      const durationMonths = Math.max(1, Number(subscription.package_duration_months) || 1);
      return total + amount / durationMonths;
    }, 0);

  const integrationTotal = input.integrationHealth.length;
  const integrationReady = input.integrationHealth.filter((row) => row.status === 'READY').length;
  const integrationAttention = input.integrationHealth.filter((row) => row.status !== 'READY').length;
  const openSyncGapCount = input.integrationHealth.reduce(
    (total, row) => total + Math.max(0, Number(row.sync_gap_count) || 0),
    0,
  );

  return {
    attachRate: percentage(linkedMerchantIds.size, input.totalMerchants),
    linkedMerchantCount: linkedMerchantIds.size,
    trialToPaidRate: percentage(convertedTrialMerchantIds.size, trialMerchantIds.size),
    trialMerchantCount: trialMerchantIds.size,
    convertedTrialMerchantCount: convertedTrialMerchantIds.size,
    mrr,
    churnRate: percentage(churnedMerchantIds.size, paidMerchantBaseIds.size),
    churnedMerchantCount: churnedMerchantIds.size,
    paidMerchantBase: paidMerchantBaseIds.size,
    integrationTotal,
    integrationReady,
    integrationAttention,
    openSyncGapCount,
  };
}