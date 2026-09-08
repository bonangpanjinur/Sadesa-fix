export type POSSubscriptionStatus = 'PENDING' | 'ACTIVE' | 'REJECTED' | 'SUSPENDED' | 'CANCELLED' | 'EXPIRED';

export interface POSSubscriptionRecord {
  status: string;
  is_trial?: boolean | null;
  expired_at?: string | null;
  grace_ends_at?: string | null;
  payment_status?: string | null;
}

export type POSSubscriptionState = 'NO_SUBSCRIPTION' | 'PENDING_REVIEW' | 'ACTIVE' | 'EXPIRING_SOON' | 'GRACE_PERIOD' | 'EXPIRED' | 'REJECTED' | 'SUSPENDED';

function normalizeSubscriptionStatus(status: string | null | undefined): string {
  return (status || '').trim().toUpperCase();
}

export function getPOSSubscriptionState(subscription: POSSubscriptionRecord | null, now = new Date()): POSSubscriptionState {
  if (!subscription) return 'NO_SUBSCRIPTION';
  const status = normalizeSubscriptionStatus(subscription.status);
  if (status === 'PENDING') return 'PENDING_REVIEW';
  if (status === 'REJECTED') return 'REJECTED';
  if (status === 'SUSPENDED') return 'SUSPENDED';
  if (status === 'CANCELLED') return 'EXPIRED';
  if (!['ACTIVE', 'TRIAL', 'GRACE'].includes(status) || !subscription.expired_at) return 'EXPIRED';

  if (status === 'GRACE') {
    const graceEnds = subscription.grace_ends_at ? new Date(subscription.grace_ends_at) : null;
    return graceEnds && !Number.isNaN(graceEnds.getTime()) && graceEnds > now ? 'GRACE_PERIOD' : 'EXPIRED';
  }

  const expiry = new Date(subscription.expired_at);
  if (Number.isNaN(expiry.getTime())) return 'EXPIRED';
  if (expiry <= now) {
    const graceEnds = subscription.grace_ends_at ? new Date(subscription.grace_ends_at) : null;
    return graceEnds && !Number.isNaN(graceEnds.getTime()) && graceEnds > now ? 'GRACE_PERIOD' : 'EXPIRED';
  }
  const daysRemaining = (expiry.getTime() - now.getTime()) / 86_400_000;
  return daysRemaining <= 7 ? 'EXPIRING_SOON' : 'ACTIVE';
}

export function isPOSSubscriptionActive(subscription: POSSubscriptionRecord | null, now = new Date()) {
  const state = getPOSSubscriptionState(subscription, now);
  return state === 'ACTIVE' || state === 'EXPIRING_SOON' || state === 'GRACE_PERIOD';
}

export const POS_SUBSCRIPTION_STATE_LABEL: Record<POSSubscriptionState, string> = {
  NO_SUBSCRIPTION: 'Belum berlangganan',
  PENDING_REVIEW: 'Menunggu verifikasi admin',
  ACTIVE: 'Aktif',
  EXPIRING_SOON: 'Segera berakhir',
  GRACE_PERIOD: 'Masa tenggang',
  EXPIRED: 'Sudah berakhir',
  REJECTED: 'Ditolak',
  SUSPENDED: 'Ditangguhkan',
};
