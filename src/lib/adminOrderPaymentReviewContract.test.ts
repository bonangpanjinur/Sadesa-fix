import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/82_20261006170000_admin_order_payment_review.sql'),
  'utf8',
);

describe('admin order payment review contract', () => {
  it('restricts payment rejection to authenticated admins and requires a reason', () => {
    expect(migration).toContain('SECURITY DEFINER');
    expect(migration).toContain('auth.uid() IS NULL OR NOT public.is_admin()');
    expect(migration).toContain('char_length(v_reason) < 3 OR char_length(v_reason) > 1000');
    expect(migration).toContain('FROM PUBLIC, anon, authenticated');
    expect(migration).toContain('TO authenticated');
  });

  it('requires an uploaded transfer proof, audits rejection, and preserves the pending order for retry', () => {
    expect(migration).toContain("v_order.payment_method IS DISTINCT FROM 'TRANSFER'");
    expect(migration).toContain('v_order.payment_proof_url');
    expect(migration).toContain("SET payment_status = 'FAILED'");
    expect(migration).toContain("'payment_proof_rejected'");
    expect(migration).toContain("jsonb_build_object('reason', v_reason)");
    expect(migration).toContain("'PENDING_TRANSFER'");
    expect(migration).toContain('Payment proof was rejected; a new proof is required');
  });
});
