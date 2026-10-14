import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/127_20261014200000_payment_fare_hardening.sql'),
  'utf8',
);
const paymentPage = readFileSync(resolve(process.cwd(), 'src/pages/PaymentConfirmationPage.tsx'), 'utf8');
const courierPage = readFileSync(resolve(process.cwd(), 'src/pages/transport/CourierBookingPage.tsx'), 'utf8');
const ridePage = readFileSync(resolve(process.cwd(), 'src/pages/ride/RideBookingPage.tsx'), 'utf8');
const adminApprovalPage = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminApprovalCenterPage.tsx'), 'utf8');
const adminRefundsPage = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminRefundsPage.tsx'), 'utf8');

describe('payment and fare audit hardening contracts', () => {
  it('removes direct authenticated order writes and legacy insert/update policies', () => {
    expect(migration).toContain("AND cmd IN ('INSERT', 'UPDATE')");
    expect(migration).toContain('REVOKE INSERT, UPDATE ON public.orders FROM PUBLIC, anon, authenticated');
  });

  it('gives transfer orders deadlines, blocks late proof/payment and releases reserved inventory atomically', () => {
    expect(migration).toContain("NEW.confirmation_deadline := now() + interval '30 minutes'");
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.expire_pending_marketplace_payments');
    expect(migration).toContain('FOR UPDATE SKIP LOCKED');
    expect(migration).toContain("SET status = 'expired', released_at = now()");
    expect(migration).toContain("payment_status = 'EXPIRED'");
    expect(migration).toContain('Payment confirmation deadline has expired');
  });

  it('uses immutable delivery-fee and payment-destination snapshots', () => {
    expect(migration).toContain('courier_delivery_fee_snapshot');
    expect(migration).toContain('ADD COLUMN IF NOT EXISTS payment_destination_snapshot jsonb');
    expect(migration).toContain('o.courier_delivery_fee_snapshot::bigint');
    expect(migration).toContain("'source', 'ADMIN'");
    expect(paymentPage).toContain('payment_destination_snapshot');
    expect(paymentPage).not.toContain("from('app_settings').select('value').eq('key', 'admin_payment_info')");
  });

  it('requires provider reference, provider status and exact amount before refund completion', () => {
    expect(migration).toContain('refund_settlements_provider_reference_unique');
    expect(migration).toContain("v_status <> 'SUCCEEDED'");
    expect(migration).toContain('p_provider_amount <> v_settlement.amount');
    expect(migration).toContain('provider_status = v_status, provider_amount = p_provider_amount');
    expect(migration).toContain('complete_refund_settlement(uuid, boolean, text, integer, text, text)');
  });

  it('routes legacy refund approvals through provider settlement and reports pending provider completion', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.decide_refund_request(');
    expect(migration).toContain('RETURN public.process_refund_decision(p_request_id, p_approve, p_notes)');
    expect(adminApprovalPage).toContain('Pencairan menunggu konfirmasi provider.');
    expect(adminRefundsPage).toContain('Pencairan menunggu konfirmasi provider.');
  });

  it('shows courier server amount and does not price by OSRM road distance', () => {
    expect(courierPage).toContain('const distanceKm = straightLineDistanceKm');
    expect(courierPage).toContain('shipping_cost?: number');
    expect(courierPage).toContain('Ongkos final server: Rp');
  });

  it('prices the ride preview by Haversine and reconciles the stored fare after create', () => {
    expect(ridePage).toContain('fareSettings.base_fare + straightLineDistanceKm * fareSettings.per_km_fare');
    expect(ridePage).toContain(".select('estimated_fare')");
    expect(ridePage).toContain('Tarif final: ${formatPrice(savedFare)}');
  });

  it('refreshes payment state and treats expired orders as terminal in the UI', () => {
    expect(paymentPage).toContain('loadOrderAndPaymentInfo(false)');
    expect(paymentPage).toContain("paymentStatus === 'EXPIRED'");
    expect(paymentPage).toContain('!isPaymentExpired && hasPaymentInstructions');
    expect(paymentPage).toContain('onUploaded={() => void loadOrderAndPaymentInfo(false)}');
  });
});
