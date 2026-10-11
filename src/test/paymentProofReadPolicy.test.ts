import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/104_20261011234500_fix_payment_proof_read_policy.sql'),
  'utf8',
);

describe('payment proof read policy repair', () => {
  it('resolves access from the order path and merchant ownership', () => {
    expect(migration).toContain("split_part(p_object_name, '/', 1) <> 'orders'");
    expect(migration).toContain('o.buyer_id = auth.uid()');
    expect(migration).toContain('m.id = o.merchant_id');
    expect(migration).toContain('m.user_id = auth.uid()');
    expect(migration).toContain('public.is_admin()');
  });

  it('binds the storage policy to the object name', () => {
    expect(migration).toContain('bucket_id = \'payment-proofs\'');
    expect(migration).toContain('public.can_access_payment_proof(name)');
    expect(migration).not.toContain('storage.foldername(m.name)');
    expect(migration).toContain('DROP POLICY IF EXISTS "Buyer/merchant/admin can view payment proofs"');
  });
});
