import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const source = readFileSync(resolve(process.cwd(), 'supabase/functions/gdc-qris-mpm/index.ts'), 'utf8');
const supabaseConfig = readFileSync(resolve(process.cwd(), 'supabase/config.toml'), 'utf8');
const previewBranch = source.split("if (input.action === 'admin_preview') {")[1]?.split("if (!input.order_id")[0] ?? '';
const authGuard = source.split("const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';")[1]?.split('const admin = createClient')[0] ?? '';

describe('GDC QRIS MPM admin preview safety contract', () => {
  it('requires the sandbox GDC host and an authenticated admin', () => {
    expect(previewBranch).toContain('GDC_SANDBOX_HOST');
    expect(previewBranch).toContain('userClient.rpc(\'is_admin\')');
    expect(previewBranch).toContain('isAdmin !== true');
    expect(previewBranch).toContain('input.application_id');
  });

  it('distinguishes missing Supabase runtime configuration from an invalid user session', () => {
    expect(authGuard).toContain('Supabase runtime configuration is incomplete');
    expect(authGuard).toContain('Konfigurasi runtime Supabase Edge Function belum lengkap.');
    expect(authGuard).toContain('Sesi login tidak ditemukan.');
    expect(authGuard).toContain('Sesi login tidak valid atau kedaluwarsa.');
    expect(authGuard).not.toContain("{ error: 'Unauthorized' }");
  });

  it('keeps gateway JWT verification enabled for the user-authenticated function', () => {
    expect(supabaseConfig).toMatch(/\[functions\.gdc-qris-mpm\][\s\S]*?verify_jwt = true/);
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
