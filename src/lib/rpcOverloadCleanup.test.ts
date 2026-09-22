import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

describe('RPC overload cleanup contract', () => {
  it('removes legacy quota overloads while preserving canonical wrappers', () => {
    const migration = readFileSync(
      resolve(process.cwd(), 'supabase/bootstrap/05_20260911110000_to_20260914150000.sql'),
      'utf8',
    );

    expect(migration).toContain('DROP FUNCTION IF EXISTS public.use_merchant_quota_v2(uuid, integer);');
    expect(migration).toContain('DROP FUNCTION IF EXISTS public.use_merchant_quota(uuid, integer);');
    expect(migration).toContain("NOTIFY pgrst, 'reload schema';");
  });
});
