import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const migration = readFileSync(resolve(process.cwd(), 'archive/supabase/migrations/20261013140000_admin_login_activity.sql'), 'utf8');
const sourceMigration = readFileSync(resolve(process.cwd(), 'supabase/bootstrap/111_20261013140000_admin_login_activity.sql'), 'utf8');

describe('admin login activity contract', () => {
  it('keeps the deployable canonical bootstrap bundle aligned with the audited source', () => {
    expect(sourceMigration).toContain('CREATE TABLE IF NOT EXISTS public.admin_login_activity');
    expect(sourceMigration).toContain('CREATE OR REPLACE FUNCTION public.record_admin_login_activity');
    expect(sourceMigration).toContain('USING (public.is_admin())');
  });

  it('restricts reads and writes to admins', () => {
    expect(migration).toContain('USING (public.is_admin())');
    expect(migration).toContain('IF auth.uid() IS NULL OR NOT public.is_admin()');
    expect(migration).toContain('RETURN NULL;');
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.record_admin_login_activity');
  });
});
