import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const worker = readFileSync(resolve(process.cwd(), 'supabase/functions/gdc-qris-reconcile/index.ts'), 'utf8');
const migration = readFileSync(resolve(process.cwd(), 'supabase/bootstrap/147_20261121112000_gdc_qris_mpm_worker_schedule.sql'), 'utf8');

describe('GDC QRIS MPM reconciliation worker contract', () => {
  it('authenticates with dedicated CRON_SECRET rather than service-role JWT', () => {
    expect(worker).toContain('Deno.env.get("CRON_SECRET")');
    expect(worker).toContain('x-cron-secret');
    expect(worker).not.toContain('auth !== `Bearer ${serviceRoleKey}`');
  });

  it('queries GDC in bounded batches and settles through the canonical RPC', () => {
    expect(worker).toContain('QUERY_PATH = "/v1.0/qr/qr-mpm-query"');
    expect(worker).toContain('.limit(20)');
    expect(worker).toContain('settle_gdc_qris_mpm_payment');
    expect(worker).toContain('setTimeout(resolve, 100)');
  });

  it('uses a provider-query grace period before expiry and schedules pg_net', () => {
    expect(migration).toContain("interval '15 minutes'");
    expect(migration).toContain('net.http_post');
    expect(migration).toContain('GDC_RECONCILE_CRON_SECRET');
    expect(migration).toContain('gdc-qris-reconcile');
  });
});
