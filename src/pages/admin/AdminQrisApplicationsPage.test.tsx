import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import type { ReactNode } from 'react';

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
  applications: [{
    id: 'application-1',
    application_number: 'QR-TEST-1',
    merchant_id: 'merchant-1',
    applicant_user_id: 'owner-1',
    default_bank_name: 'Bank Demo',
    default_account_number: '000111222',
    default_account_name: 'Toko Demo',
    business_criteria_code: 'UMI',
    business_age_code: 'LESS_THAN_1_YEAR',
    qris_merchant_name_short: 'TOKO DEMO',
    qris_merchant_name: 'TOKO DEMO TEST',
    documents: {},
    status: 'APPROVED_PENDING_ISSUANCE',
    decision_note: null,
    qris_reference: null,
    qris_asset_key: null,
    gdc_merchant_id: null,
    gdc_account_number: null,
    submitted_at: '2026-11-01T00:00:00Z',
    revision_number: 1,
    merchant: { name: 'Toko Demo', city: 'Kota Demo' },
  }],
}));

vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: 'admin-1' } }) }));
vi.mock('@/components/admin/AdminLayout', () => ({
  AdminLayout: ({ title, subtitle, children }: { title: string; subtitle: string; children: ReactNode }) => (
    <main><h1>{title}</h1><p>{subtitle}</p>{children}</main>
  ),
}));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => ({
      select: () => ({ order: async () => ({ data: mocks.applications, error: null }) }),
    }),
    storage: {
      from: () => ({ createSignedUrl: async () => ({ data: { signedUrl: 'https://example.test/doc' } }) }),
    },
    rpc: (name: string, args: unknown) => mocks.rpc(name, args),
  },
}));

import AdminQrisApplicationsPage from './AdminQrisApplicationsPage';

describe('Admin QR MPM issuance', () => {
  beforeEach(() => {
    mocks.rpc.mockReset();
    mocks.rpc.mockResolvedValue({ error: null });
  });

  it('issues a GDC QR MPM application without requiring a static QR upload', async () => {
    render(<AdminQrisApplicationsPage />);
    fireEvent.click(await screen.findByRole('button', { name: /Toko Demo/ }));

    fireEvent.change(await screen.findByLabelText('NMID / Merchant ID Neo-GDC'), { target: { value: 'NMID-123' } });
    fireEvent.change(screen.getByLabelText('Account Number GDC'), { target: { value: 'GDC-456' } });

    expect(screen.getByText(/Anda tidak perlu mengunggah QRIS statis/i)).toBeInTheDocument();
    expect(screen.queryByText('QRIS statis untuk merchant ini')).not.toBeInTheDocument();
    expect(screen.queryByText('Unggah QRIS statis merchant')).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Simpan Identitas GDC — Menunggu Aktivasi' }));

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('admin_issue_qris_mpm', expect.objectContaining({
      p_application_id: 'application-1',
      p_qris_reference: null,
      p_qris_asset_key: null,
      p_gdc_merchant_id: 'NMID-123',
      p_gdc_account_number: 'GDC-456',
    })));
  });
});
