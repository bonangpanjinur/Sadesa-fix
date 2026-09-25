import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/41_20260925110000_service_ledger_rental_notifications.sql'),
  'utf8',
);
const servicesPage = readFileSync(resolve(process.cwd(), 'src/pages/ServicesPage.tsx'), 'utf8');
const requesterPage = readFileSync(resolve(process.cwd(), 'src/pages/ServiceRequestsPage.tsx'), 'utf8');

describe('service marketplace enhancement contract', () => {
  it('adds independent domain status and authoritative immutable ledger', () => {
    expect(migration).toContain('service_transaction_ledger');
    expect(migration).toContain('service_ledger_immutable');
    expect(migration).toContain('payment_status text');
    expect(migration).toContain('work_status text');
    expect(migration).toContain('payout_status text');
  });

  it('supports rental dates, deposit, late fee, and handover condition', () => {
    expect(migration).toContain('service_create_request_v2');
    expect(migration).toContain('rental_start_at');
    expect(migration).toContain('rental_end_at');
    expect(migration).toContain('rental_deposit');
    expect(migration).toContain('rental_late_fee_per_day');
    expect(servicesPage).toContain("p_service_type: offer.service_type");
    expect(requesterPage).toContain("request.service_type === 'RENTAL'");
  });

  it('emits in-app notifications from transaction events', () => {
    expect(migration).toContain('service_emit_notification');
    expect(migration).toContain('trg_service_request_events');
    expect(migration).toContain('trg_service_payment_events');
    expect(migration).toContain('trg_service_payout_events');
  });

  it('provides deterministic SLA timeout sweep', () => {
    expect(migration).toContain('service_run_sla_sweep');
    expect(migration).toContain('NEGOTIATION_TIMEOUT');
    expect(migration).toContain('PAYMENT_TIMEOUT');
    expect(migration).toContain("status = 'CANCELLED'");
  });
});
