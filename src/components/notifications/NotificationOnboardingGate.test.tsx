import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';

const mocks = vi.hoisted(() => ({
  user: { id: 'courier-1' },
  isPushSupported: vi.fn(),
  getPushPermission: vi.fn(),
  getSubscriptionStatus: vi.fn(),
  hasActiveBrowserPushSubscription: vi.fn(),
  subscribeToPush: vi.fn(),
  getLastPushError: vi.fn(),
}));

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: mocks.user, loading: false }),
}));

vi.mock('@/lib/pushNotification', () => mocks);

import { NotificationOnboardingGate } from './NotificationOnboardingGate';

describe('NotificationOnboardingGate', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.isPushSupported.mockResolvedValue(true);
    mocks.getPushPermission.mockResolvedValue('granted');
    mocks.getSubscriptionStatus.mockResolvedValue(true);
    mocks.hasActiveBrowserPushSubscription.mockResolvedValue(true);
    mocks.subscribeToPush.mockResolvedValue(true);
    mocks.getLastPushError.mockReturnValue('Subscription belum tersimpan (500)');
  });

  it('does not show the modal when push is already registered', async () => {
    render(<NotificationOnboardingGate />);

    await waitFor(() => expect(mocks.getSubscriptionStatus).toHaveBeenCalledWith('courier-1'));
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(mocks.subscribeToPush).not.toHaveBeenCalled();
  });

  it('silently repairs the server record without reopening the modal for an active browser subscription', async () => {
    mocks.getSubscriptionStatus.mockResolvedValue(false);
    render(<NotificationOnboardingGate />);

    await waitFor(() => expect(mocks.subscribeToPush).toHaveBeenCalledWith('courier-1'));
    expect(screen.queryByRole('dialog')).toBeNull();
  });

  it('shows the required modal when no browser subscription exists', async () => {
    mocks.hasActiveBrowserPushSubscription.mockResolvedValue(false);
    render(<NotificationOnboardingGate />);

    expect(await screen.findByRole('dialog')).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Aktifkan Notifikasi' })).toBeTruthy();
  });

  it('keeps the modal open when an existing browser subscription cannot sync to the server', async () => {
    mocks.getSubscriptionStatus.mockResolvedValue(false);
    mocks.subscribeToPush.mockResolvedValue(false);
    render(<NotificationOnboardingGate />);

    expect(await screen.findByRole('dialog')).toBeTruthy();
    expect(screen.getByText(/sinkronisasi belum selesai/i)).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Coba sinkronkan lagi' })).toBeTruthy();
  });
});
