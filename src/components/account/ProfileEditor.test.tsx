import { render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { ProfileEditor } from './ProfileEditor';

vi.mock('@/components/AddressSelector', () => ({
  AddressSelector: () => null,
  formatFullAddress: () => '',
  createEmptyAddressData: () => ({
    province: '',
    provinceName: '',
    city: '',
    cityName: '',
    district: '',
    districtName: '',
    village: '',
    villageName: '',
    detail: '',
  }),
}));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: { storage: { from: vi.fn() }, from: vi.fn() },
}));
vi.mock('@/hooks/use-toast', () => ({ toast: vi.fn() }));

describe('ProfileEditor accessibility', () => {
  it('associates visible labels with profile inputs and names the avatar upload button', () => {
    render(
      <ProfileEditor
        userId="user-1"
        initialData={{ full_name: 'Ayu', phone: '081234567890', address: null }}
        onSave={vi.fn()}
        onCancel={vi.fn()}
      />,
    );

    expect(screen.getByLabelText('Nama Lengkap')).toHaveValue('Ayu');
    expect(screen.getByLabelText(/No\. WhatsApp/)).toHaveValue('0812-3456-7890');
    expect(screen.getByRole('button', { name: 'Unggah foto profil' })).toBeInTheDocument();
  });
});
