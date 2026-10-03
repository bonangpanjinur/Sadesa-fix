import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { useAuth } from '@/contexts/AuthContext';
import {
  getPushPermission,
  getSubscriptionStatus,
  isPushSupported,
  subscribeToPush,
  unsubscribeFromPush,
} from '@/lib/pushNotification';
import { toast } from 'sonner';
import { setLocale } from '@/lib/i18n';
import { PushNotificationSettings } from './PushNotificationSettings';

vi.mock('@/contexts/AuthContext', () => ({ useAuth: vi.fn() }));
vi.mock('@/lib/pushNotification', () => ({
  getLastPushError: vi.fn(),
  isPushSupported: vi.fn(),
  getPushPermission: vi.fn(),
  subscribeToPush: vi.fn(),
  unsubscribeFromPush: vi.fn(),
  getSubscriptionStatus: vi.fn(),
}));
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }));

describe('PushNotificationSettings', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    setLocale('id');
    vi.mocked(useAuth).mockReturnValue({
      user: { id: 'user-1', email: 'user@example.test' },
    } as ReturnType<typeof useAuth>);
    vi.mocked(isPushSupported).mockResolvedValue(true);
    vi.mocked(getPushPermission).mockResolvedValue('granted');
    vi.mocked(subscribeToPush).mockResolvedValue(true);
    vi.mocked(unsubscribeFromPush).mockResolvedValue(false);
  });

  it('shows a retryable error if stored push status cannot be checked', async () => {
    vi.mocked(getSubscriptionStatus)
      .mockRejectedValueOnce(new Error('temporary lookup failure'))
      .mockResolvedValueOnce(true);
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});

    render(<PushNotificationSettings />);

    const retryButton = await screen.findByRole('button', { name: 'Coba lagi' });
    expect(screen.getByRole('alert')).toHaveTextContent('Status notifikasi belum dapat diperiksa.');
    fireEvent.click(retryButton);

    await waitFor(() => expect(screen.getByRole('switch', { name: 'Notifikasi Push' })).toBeChecked());
    consoleError.mockRestore();
  });

  it('reports failure when notification unsubscribe does not complete', async () => {
    vi.mocked(getSubscriptionStatus).mockResolvedValue(true);

    render(<PushNotificationSettings />);
    const notificationSwitch = await screen.findByRole('switch', { name: 'Notifikasi Push' });
    fireEvent.click(notificationSwitch);

    await waitFor(() => expect(toast.error).toHaveBeenCalledWith('Gagal menonaktifkan notifikasi'));
    expect(notificationSwitch).toBeChecked();
  });
});
