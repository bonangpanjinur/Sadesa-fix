import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/126_20261014190000_to_20261014190000.sql'),
  'utf8',
);

describe('driver cancel ride safety contract', () => {
  it('allows cancellation only before pickup', () => {
    expect(migration).toContain("IF v_ride.status <> 'ACCEPTED' THEN");
    expect(migration).not.toContain("v_ride.status NOT IN ('ACCEPTED','PICKED_UP','IN_TRANSIT')");
    expect(migration).toContain('contact support for an in-flight incident');
  });

  it('keeps the RPC locked to authenticated callers', () => {
    expect(migration).toContain('SECURITY DEFINER');
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.driver_cancel_ride(uuid, text) FROM PUBLIC, anon;');
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.driver_cancel_ride(uuid, text) TO authenticated;');
  });
});
