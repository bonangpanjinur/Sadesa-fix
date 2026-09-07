import { describe, expect, it } from 'vitest';
import {
  getCheckoutRecoveryAction,
  OFFLINE_CHECKOUT_RECOVERY_SCENARIOS,
} from './posOfflineRecovery';

describe('POS offline checkout recovery contract', () => {
  it.each(OFFLINE_CHECKOUT_RECOVERY_SCENARIOS)(
    'replays the same durable request after %s',
    () => {
      expect(getCheckoutRecoveryAction({ status: 'queued' })).toBe('replay_idempotent_request');
    },
  );

  it('does not replay a sale already confirmed by the server', () => {
    expect(getCheckoutRecoveryAction({ synced: true, status: 'synced' })).toBe('ignore_synced');
  });

  it('keeps price and stock conflicts for manual resolution', () => {
    expect(getCheckoutRecoveryAction({ status: 'conflict' })).toBe('manual_conflict');
  });
});