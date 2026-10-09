import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/91_20261009100000_commission_wallet_alerts.sql'),
  'utf8',
);

describe('commission wallet low-balance alert migration', () => {
  it('stores a per-wallet alert gate and resets it after recovery', () => {
    expect(migration).toContain('ADD COLUMN IF NOT EXISTS low_balance_alerted_at timestamptz');
    expect(migration).toContain('IF NEW.low_balance_alerted_at IS NOT NULL THEN');
    expect(migration).toContain('NEW.balance_rupiah > v_threshold AND NEW.debt_rupiah = 0');
    expect(migration).toContain('NEW.low_balance_alerted_at := NULL');
  });

  it('sends warning notifications to the owner with role-specific wallet links', () => {
    expect(migration).toContain("VALUES (v_user_id, v_title, v_message, 'warning', v_link)");
    expect(migration).toContain("v_link := '/merchant/wallet'");
    expect(migration).toContain("v_link := '/courier/commission-wallet'");
    expect(migration).toContain("v_title := 'Komisi tertunggak'");
  });

  it('re-evaluates wallets after a dynamic threshold change and backfills low wallets', () => {
    expect(migration).toContain('commission_wallet_policy_threshold_alert_check');
    expect(migration).toContain('commission_wallet_fee_alert_check');
    expect(migration).toContain('s.is_enabled AND s.fee_percent > 0');
    expect(migration).toContain('UPDATE public.commission_wallets\n    SET balance_rupiah = balance_rupiah');
    expect(migration).toContain('low_balance_alerted_at IS NULL');
  });
});
