export interface PushDeliveryCounts {
  total: number;
  sent: number;
  failed: number;
  expired: number;
}

export interface PushDeliveryKpis {
  successRate: number;
  issueCount: number;
}

export function calculatePushDeliveryKpis(counts: PushDeliveryCounts): PushDeliveryKpis {
  return {
    successRate: counts.total > 0 ? Math.round((counts.sent / counts.total) * 100) : 0,
    issueCount: counts.failed + counts.expired,
  };
}
