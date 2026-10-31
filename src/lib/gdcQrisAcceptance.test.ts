import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(resolve(process.cwd(), path), 'utf8');
const migration = read('supabase/bootstrap/134_20261031220000_gdc_qris_dynamic_payment.sql');
const telemetry = read('supabase/bootstrap/135_20261031230000_gdc_qris_rollout_observability.sql');
const edge = read('supabase/functions/gdc-qris-payment/index.ts');
const checkout = read('src/pages/CheckoutPage.tsx');
const paymentPage = read('src/pages/GdcQrisPaymentPage.tsx');
const api = read('src/lib/gdcQrisApi.ts');

describe('GDC QRIS Fase 4-5 acceptance contract', () => {
  it('routes only an active merchant profile to GDC and preserves online fallback', () => {
    expect(checkout).toContain("eq('status', 'ACTIVE')");
    expect(checkout).toContain("onlineProvider === 'GDC'");
    expect(checkout).toContain('createPaymentInvoice');
    expect(checkout).toContain("/payment/gdc/");
  });

  it('keeps QR display and polling terminal-state aware', () => {
    expect(paymentPage).toContain('QRCodeSVG');
    expect(paymentPage).toContain('setInterval(() => void refresh(false), 5000)');
    expect(paymentPage).toContain("['SUCCEEDED', 'FAILED', 'EXPIRED']");
    expect(paymentPage).toContain('qr_image');
  });

  it('enforces server-side idempotency and payment fulfillment guards', () => {
    expect(migration).toContain('gdc_one_live_attempt_per_order_idx');
    expect(migration).toContain('reserve_gdc_qris_attempt');
    expect(migration).toContain('p_paid_amount <> v_attempt.amount');
    expect(migration).toContain("payment_status = 'PAID'");
    expect(edge).toContain('x-callback-token');
    expect(edge).toContain('process_gdc_qris_status');
  });

  it('records rollout metrics without leaking QR content or provider secrets', () => {
    expect(telemetry).toContain('get_gdc_qris_rollout_metrics');
    expect(telemetry).toContain('callback_rejected');
    expect(api).toContain("observe('payment', 'gdc_generate'");
    expect(api).toContain("observe('payment', 'gdc_query'");
    expect(telemetry).not.toContain('request_payload');
    expect(telemetry).not.toContain('response_payload');
  });
});
