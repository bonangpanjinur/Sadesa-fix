import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { MemoryRouter } from 'react-router-dom';
import { MealTimeReminder, getMealPeriod } from './MealTimeReminder';

const auth = vi.hoisted(() => ({ user: { id: 'user-1' } as { id: string } | null }));
const push = vi.hoisted(() => ({
  isSupported: true,
  isSubscribed: false,
  loading: false,
  subscribe: vi.fn().mockResolvedValue(true),
}));

vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => auth }));
vi.mock('@/hooks/usePushNotification', () => ({ usePushNotification: () => push }));
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }));

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  auth.user = { id: 'user-1' };
  push.isSupported = true;
  push.isSubscribed = false;
  push.loading = false;
  push.subscribe.mockClear();
});

describe('MealTimeReminder', () => {
  it.each([
    [5, 'pagi'], [9, 'pagi'], [10, 'siang'], [13, 'siang'],
    [14, 'sore'], [17, 'sore'], [18, 'malam'], [23, 'malam'], [2, 'malam'],
  ] as const)('maps hour %i to %s', (hour, period) => {
    expect(getMealPeriod(hour)).toBe(period);
  });

  it('shows the local-time meal suggestion and opt-in for a signed-in user', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(2026, 9, 15, 12, 30));
    render(<MemoryRouter><MealTimeReminder /></MemoryRouter>);
    expect(screen.getByTestId('meal-time-reminder')).toHaveAttribute('aria-label', 'Pengingat makan siang');
    expect(screen.getByText(/makan siang/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Aktifkan push notification SaDesa' })).toBeInTheDocument();
  });

  it('does not offer push when already subscribed and requests subscription on click', () => {
    push.isSubscribed = false;
    render(<MemoryRouter><MealTimeReminder /></MemoryRouter>);
    fireEvent.click(screen.getByRole('button', { name: 'Aktifkan push notification SaDesa' }));
    expect(push.subscribe).toHaveBeenCalledTimes(1);
  });

  it('hides the subscription control for anonymous visitors and already subscribed users', () => {
    auth.user = null;
    const { rerender } = render(<MemoryRouter><MealTimeReminder /></MemoryRouter>);
    expect(screen.queryByRole('button', { name: 'Aktifkan push notification SaDesa' })).not.toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Masuk' })).toHaveAttribute('href', '/auth');

    auth.user = { id: 'user-1' };
    push.isSubscribed = true;
    rerender(<MemoryRouter><MealTimeReminder /></MemoryRouter>);
    expect(screen.queryByRole('button', { name: 'Aktifkan push notification SaDesa' })).not.toBeInTheDocument();
  });
});
