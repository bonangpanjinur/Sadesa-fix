import { describe, expect, it, vi, afterEach } from 'vitest';
import { act, render, screen } from '@testing-library/react';
import { PaymentCountdown } from './PaymentCountdown';

describe('PaymentCountdown', () => {
  afterEach(() => vi.useRealTimers());

  it('shows remaining payment time and expires at the deadline', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-08-23T10:00:00.000Z'));
    render(<PaymentCountdown deadline="2026-08-23T10:01:05.000Z" />);

    expect(screen.getByText('Batas waktu pembayaran')).toBeInTheDocument();
    expect(screen.getByText('01:05')).toBeInTheDocument();

    act(() => vi.advanceTimersByTime(65_000));
    expect(screen.getByText('Batas waktu pembayaran telah habis')).toBeInTheDocument();
    expect(screen.getByText('00:00')).toBeInTheDocument();
  });
});
