import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import { MerchantQrisApplicationCard } from './MerchantQrisApplicationCard';

const mocks = vi.hoisted(() => ({
  maybeSingle: vi.fn(),
  upload: vi.fn(),
  remove: vi.fn(),
  toastError: vi.fn(),
  toastSuccess: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: vi.fn(() => ({
      select: vi.fn(() => ({
        eq: vi.fn(() => ({
          order: vi.fn(() => ({
            limit: vi.fn(() => ({ maybeSingle: mocks.maybeSingle })),
          })),
        })),
      })),
    })),
    storage: { from: vi.fn(() => ({ upload: mocks.upload, remove: mocks.remove })) },
  },
}));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: 'merchant-user-1' } }) }));
vi.mock('sonner', () => ({ toast: { error: mocks.toastError, success: mocks.toastSuccess } }));

const merchantProps = {
  merchantId: 'merchant-1',
  merchantName: 'Toko Uji',
  bankName: 'BCA',
  accountNumber: '1234567890',
  accountName: 'Pemilik Toko',
};

function renderCard() {
  return render(<MerchantQrisApplicationCard {...merchantProps} />);
}

describe('Merchant dynamic QRIS document upload', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.maybeSingle.mockResolvedValue({ data: null, error: null });
    mocks.upload.mockResolvedValue({ error: null });
    mocks.remove.mockResolvedValue({ error: null });
  });

  it('keeps the form rendered and shows the selected photo name', async () => {
    renderCard();
    const input = await screen.findByLabelText('Foto KTP Pemilik');
    const photo = new File(['valid-jpeg'], 'ktp-pemilik.jpg', { type: 'image/jpeg' });

    fireEvent.change(input, { target: { files: [photo] } });

    expect(screen.getByRole('heading', { name: 'Pengajuan QRIS Dinamis GDC' })).toBeInTheDocument();
    expect(screen.getByText('ktp-pemilik.jpg')).toBeInTheDocument();
    expect(mocks.upload).not.toHaveBeenCalled();
  });

  it('rejects unsupported and oversized photos before they can start an upload', async () => {
    renderCard();
    const input = await screen.findByLabelText('Foto Produk') as HTMLInputElement;

    fireEvent.change(input, { target: { files: [new File(['heic'], 'produk.heic', { type: 'image/heic' })] } });
    expect(mocks.toastError).toHaveBeenCalledWith('Dokumen harus berupa JPG atau PNG.');
    expect(input.value).toBe('');

    const oversizedPhoto = new File([new Uint8Array(2 * 1024 * 1024 + 1)], 'produk-besar.jpg', { type: 'image/jpeg' });
    fireEvent.change(input, { target: { files: [oversizedPhoto] } });
    expect(mocks.toastError).toHaveBeenCalledWith('Ukuran setiap dokumen maksimal 2 MB. Pilih foto yang lebih kecil.');
    expect(input.value).toBe('');
    expect(screen.getByRole('heading', { name: 'Pengajuan QRIS Dinamis GDC' })).toBeInTheDocument();
    expect(mocks.upload).not.toHaveBeenCalled();
  });

  it('does not offer a new application when loading existing status fails, and allows retry', async () => {
    mocks.maybeSingle
      .mockResolvedValueOnce({ data: null, error: new Error('offline') })
      .mockResolvedValueOnce({ data: null, error: null });
    renderCard();

    expect(await screen.findByRole('alert')).toHaveTextContent('Formulir dinonaktifkan');
    expect(screen.queryByLabelText('Foto KTP Pemilik')).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Coba muat ulang' }));

    expect(await screen.findByLabelText('Foto KTP Pemilik')).toBeInTheDocument();
  });

  it('cleans up only the new upload after Storage failure and leaves correction form usable', async () => {
    mocks.maybeSingle.mockResolvedValue({
      data: {
        id: 'application-1', application_number: 'QR-001', status: 'NEEDS_CORRECTION',
        business_criteria_code: 'UMI', business_age_code: '1_TO_3_YEARS',
        qris_merchant_name_short: 'Toko Uji', qris_merchant_name: 'Toko Uji',
        documents: {
          OWNER_ID: 'merchant-user-1/application-1/owner_id-existing.jpg',
          OWNER_SELFIE: 'merchant-user-1/application-1/selfie-existing.jpg',
          BUSINESS_LOCATION: 'merchant-user-1/application-1/location-existing.jpg',
          PRODUCT: 'merchant-user-1/application-1/product-existing.jpg',
        },
        decision_note: 'Foto KTP perlu diperbarui.', submitted_at: '2026-01-01T00:00:00.000Z', revision_number: 1,
      },
      error: null,
    });
    mocks.upload.mockResolvedValue({ error: new Error('Storage unavailable') });
    renderCard();
    const input = await screen.findByLabelText('Foto KTP Pemilik');
    fireEvent.change(input, { target: { files: [new File(['replacement'], 'ktp-baru.jpg', { type: 'image/jpeg' })] } });
    fireEvent.click(screen.getByRole('button', { name: 'Kirim Perbaikan' }));

    await waitFor(() => expect(mocks.remove).toHaveBeenCalledTimes(1));
    const removedPaths = mocks.remove.mock.calls[0][0] as string[];
    expect(removedPaths).toHaveLength(1);
    expect(removedPaths[0]).toMatch(/^merchant-user-1\/application-1\/owner_id-[0-9a-f-]+\.jpg$/i);
    expect(removedPaths).not.toContain('merchant-user-1/application-1/owner_id-existing.jpg');
    expect(mocks.toastError).toHaveBeenCalledWith('Storage unavailable');
    expect(screen.getByRole('button', { name: 'Kirim Perbaikan' })).toBeEnabled();
    expect(screen.getByRole('heading', { name: 'Pengajuan QRIS Dinamis GDC' })).toBeInTheDocument();
  });
});
