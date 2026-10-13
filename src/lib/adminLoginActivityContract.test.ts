import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const migration = readFileSync(resolve(process.cwd(), 'archive/supabase/migrations/20261013140000_admin_login_activity.sql'), 'utf8');
const sourceMigration = readFileSync(resolve(process.cwd(), 'supabase/migrations/20261013140000_admin_login_activity.sql'), 'utf8');

describe('admin login activity contract', () => {
  it('keeps the deployable migration synchronized', () => {
    expect(sourceMigration).toBe(migration);
  });

  it('restricts reads and writes to admins', () => {
    expect(migration).toContain('USING (public.is_admin())');
    expect(migration).toContain('IF auth.uid() IS NULL OR NOT public.is_admin()');
    expect(migration).toContain('RETURN NULL;');
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.record_admin_login_activity');
  });
});
