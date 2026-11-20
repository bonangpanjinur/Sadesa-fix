import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const source = readFileSync(resolve(process.cwd(), 'supabase/functions/gdc-qris-mpm/index.ts'), 'utf8');
const previewBranch = source.split("if (input.action === 'admin_preview') {")[1]?.split("if (!input.order_id")[0] ?? '';

describe('GDC QRIS MPM admin preview safety contract', () => {
  it('requires the sandbox GDC host and an authenticated admin', () => {
    expect(previewBranch).toContain('GDC_SANDBOX_HOST');
    expect(previewBranch).toContain('userClient.rpc(\'is_admin\')');
    expect(previewBranch).toContain('isAdmin !== true');
    expect(previewBranch).toContain('input.application_id');
  });

  it('uses a fixed Rp1,000 IDR amount and returns a preview-only response', () => {
    expect(previewBranch).toContain('const amount = 1000;');
    expect(previewBranch).toContain("currency: 'IDR'");
    expect(previewBranch).toContain("status: 'PREVIEW'");
    expect(previewBranch).toContain('gdcPost(credentials, API_PATHS.generate');
  });

  it('does not create or update orders or persisted payment rows in the preview branch', () => {
    expect(previewBranch).not.toMatch(/\.from\(['"]orders['"]\)/);
    expect(previewBranch).not.toMatch(/\.from\(['"]gdc_qris_mpm_payments['"]\)/);
    expect(previewBranch).not.toMatch(/\.insert\s*\(/);
    expect(previewBranch).not.toMatch(/\.update\s*\(/);
  });
});
