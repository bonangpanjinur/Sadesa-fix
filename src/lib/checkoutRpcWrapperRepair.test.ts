import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/bootstrap/144_20261121003000_restore_marketplace_checkout_implementation.sql',
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
});
