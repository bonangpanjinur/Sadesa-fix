import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { POSPaymentDialog } from './POSPaymentDialog';

const formatCurrency = (value: number) => `Rp ${value.toLocaleString('id-ID')}`;

const baseProps = {
  open: true,
  onOpenChange: vi.fn(),
  subtotal: 50_000,
  taxAmount: 0,
  discount: 0,
  promoDiscount: 0,
  voucherDiscount: 0,
  pointsDiscount: 0,
  total: 50_000,
  paymentMethod: 'cash',
  paymentAmount: '50_000',
  isSplitPayment: false,
  splitMethod2: 'transfer',
  splitAmount1: '',
  splitAmount2: '',
  appliedPromo: null,
  appliedVoucher: null,
  pointsToRedeem: 0,
  pointsEarned: 0,
  selectedCustomer: null,
  loyaltyProgram: null,
  isOnline: true,
  formatCurrency,
  onChange: vi.fn(),
  onProcess: vi.fn().mockResolvedValue(true),
};

describe('POSPaymentDialog', () => {
  it('disables completion and shows the shortfall when cash is insufficient', () => {
    render(<POSPaymentDialog {...baseProps} paymentAmount="30000" />);

    expect(screen.getByRole('status')).toHaveTextContent('Nominal masih kurang Rp 20.000.');
    expect(screen.getByRole('button', { name: 'Selesaikan' })).toBeDisabled();
  });

  it('keeps exact split payments actionable and offers an isi sisa shortcut', async () => {
    const onChange = vi.fn();
    const onProcess = vi.fn().mockResolvedValue(true);

    render(
      <POSPaymentDialog
        {...baseProps}
        onChange={onChange}
        onProcess={onProcess}
        isSplitPayment
        splitAmount1="20000"
        splitAmount2="30000"
      />,
    );

    const completeButton = screen.getByRole('button', { name: 'Selesaikan' });
    expect(completeButton).toBeEnabled();
    fireEvent.click(completeButton);
    await waitFor(() => expect(onProcess).toHaveBeenCalledTimes(1));

    fireEvent.click(screen.getByRole('button', { name: 'Isi sisa' }));
    expect(onChange).toHaveBeenCalledWith('splitAmount2', '30000');
  });

  it('blocks cashless payment while offline and explains the recovery path', () => {
    render(<POSPaymentDialog {...baseProps} paymentMethod="qris" isOnline={false} />);

    expect(screen.getByRole('alert')).toHaveTextContent('memerlukan koneksi internet');
    expect(screen.getByRole('button', { name: 'Selesaikan' })).toBeDisabled();
  });
});
