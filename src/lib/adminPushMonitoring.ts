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

export interface PushDeliveryHourlyStat {
  hour_bucket: string;
  status: string;
  attempt_count: number | string;
}

export interface PushDeliveryHourlyPoint {
  hour: string;
  sent: number;
  failed: number;
  expired: number;
}

export function calculatePushDeliveryKpis(counts: PushDeliveryCounts): PushDeliveryKpis {
  return {
    successRate: counts.total > 0 ? Math.round((counts.sent / counts.total) * 100) : 0,
    issueCount: counts.failed + counts.expired,
  };
}

export function buildPushDeliveryHourlyTrend(
  stats: readonly PushDeliveryHourlyStat[],
  since: Date,
  until: Date,
): PushDeliveryHourlyPoint[] {
  const start = new Date(since);
  const end = new Date(until);
  if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime()) || end < start) return [];

  start.setUTCMinutes(0, 0, 0);
  end.setUTCMinutes(0, 0, 0);

  const points = new Map<number, PushDeliveryHourlyPoint>();
  for (let cursor = start.getTime(); cursor <= end.getTime(); cursor += 60 * 60 * 1000) {
    points.set(cursor, { hour: new Date(cursor).toISOString(), sent: 0, failed: 0, expired: 0 });
  }

  for (const stat of stats) {
    if (stat.status !== 'sent' && stat.status !== 'failed' && stat.status !== 'expired') continue;
    const bucketTime = Date.parse(stat.hour_bucket);
    const point = points.get(bucketTime);
    if (point) point[stat.status] += Number(stat.attempt_count) || 0;
  }

  return [...points.values()];
}
