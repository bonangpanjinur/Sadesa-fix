import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/40_20260925100000_service_transaction_state_machine.sql'),
  'utf8',
);
const servicesPage = readFileSync(resolve(process.cwd(), 'src/pages/ServicesPage.tsx'), 'utf8');
const requesterPage = readFileSync(resolve(process.cwd(), 'src/pages/ServiceRequestsPage.tsx'), 'utf8');
const providerPage = readFileSync(resolve(process.cwd(), 'src/pages/ServiceProviderHistoryPage.tsx'), 'utf8');
const adminPage = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminServicesPage.tsx'), 'utf8');
const disputesPage = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminServiceDisputesPage.tsx'), 'utf8');

describe('service marketplace transaction contract', () => {
  it('publishes profiles atomically and requires verification before booking', () => {
    expect(servicesPage).toContain("rpc('service_publish_profile'");
    expect(migration).toContain("verification_status = 'PENDING'");
    expect(migration).toContain("verification_status = 'VERIFIED'");
    expect(migration).toContain('REVOKE INSERT, UPDATE, DELETE ON public.service_profiles FROM authenticated');
  });

  it('keeps requester budget separate from the mutually accepted final price', () => {
    expect(migration).toContain('requester_budget numeric(14,2)');
    expect(migration).toContain("INSERT INTO public.service_requests");
    expect(migration).toContain("'NEGOTIATING'");
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.service_provider_propose_price');
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.service_requester_accept_price');
    expect(requesterPage).toContain("rpc('service_requester_accept_price'");
    expect(providerPage).toContain("rpc('service_provider_propose_price'");
  });

  it('requires both completion, verified payment, and an actual payout transfer reference', () => {
    expect(migration).toContain('v_request.requester_completed AND v_request.provider_completed');
    expect(migration).toContain('Actual bank transfer reference is required');
    expect(migration).toContain('external_transfer_reference = trim(p_external_transfer_reference)');
    expect(migration).toContain("REVOKE ALL ON FUNCTION public.service_admin_release_payout(uuid,text) FROM PUBLIC, anon, authenticated");
    expect(adminPage).toContain("p_external_transfer_reference: transferReference");
  });

  it('keeps refund approved separate from refund transfer reconciliation', () => {
    expect(migration).toContain('Actual refund transfer reference is required');
    expect(migration).toContain("status = 'COMPLETED', external_reference = trim(p_external_reference)");
    expect(migration).toContain("status = 'REFUNDED', admin_note = coalesce");
    expect(disputesPage).toContain("rpc('service_admin_record_refund'");
  });
});
