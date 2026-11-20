import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import AdminQrisApplicationsPage from './AdminQrisApplicationsPage';

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
  rpc: vi.fn(),
  createSignedUrl: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: mocks.from,
    rpc: mocks.rpc,
    storage: { from: vi.fn(() => ({ createSignedUrl: mocks.createSignedUrl })) },
  },
}));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: 'admin-user' } }) }));
vi.mock('@/components/admin/AdminLayout', () => ({
  AdminLayout: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));
vi.mock('@/components/ui/ImageUpload', () => ({
  ImageUpload: ({ onChange }: { onChange: (value: string) => void }) => (
    <button type="button" onClick={() => onChange('qris/merchant-1.png')}>Pilih QRIS uji</button>
  ),
}));

function application(overrides: Record<string, unknown> = {}) {
  return {
    id: 'application-1',
    application_number: 'QR-TEST-001',
    merchant_id: 'merchant-1',
    applicant_user_id: 'merchant-user-1',
    default_bank_name: null,
    default_account_number: null,
    default_account_name: null,
    business_criteria_code: 'UMI',
    business_age_code: 'MORE_THAN_1_YEAR',
    qris_merchant_name_short: 'Toko Uji',
    qris_merchant_name: 'Toko Uji Sadesa',
    documents: {},
    status: 'APPROVED_PENDING_ISSUANCE',
    decision_note: null,
    qris_reference: null,
    qris_asset_key: null,
    gdc_merchant_id: null,
    gdc_account_number: null,
    gdc_mpm_enabled: false,
    submitted_at: '2026-11-20T00:00:00.000Z',
    revision_number: 1,
    merchant: { name: 'Toko Uji', city: 'Bandung' },
    ...overrides,
  };
}

function arrange(selectedApplication: ReturnType<typeof application>) {
  mocks.from.mockImplementation(() => ({
    select: vi.fn(() => ({ order: vi.fn().mockResolvedValue({ data: [selectedApplication], error: null }) })),
    update: vi.fn(() => ({ eq: vi.fn().mockResolvedValue({ error: null }) })),
  }));
  mocks.rpc.mockResolvedValue({ error: null });
  mocks.createSignedUrl.mockResolvedValue({ data: null, error: null });
  render(<AdminQrisApplicationsPage />);
}

async function selectApplication() {
  const applicationButton = await screen.findByRole('button', { name: /Toko Uji/ });
  await act(async () => {
    fireEvent.click(applicationButton);
    await new Promise((resolve) => setTimeout(resolve, 0));
  });
}

async function clickAndFlush(button: HTMLElement) {
  await act(async () => {
    fireEvent.click(button);
    await new Promise((resolve) => setTimeout(resolve, 0));
  });
}

describe('Admin QRIS GDC mapping controls', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('shows and submits MID/account during issuance so the required mapping can be saved', async () => {
    arrange(application());
    await selectApplication();

    fireEvent.change(await screen.findByLabelText('Nomor referensi QRIS'), { target: { value: 'REF-001' } });
    fireEvent.change(screen.getByLabelText('GDC Merchant ID (MID)'), { target: { value: 'MID-001' } });
    fireEvent.change(screen.getByLabelText('GDC Account Number'), { target: { value: '000123456789' } });
    fireEvent.click(screen.getByRole('button', { name: 'Pilih QRIS uji' }));
    await clickAndFlush(screen.getByRole('button', { name: 'Simpan QRIS — Menunggu Aktivasi' }));

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('admin_issue_qris_mpm', {
      p_application_id: 'application-1',
      p_qris_reference: 'REF-001',
      p_qris_asset_key: 'qris/merchant-1.png',
      p_gdc_merchant_id: 'MID-001',
      p_gdc_account_number: '000123456789',
    }));
  });

  it('lets admins activate dynamic MPM only through the explicit admin RPC', async () => {
    arrange(application({
      status: 'ACTIVE',
      gdc_merchant_id: 'MID-001',
      gdc_account_number: '000123456789',
      gdc_mpm_enabled: false,
    }));
    await selectApplication();
    const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(true);
    await clickAndFlush(await screen.findByRole('button', { name: 'Aktifkan QRIS Dinamis' }));

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('admin_set_qris_mpm_enabled', {
      p_application_id: 'application-1',
      p_enabled: true,
    }));
    expect(confirmSpy).toHaveBeenCalledWith(expect.stringContaining('Toko Uji'));
    confirmSpy.mockRestore();
  });

  it('requires the edited mapping to be saved before enabling dynamic MPM', async () => {
    arrange(application({
      status: 'ACTIVE',
      gdc_merchant_id: 'MID-OLD',
      gdc_account_number: '000111',
      gdc_mpm_enabled: false,
    }));
    await selectApplication();
    fireEvent.change(await screen.findByLabelText('GDC Merchant ID (MID)'), { target: { value: 'MID-NEW' } });

    expect(screen.getByRole('button', { name: 'Aktifkan QRIS Dinamis' })).toBeDisabled();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it('saves an updated active mapping through the RPC that disables it pending reverification', async () => {
    arrange(application({
      status: 'ACTIVE',
      gdc_merchant_id: 'MID-OLD',
      gdc_account_number: '000111',
      gdc_mpm_enabled: true,
    }));
    await selectApplication();
    fireEvent.change(await screen.findByLabelText('GDC Merchant ID (MID)'), { target: { value: 'MID-NEW' } });
    fireEvent.change(screen.getByLabelText('GDC Account Number'), { target: { value: '000222' } });
    await clickAndFlush(screen.getByRole('button', { name: 'Simpan Mapping (Dinamis Dinonaktifkan)' }));

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('admin_configure_qris_mpm', {
      p_application_id: 'application-1',
      p_gdc_merchant_id: 'MID-NEW',
      p_gdc_account_number: '000222',
    }));
  });
});
