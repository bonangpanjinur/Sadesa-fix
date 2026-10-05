import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migrationPath = 'supabase/bootstrap/76_20261005130000_merchant_order_summary_rpc.sql';
const migration = readFileSync(resolve(process.cwd(), migrationPath), 'utf8');
const manifest = JSON.parse(readFileSync(resolve(process.cwd(), 'supabase/bootstrap/manifest.json'), 'utf8')) as {
  bundles: Array<{ file: string; source_files: string[] }>;
};

describe('merchant order summary RPC migration', () => {
  it('registers the summary RPC and refreshes PostgREST schema metadata', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.merchant_order_summary(p_merchant_id uuid)');
    expect(migration).toContain('RETURNS TABLE(');
    expect(migration).toContain("NOTIFY pgrst, 'reload schema'");
    expect(manifest.bundles).toContainEqual(expect.objectContaining({
      file: '76_20261005130000_merchant_order_summary_rpc.sql',
      source_files: ['76_20261005130000_merchant_order_summary_rpc.sql'],
    }));
  });

  it('keeps summary reads scoped to the authenticated merchant owner', () => {
    expect(migration).toContain('SECURITY DEFINER');
    expect(migration).toContain('m.id = p_merchant_id');
    expect(migration).toContain('m.user_id = auth.uid()');
    expect(migration).toContain("REVOKE ALL ON FUNCTION public.merchant_order_summary(uuid) FROM PUBLIC, anon");
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.merchant_order_summary(uuid) TO authenticated');
  });
});
