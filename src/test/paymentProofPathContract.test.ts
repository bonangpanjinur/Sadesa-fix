import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/105_20261011240000_harden_payment_proof_path_contract.sql'),
  'utf8',
);

describe('payment proof path contract', () => {
  it('normalizes legacy URLs while validating bucket-relative paths', () => {
    expect(migration).toContain("split_part(trim(COALESCE(p_value, '')), '?', 1)");
    expect(migration).toContain("/storage/v1/object/(public|authenticated|sign)/payment-proofs/");
    expect(migration).toContain("v_parts[1] <> 'orders'");
    expect(migration).toContain('v_parts[2] <> p_order_id::text');
  });

  it('requires separate canonical shapes for authenticated and guest uploads', () => {
    expect(migration).toContain('array_length(v_parts, 1) = 3');
    expect(migration).toContain('array_length(v_parts, 1) = 4');
    expect(migration).toContain('v_parts[3] = p_guest_token_hash');
    expect(migration).toContain('public.is_valid_payment_proof_path(v_path, p_order_id, NULL)');
    expect(migration).toContain('public.is_valid_payment_proof_path(v_path, p_order_id, v_token_hash)');
  });

  it('replaces the URL-only guest trigger check', () => {
    expect(migration).toContain('NOT public.is_valid_payment_proof_path(');
    expect(migration).not.toContain("position(\n         ('/payment-proofs/orders/'");
  });
});
