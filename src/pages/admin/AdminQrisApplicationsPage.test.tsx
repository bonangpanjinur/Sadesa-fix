import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import AdminQrisApplicationsPage from './AdminQrisApplicationsPage';

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
  rpc: vi.fn(),
  invoke: vi.fn(),
  createSignedUrl: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: mocks.from,
    rpc: mocks.rpc,
    functions: { invoke: mocks.invoke },
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
  mocks.invoke.mockResolvedValue({ data: { status: 'PREVIEW', amount: 1000, currency: 'IDR', qr_content: 'sandbox-emv-payload', reference_no: 'sandbox-ref-1' }, error: null });
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

  it('groups unresolved internal stages under the four agreed display statuses', async () => {
    arrange(application({ status: 'SUBMITTED' }));

    expect((await screen.findAllByText('Menunggu Aktivasi Admin')).length).toBeGreaterThan(0);
    expect(screen.getByRole('option', { name: 'Perlu Perbaikan' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Ditolak' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'QRIS Aktif' })).toBeInTheDocument();
    expect(screen.getAllByRole('option')).toHaveLength(5);
  });

  it('saves the manually GDC-approved MID/account before admin activation', async () => {
    arrange(application());
    await selectApplication();

    fireEvent.change(screen.getByLabelText('GDC Merchant ID (MID)'), { target: { value: 'MID-001' } });
    fireEvent.change(screen.getByLabelText('GDC Account Number'), { target: { value: '000123456789' } });
    await clickAndFlush(screen.getByRole('button', { name: 'Simpan Data GDC — Menunggu Aktivasi Admin' }));

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('admin_configure_qris_mpm', {
      p_application_id: 'application-1',
      p_gdc_merchant_id: 'MID-001',
      p_gdc_account_number: '000123456789',
    }));
  });

  it('activates dynamic MPM with the admin RPC after the GDC mapping is saved', async () => {
    arrange(application({
      status: 'ISSUED_PENDING_ACTIVATION',
      gdc_merchant_id: 'MID-001',
      gdc_account_number: '000123456789',
    }));
    await selectApplication();
    await clickAndFlush(await screen.findByRole('button', { name: 'Aktifkan QRIS Dinamis' }));

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('admin_activate_qris', {
      p_application_id: 'application-1',
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

  it('lets admins save the GDC mapping while QRIS is pending activation without enabling dynamic MPM', async () => {
    arrange(application({ status: 'ISSUED_PENDING_ACTIVATION' }));
    await selectApplication();

    fireEvent.change(await screen.findByLabelText('GDC Merchant ID (MID)'), { target: { value: 'MID-PENDING' } });
    fireEvent.change(screen.getByLabelText('GDC Account Number'), { target: { value: '000333' } });
    await clickAndFlush(screen.getByRole('button', { name: 'Simpan Mapping (MPM tetap nonaktif)' }));

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('admin_configure_qris_mpm', {
      p_application_id: 'application-1',
      p_gdc_merchant_id: 'MID-PENDING',
      p_gdc_account_number: '000333',
    }));
    expect(mocks.rpc).not.toHaveBeenCalledWith('admin_set_qris_mpm_enabled', expect.anything());
  });

  it('previews dynamic QR through the sandbox for a saved mapping before activation', async () => {
    arrange(application({
      status: 'ISSUED_PENDING_ACTIVATION',
      gdc_merchant_id: 'MID-SANDBOX',
      gdc_account_number: '000123456789',
    }));
    await selectApplication();
    await clickAndFlush(await screen.findByRole('button', { name: 'Buat QR Uji Sandbox · Rp1.000' }));

    await waitFor(() => expect(mocks.invoke).toHaveBeenCalledWith('gdc-qris-mpm', {
      body: { action: 'admin_preview', application_id: 'application-1' },
    }));
    expect(await screen.findByLabelText('QRIS dinamis sandbox Toko Uji')).toBeInTheDocument();
    expect(screen.getByText('QR UJI SANDBOX — JANGAN DIBAYAR')).toBeInTheDocument();
    expect(screen.getByText(/Referensi sandbox: sandbox-ref-1/)).toBeInTheDocument();
  });
});
