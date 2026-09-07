export type CheckoutRecoveryAction = 'replay_idempotent_request' | 'manual_conflict' | 'ignore_synced';

export interface CheckoutRecoveryRecord {
  synced?: boolean;
  status?: 'queued' | 'syncing' | 'failed' | 'conflict' | 'synced';
}

export function getCheckoutRecoveryAction(record: CheckoutRecoveryRecord): CheckoutRecoveryAction {
  if (record.synced || record.status === 'synced') return 'ignore_synced';
  if (record.status === 'conflict') return 'manual_conflict';
  return 'replay_idempotent_request';
}

/**
 * These are the failure points covered by the durable checkpoint. All four
 * must replay the same request key; the server RPC then decides whether this
 * is a first attempt or an idempotent duplicate.
 */
export const OFFLINE_CHECKOUT_RECOVERY_SCENARIOS = [
  'browser_refresh',
  'tab_or_device_closed',
  'power_loss',
  'connection_drop_during_checkout',
] as const;

export type OfflineCheckoutRecoveryScenario = typeof OFFLINE_CHECKOUT_RECOVERY_SCENARIOS[number];