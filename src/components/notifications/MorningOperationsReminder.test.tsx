import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MorningOperationsReminder } from './MorningOperationsReminder';

describe('MorningOperationsReminder', () => {
  beforeEach(() => {
    window.localStorage.clear();
    vi.useFakeTimers();
    vi.setSystemTime(new Date(2026, 9, 6, 7, 30));
  });

  afterEach(() => {
    cleanup();
    window.localStorage.clear();
    vi.useRealTimers();
  });

  it('shows the merchant reminder in the morning and explains background push accurately', () => {
    render(<MorningOperationsReminder audience="merchant" userId="merchant-1" />);

    expect(screen.getByTestId('morning-operations-reminder-merchant')).toBeInTheDocument();
    expect(screen.getByText(/jangan tutup dashboard/i)).toBeInTheDocument();
    expect(screen.getByText(/Web Push mungkin tetap masuk/i)).toBeInTheDocument();
  });

  it('warns couriers that PWA background location is not guaranteed', () => {
    render(<MorningOperationsReminder audience="courier" userId="courier-1" />);

    expect(screen.getByTestId('morning-operations-reminder-courier')).toBeInTheDocument();
    expect(screen.getByText(/PWA tidak menjamin lokasi terus terkirim/i)).toBeInTheDocument();
  });

  it('does not show outside the morning window', () => {
    vi.setSystemTime(new Date(2026, 9, 6, 13, 0));
    render(<MorningOperationsReminder audience="merchant" userId="merchant-1" />);

    expect(screen.queryByTestId('morning-operations-reminder-merchant')).not.toBeInTheDocument();
  });

  it('can be dismissed and does not reappear for the same account and day', () => {
    const first = render(<MorningOperationsReminder audience="courier" userId="courier-1" />);
    fireEvent.click(screen.getByRole('button', { name: 'Tutup pengingat operasional pagi' }));
    expect(screen.queryByTestId('morning-operations-reminder-courier')).not.toBeInTheDocument();

    first.unmount();
    render(<MorningOperationsReminder audience="courier" userId="courier-1" />);
    expect(screen.queryByTestId('morning-operations-reminder-courier')).not.toBeInTheDocument();
  });
});
