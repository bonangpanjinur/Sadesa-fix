import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/98_20261010180000_retire_merchant_free_trial_trigger.sql'),
  'utf8',
);

describe('retire merchant free-trial trigger migration', () => {
  it('removes the obsolete free-trial subscription trigger idempotently', () => {
    expect(migration).toContain('DROP TRIGGER IF EXISTS grant_new_merchant_free_trial_trigger ON public.merchants');
    expect(migration).toContain('DO $bootstrap_do_');
    expect(migration).toContain('EXCEPTION');
  });

  it('does not remove commission wallet provisioning or alter wallet balances', () => {
    expect(migration).not.toContain('merchants_provision_commission_wallet');
    expect(migration).not.toContain('commission_wallets');
    expect(migration).not.toContain('DELETE FROM');
  });
});
