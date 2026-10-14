import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20261014113000_enforce_marketplace_checkout_payment_and_phone.sql',
), 'utf8');

const bootstrap = readFileSync(resolve(
  process.cwd(),
  'supabase/bootstrap/119_20261014113000_to_20261014113000.sql',
), 'utf8');

describe('marketplace checkout server contract', () => {
  it('enforces the same 8–15 digit phone contract at the database boundary', () => {
    expect(migration).toContain("regexp_replace(COALESCE(NEW.delivery_phone, ''), '[^0-9]', '', 'g')");
    expect(migration).toContain('length(v_phone_digits) < 8 OR length(v_phone_digits) > 15');
    expect(migration).toContain("Invalid delivery phone number");
  });

  it('rejects disabled merchant transfer and disabled online gateway payment', () => {
    expect(migration).toContain("NEW.payment_method = 'TRANSFER'");
    expect(migration).toContain('m.payment_transfer_enabled');
    expect(migration).toContain('Transfer payment is unavailable for this merchant');
    expect(migration).toContain("NEW.payment_method = 'ONLINE'");
    expect(migration).toContain("s.key = 'payment_xendit'");
    expect(migration).toContain('Online payment is currently unavailable');
  });

  it('ships the same contract in the ordered bootstrap bundle', () => {
    expect(bootstrap).toContain('20261014113000_enforce_marketplace_checkout_payment_and_phone.sql');
    expect(bootstrap).toContain('CREATE TRIGGER enforce_marketplace_checkout_contract');
  });
});
