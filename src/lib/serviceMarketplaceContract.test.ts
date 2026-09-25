import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/40_20260925100000_service_transaction_state_machine.sql'),
  'utf8',
);
const servicesPage = readFileSync(resolve(process.cwd(), 'src/pages/ServicesPage.tsx'), 'utf8');
const accountPage = readFileSync(resolve(process.cwd(), 'src/pages/AccountPage.tsx'), 'utf8');
const providerRegistration = readFileSync(resolve(process.cwd(), 'src/components/account/ServiceProviderRegistration.tsx'), 'utf8');
const requesterPage = readFileSync(resolve(process.cwd(), 'src/pages/ServiceRequestsPage.tsx'), 'utf8');
const providerPage = readFileSync(resolve(process.cwd(), 'src/pages/ServiceProviderHistoryPage.tsx'), 'utf8');
const adminPage = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminServicesPage.tsx'), 'utf8');
const disputesPage = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminServiceDisputesPage.tsx'), 'utf8');

describe('service marketplace transaction contract', () => {
  it('publishes profiles atomically and requires verification before booking', () => {
    expect(providerRegistration).toContain("rpc('service_publish_profile'");
    expect(migration).toContain("verification_status = 'PENDING'");
    expect(migration).toContain("verification_status = 'VERIFIED'");
    expect(migration).toContain('REVOKE INSERT, UPDATE, DELETE ON public.service_profiles FROM authenticated');
  });

  it('registers providers from their existing account and routes referrals to scoped verifiers', () => {
    const onboardingMigration = readFileSync(
      resolve(process.cwd(), 'supabase/bootstrap/43_20260925130000_service_payment_proof_isolation.sql'),
      'utf8',
    );
    const verifierPage = readFileSync(resolve(process.cwd(), 'src/pages/verifikator/VerifikatorServiceProvidersPage.tsx'), 'utf8');
    const appRouter = readFileSync(resolve(process.cwd(), 'src/App.tsx'), 'utf8');
    expect(providerRegistration).toContain('p_verifikator_code: referralCode || null');
    expect(accountPage).toContain('ServiceProviderRegistration');
    expect(providerRegistration).toContain("queryKey: ['service-provider-application', userId]");
    expect(onboardingMigration).toContain('CREATE OR REPLACE FUNCTION public.service_publish_profile(');
    expect(onboardingMigration).toContain('IF auth.uid() IS NULL THEN RAISE EXCEPTION');
    expect(onboardingMigration).toContain('Referral code is invalid or inactive');
    expect(onboardingMigration).toContain('code.verifikator_id = auth.uid()');
    expect(onboardingMigration).toContain("VALUES (v_profile.provider_id, 'service_provider')");
    expect(verifierPage).toContain("'service_admin_review_provider'");
    expect(appRouter).toContain('path="/verifikator/service-providers"');
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

  it('enforces provider minimum tariff and reads the admin fee policy server-side', () => {
    const financeMigration = readFileSync(
      resolve(process.cwd(), 'supabase/bootstrap/42_20260925120000_service_finance_controls.sql'),
      'utf8',
    );
    expect(financeMigration).toContain('v_profile.min_price');
    expect(financeMigration).toContain('Price cannot be below provider minimum tariff');
    expect(financeMigration).toContain("WHERE key = 'service_platform_fee'");
    const serviceFinanceMigration = readFileSync(
      resolve(process.cwd(), 'supabase/bootstrap/43_20260925130000_service_payment_proof_isolation.sql'),
      'utf8',
    );
    expect(serviceFinanceMigration).toContain("WHERE key = 'service_platform_fee'");
    expect(financeMigration).toContain('p_agreed_price * v_fee_percent / 100');
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

  it('binds proof objects to the requester and uses a dedicated fee key', () => {
    const hardeningMigration = readFileSync(
      resolve(process.cwd(), 'supabase/bootstrap/43_20260925130000_service_payment_proof_isolation.sql'),
      'utf8',
    );
    expect(hardeningMigration).toContain('can_manage_service_payment_proof');
    expect(hardeningMigration).toContain('request.requester_id = auth.uid()');
    expect(hardeningMigration).toContain('v_path_request_id <> p_request_id');
    expect(hardeningMigration).toContain('proof.proof_path = p_object_name');
    expect(hardeningMigration).toContain('idx_service_payment_proofs_active_transfer_reference');
    expect(hardeningMigration).toContain("WHERE key = 'service_platform_fee'");
    expect(hardeningMigration).toContain('Payout was already released with a different transfer reference');
    expect(adminPage).toContain("['service_platform_fee', 'admin_payment_info']");
    expect(adminPage).not.toContain("key: 'platform_fee'");
  });
});
