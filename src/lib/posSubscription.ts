export type POSSubscriptionStatus = 'PENDING' | 'ACTIVE' | 'REJECTED' | 'SUSPENDED' | 'CANCELLED' | 'EXPIRED';

export interface POSSubscriptionRecord {
  status: string;
  is_trial?: boolean | null;
  expired_at?: string | null;
  payment_status?: string | null;
}

export type POSSubscriptionState = 'NO_SUBSCRIPTION' | 'PENDING_REVIEW' | 'ACTIVE' | 'EXPIRING_SOON' | 'EXPIRED' | 'REJECTED' | 'SUSPENDED';

export function getPOSSubscriptionState(subscription: POSSubscriptionRecord | null, now = new Date()): POSSubscriptionState {
  if (!subscription) return 'NO_SUBSCRIPTION';
  if (subscription.status === 'PENDING') return 'PENDING_REVIEW';
  if (subscription.status === 'REJECTED') return 'REJECTED';
  if (subscription.status === 'SUSPENDED') return 'SUSPENDED';
  if (subscription.status !== 'ACTIVE' || !subscription.expired_at) return 'EXPIRED';
  const expiry = new Date(subscription.expired_at);
  if (Number.isNaN(expiry.getTime()) || expiry <= now) return 'EXPIRED';
  const daysRemaining = (expiry.getTime() - now.getTime()) / 86_400_000;
  return daysRemaining <= 7 ? 'EXPIRING_SOON' : 'ACTIVE';
}

export function isPOSSubscriptionActive(subscription: POSSubscriptionRecord | null, now = new Date()) {
  const state = getPOSSubscriptionState(subscription, now);
  return state === 'ACTIVE' || state === 'EXPIRING_SOON';
}

export const POS_SUBSCRIPTION_STATE_LABEL: Record<POSSubscriptionState, string> = {
  NO_SUBSCRIPTION: 'Belum berlangganan',
  PENDING_REVIEW: 'Menunggu verifikasi admin',
  ACTIVE: 'Aktif',
  EXPIRING_SOON: 'Segera berakhir',
  EXPIRED: 'Sudah berakhir',
  REJECTED: 'Ditolak',
  SUSPENDED: 'Ditangguhkan',
};
