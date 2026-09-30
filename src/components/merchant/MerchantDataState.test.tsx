import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { MerchantCardError, MerchantCardLoading } from './MerchantDataState';

describe('MerchantDataState', () => {
  it('announces the resource being loaded', () => {
    render(<MerchantCardLoading label="Memuat laporan keuangan..." />);

    expect(screen.getByText('Memuat laporan keuangan...')).toBeInTheDocument();
  });

  it('shows a retry action and invokes it when requested', () => {
    const onRetry = vi.fn();
    render(<MerchantCardError message="Item pesanan gagal dimuat." onRetry={onRetry} />);

    expect(screen.getByRole('alert')).toHaveTextContent('Item pesanan gagal dimuat.');
    fireEvent.click(screen.getByRole('button', { name: 'Coba lagi' }));

    expect(onRetry).toHaveBeenCalledOnce();
  });
});
