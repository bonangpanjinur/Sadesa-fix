import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const policy = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/103_20261011223000_guest_payment_proof_upload.sql'),
  'utf8',
);

describe('guest payment proof storage policy', () => {
  it('allows only anon uploads scoped to an unexpired guest token path', () => {
    expect(policy).toContain('FOR INSERT\nTO anon');
    expect(policy).toContain("auth.role() <> 'anon'");
    expect(policy).toContain("array_length(string_to_array(p_object_name, '/'), 1) <> 4");
    expect(policy).toContain("length(v_token_hash) <> 64");
    expect(policy).toContain('o.guest_access_token_hash = v_token_hash');
    expect(policy).toContain('o.guest_token_expires_at > now()');
    expect(policy).toContain("o.payment_method = 'TRANSFER'");
    expect(policy).toContain("o.buyer_id IS NULL");
  });

  it('does not grant anonymous read or update access', () => {
    expect(policy).not.toMatch(/FOR SELECT\s+TO anon/i);
    expect(policy).not.toMatch(/FOR UPDATE\s+TO anon/i);
    expect(policy).toContain("GRANT EXECUTE ON FUNCTION public.can_guest_manage_payment_proof(text) TO anon");
  });
});
