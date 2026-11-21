import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const worker = readFileSync(resolve(process.cwd(), 'supabase/functions/gdc-qris-reconcile/index.ts'), 'utf8');
const checkout = readFileSync(resolve(process.cwd(), 'supabase/functions/gdc-qris-mpm/index.ts'), 'utf8');
const shared = readFileSync(resolve(process.cwd(), 'supabase/functions/_shared/gdcSnap.ts'), 'utf8');
const migration = readFileSync(resolve(process.cwd(), 'supabase/bootstrap/147_20261121112000_gdc_qris_mpm_worker_schedule.sql'), 'utf8');
const settlementMigration = readFileSync(resolve(process.cwd(), 'supabase/bootstrap/149_20261121123000_gdc_qris_mpm_settlement_lifecycle.sql'), 'utf8');

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
    expect(worker).toContain('p_external_id: payment.external_id');
    expect(worker).toContain('p_currency: "IDR"');
    expect(worker).toContain('setTimeout(resolve, 100)');
  });

  it('passes the complete settlement identity from the MPM handler', () => {
    expect(checkout).toContain('p_external_id: existingPayment.external_id');
    expect(checkout).toContain('p_currency: existingPayment.currency');
  });

  it('settles paid marketplace orders to the database-supported PROCESSED lifecycle', () => {
    expect(settlementMigration).toContain("SET payment_status = 'PAID'");
    expect(settlementMigration).toContain("THEN 'PROCESSED'");
    expect(settlementMigration).not.toContain("THEN 'CONFIRMED'");
    expect(settlementMigration).toContain("p_currency <> 'IDR'");
    expect(settlementMigration).toContain('v_payment.amount IS DISTINCT FROM p_paid_amount');
    expect(settlementMigration).toContain('v_order.total IS DISTINCT FROM p_paid_amount');
    expect(settlementMigration).toContain("v_payment.status = 'PAID' AND v_order.payment_status = 'PAID'");
  });

  it('keeps GDC signing and token exchange in the shared module', () => {
    expect(worker).toContain('../_shared/gdcSnap.ts');
    expect(checkout).toContain('../_shared/gdcSnap.ts');
    expect(shared).toContain('RSASSA-PKCS1-v1_5');
    expect(shared).toContain('HMAC');
    expect(worker).not.toContain('crypto.subtle.sign');
    expect(checkout).not.toContain('crypto.subtle.sign');
  });

  it('uses a provider-query grace period before expiry and schedules pg_net', () => {
    expect(migration).toContain("interval '15 minutes'");
    expect(migration).toContain('net.http_post');
    expect(migration).toContain('GDC_RECONCILE_CRON_SECRET');
    expect(migration).toContain('gdc-qris-reconcile');
  });
  it('processes the oldest pending payments first so a backlog cannot starve rows', () => {
    expect(worker).toContain('.order("updated_at", { ascending: true })');
  });

  it('keeps checking recently expired payments and flags late payments on dead orders for refund review', () => {
    expect(worker).toContain('.eq("status", "EXPIRED")');
    expect(worker).toContain('LATE_PAYMENT_WINDOW_HOURS = 24');
    expect(worker).toContain('PAID_AFTER_EXPIRY_NEEDS_REVIEW');
    expect(worker).toContain('settleError.code === "22023"');
    // A late payment must never be settled outside the canonical RPC.
    expect(worker).not.toMatch(/orders["']\)\.update\(\{[^}]*payment_status/);
  });
});
