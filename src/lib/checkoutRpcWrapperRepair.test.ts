import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/bootstrap/144_20261121003000_restore_marketplace_checkout_implementation.sql',
), 'utf8');
const initialGdcWrapper = readFileSync(resolve(
  process.cwd(),
  'supabase/bootstrap/150_20261121174000_qris_checkout_channel_binding.sql',
), 'utf8');
const overloadRepair = readFileSync(resolve(
  process.cwd(),
  'supabase/bootstrap/151_20261122001000_fix_marketplace_checkout_overload_ambiguity.sql',
), 'utf8');

describe('marketplace checkout wrapper repair', () => {
  it('restores the canonical seven-argument authoritative RPC', () => {
    expect(migration).toMatch(/CREATE OR REPLACE FUNCTION public\.create_marketplace_checkout\([\s\S]*?p_checkout_key text DEFAULT NULL[\s\S]*?\)\s*RETURNS jsonb/);
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) FROM PUBLIC, anon');
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) TO authenticated, service_role');
  });

  it('contains the authoritative checkout logic and not the broken recursive 8-argument wrapper', () => {
    expect(migration).toContain('public.normalize_marketplace_checkout_items(p_items)');
    expect(migration).toContain('public.marketplace_shipping_contract_quote(');
    expect(migration).toContain('INSERT INTO public.orders');
    expect(migration).toContain('public.reserve_marketplace_stock(');
    expect(migration).toContain('INSERT INTO public.marketplace_checkout_idempotency');
    expect(migration).not.toMatch(/RETURN public\.create_marketplace_checkout\([\s\S]*?p_checkout_key\s*,\s*NULL\s*\)/);
  });

  it('routes the GDC wrapper through the private, non-overloaded checkout helper', () => {
    for (const source of [initialGdcWrapper, overloadRepair]) {
      expect(source).toContain('v_result := public.create_marketplace_checkout_core(');
      expect(source).not.toMatch(/v_result\s*:=\s*public\.create_marketplace_checkout\s*\(/);
    }
  });

  it('hides the historical seven-argument overload from API roles and reloads PostgREST', () => {
    expect(overloadRepair).toContain(
      'REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) FROM PUBLIC, anon, authenticated, service_role',
    );
    expect(overloadRepair).toContain(
      'GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text, text) TO authenticated, service_role',
    );
    expect(overloadRepair).toContain("NOTIFY pgrst, 'reload schema'");
  });
});
