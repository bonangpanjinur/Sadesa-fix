import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { useState } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { SubscriptionActionDialog } from './SubscriptionActionDialog';

const baseProps = {
  open: true,
  action: 'SUSPEND' as const,
  merchantName: 'Warung Melati',
  reason: '',
  busy: false,
  onReasonChange: vi.fn(),
  onOpenChange: vi.fn(),
  onConfirm: vi.fn(),
};

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe('SubscriptionActionDialog', () => {
  it('names the suspended merchant, requires a reason, and confirms only when a reason exists', () => {
    const onConfirm = vi.fn();
    function Harness() {
      const [reason, setReason] = useState('');
      return (
        <SubscriptionActionDialog
          {...baseProps}
          reason={reason}
          onReasonChange={setReason}
          onConfirm={onConfirm}
        />
      );
    }
    render(<Harness />);

    expect(screen.getByRole('dialog', { name: 'Tangguhkan akses POS Warung Melati' })).toBeInTheDocument();
    const confirmButton = screen.getByRole('button', { name: 'Tangguhkan akses' });
    expect(confirmButton).toBeDisabled();

    fireEvent.change(screen.getByRole('textbox', { name: 'Alasan (wajib)' }), {
      target: { value: 'Perlu verifikasi pembayaran' },
    });
    expect(confirmButton).toBeEnabled();
    fireEvent.click(confirmButton);
    expect(onConfirm).toHaveBeenCalledOnce();
  });

  it('shows cancellation consequences, disables repeat actions while busy, and leaves cancellation available', () => {
    const props = {
      ...baseProps,
      action: 'CANCEL' as const,
      reason: 'Atas permintaan merchant',
      busy: true,
      onOpenChange: vi.fn(),
      onConfirm: vi.fn(),
    };
    render(<SubscriptionActionDialog {...props} />);

    expect(screen.getByRole('dialog', { name: 'Batalkan langganan POS Warung Melati' })).toBeInTheDocument();
    expect(screen.getByText(/akses operasional POS dihentikan/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Memproses...' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Batal' })).toBeDisabled();
  });

  it('closes safely when the administrator chooses Batal', () => {
    const props = { ...baseProps, onOpenChange: vi.fn() };
    render(<SubscriptionActionDialog {...props} />);
    fireEvent.click(screen.getByRole('button', { name: 'Batal' }));
    expect(props.onOpenChange).toHaveBeenCalledWith(false);
  });
});
