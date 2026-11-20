import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const regressionMigration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/140_20261120210000_gdc_qris_mpm_merchant_mapping_hardening.sql'),
  'utf8',
);
const adminMappingMigration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/141_20261120220000_gdc_qris_admin_mapping_controls.sql'),
  'utf8',
);
const pendingActivationMigration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/142_20261120230000_gdc_mapping_before_qris_activation.sql'),
  'utf8',
);
const edgeFunction = readFileSync(
  resolve(process.cwd(), 'supabase/functions/gdc-qris-mpm/index.ts'),
  'utf8',
);

describe('GDC QRIS admin mapping migration contract', () => {
  it('repairs the old insert guard that rejected every non-admin application insert', () => {
    expect(regressionMigration).toMatch(/IF TG_OP = 'INSERT' THEN\s+IF NOT public\.is_admin\(\) THEN/);
    expect(adminMappingMigration).toMatch(
      /IF TG_OP = 'INSERT' THEN[\s\S]*?NEW\.gdc_mpm_enabled IS TRUE[\s\S]*?AND NOT public\.is_admin\(\) THEN/,
    );
    expect(adminMappingMigration).toContain('NULLIF(trim(NEW.gdc_merchant_id), \'\') IS NOT NULL');
    expect(adminMappingMigration).toContain('NULLIF(trim(NEW.gdc_account_number), \'\') IS NOT NULL');
  });

  it('requires an active application and complete identity only when dynamic MPM is enabled', () => {
    expect(adminMappingMigration).toMatch(
      /IF NEW\.gdc_mpm_enabled IS TRUE\s+AND \(NEW\.status <> 'ACTIVE'[\s\S]*?gdc_merchant_id[\s\S]*?gdc_account_number[\s\S]*?THEN/,
    );
    expect(adminMappingMigration).toContain('ADD COLUMN IF NOT EXISTS gdc_mpm_enabled boolean NOT NULL DEFAULT false');
    expect(adminMappingMigration).toContain('BEFORE INSERT OR UPDATE OF gdc_merchant_id, gdc_account_number, gdc_mpm_enabled, status');
  });

  it('limits identity changes and activation controls to the protected admin RPCs', () => {
    expect(adminMappingMigration).toContain('IF NOT public.is_admin() THEN');
    expect(adminMappingMigration).toContain('CREATE OR REPLACE FUNCTION public.admin_configure_qris_mpm(');
    expect(adminMappingMigration).toContain('CREATE OR REPLACE FUNCTION public.admin_set_qris_mpm_enabled(');
    expect(adminMappingMigration).toContain('gdc_mpm_enabled = false');
    expect(adminMappingMigration).toContain('REVOKE ALL ON FUNCTION public.admin_set_qris_mpm_enabled(uuid, boolean) FROM PUBLIC, anon');
    expect(adminMappingMigration).toContain('GRANT EXECUTE ON FUNCTION public.admin_set_qris_mpm_enabled(uuid, boolean) TO authenticated');
  });

  it('uses only an explicitly enabled merchant mapping for GDC checkout', () => {
    expect(edgeFunction).toContain(".eq('merchant_id', order.merchant_id).eq('status', 'ACTIVE').eq('gdc_mpm_enabled', true)");
  });

  it('allows an admin to save mapping before static QRIS activation while forcing dynamic MPM off', () => {
    expect(pendingActivationMigration).toContain("v_application.status NOT IN ('ACTIVE', 'ISSUED_PENDING_ACTIVATION')");
    expect(pendingActivationMigration).toContain('gdc_mpm_enabled = false');
    expect(pendingActivationMigration).toContain("'status', v_application.status");
  });
});
