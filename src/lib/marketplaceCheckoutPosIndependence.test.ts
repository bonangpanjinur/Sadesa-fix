import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

describe('marketplace checkout independent of POS activation', () => {
  const migration = readFileSync(
    resolve(process.cwd(), 'supabase/bootstrap/145_20261121005000_marketplace_checkout_independent_of_pos_activation.sql'),
    'utf8',
  );

  it('uses POS outlet reservations only when the tenant passes the active POS entitlement check', () => {
    expect(migration).toContain('public.is_pos_tenant_active(pt.id)');
    expect(migration).not.toMatch(/WHERE pt\.merchant_id = v_order\.merchant_id AND pt\.is_active = true/);
  });

  it('retains marketplace stock reservation fallback for inactive POS tenants', () => {
    expect(migration).toContain('ELSIF v_variant_id IS NOT NULL THEN');
    expect(migration).toContain('Insufficient marketplace variant stock');
    expect(migration).toContain('Insufficient marketplace stock');
    expect(migration).toContain('UPDATE public.products SET reserved_stock = reserved_stock + v_qty');
  });

  it('does not weaken the POS mutation guard', () => {
    expect(migration).not.toMatch(/DROP TRIGGER|DISABLE TRIGGER|ALTER TABLE .*pos_stock/i);
    expect(migration).not.toContain("set_config('app.pos_stock_projection'");
  });
});
