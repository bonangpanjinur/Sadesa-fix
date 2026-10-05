import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { MemoryRouter } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { setLocale } from '@/lib/i18n';
import SettingsPage from './SettingsPage';

vi.mock('@/contexts/AuthContext', () => ({ useAuth: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: { auth: { updateUser: vi.fn() } },
}));
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }));
vi.mock('@/components/layout/Header', () => ({ Header: () => null }));
vi.mock('@/components/layout/BottomNav', () => ({ BottomNav: () => null }));
vi.mock('@/components/settings/PushNotificationSettings', () => ({ PushNotificationSettings: () => null }));

function renderSettings() {
  return render(
    <MemoryRouter>
      <SettingsPage />
    </MemoryRouter>,
  );
}

describe('SettingsPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    act(() => setLocale('id'));
    vi.mocked(useAuth).mockReturnValue({
      user: { id: 'user-1', email: 'user@example.test' },
      isCourier: false,
    } as ReturnType<typeof useAuth>);
    vi.mocked(supabase.auth.updateUser).mockResolvedValue({ data: { user: null }, error: null } as never);
  });

  it('does not offer a dark-mode switch', () => {
    renderSettings();

    expect(screen.queryByRole('switch', { name: 'Mode Gelap' })).not.toBeInTheDocument();
  });

  it('localizes the settings headings when the user selects English', () => {
    renderSettings();

    fireEvent.click(screen.getByRole('button', { name: 'English' }));

    expect(screen.getByRole('heading', { name: 'Settings' })).toBeInTheDocument();
    expect(screen.getByText('Language')).toBeInTheDocument();
    expect(screen.getByText('Privacy & Security')).toBeInTheDocument();
  });

  it('rejects a weak password before sending an update request', () => {
    renderSettings();
    fireEvent.click(screen.getByRole('button', { name: 'Ubah Password' }));
    fireEvent.change(screen.getByLabelText('Password Baru'), { target: { value: 'weakpass123' } });
    fireEvent.change(screen.getByLabelText('Konfirmasi Password'), { target: { value: 'weakpass123' } });
    fireEvent.click(screen.getByRole('button', { name: 'Simpan' }));

    expect(toast.error).toHaveBeenCalledWith(
      'Password harus minimal 8 karakter dan mengandung huruf besar, huruf kecil, serta angka.',
    );
    expect(supabase.auth.updateUser).not.toHaveBeenCalled();
  });

  it('updates the password and reports success for a valid password', async () => {
    renderSettings();
    fireEvent.click(screen.getByRole('button', { name: 'Ubah Password' }));
    fireEvent.change(screen.getByLabelText('Password Baru'), { target: { value: 'SecurePass123' } });
    fireEvent.change(screen.getByLabelText('Konfirmasi Password'), { target: { value: 'SecurePass123' } });
    fireEvent.click(screen.getByRole('button', { name: 'Simpan' }));

    await waitFor(() => expect(supabase.auth.updateUser).toHaveBeenCalledWith({ password: 'SecurePass123' }));
    expect(toast.success).toHaveBeenCalledWith('Password berhasil diubah');
    expect(screen.queryByLabelText('Password Baru')).not.toBeInTheDocument();
  });
});
