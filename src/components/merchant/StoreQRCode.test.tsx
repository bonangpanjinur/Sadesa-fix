import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { StoreQRCode } from './StoreQRCode';

describe('StoreQRCode', () => {
  it('renders the SaDesa mark in the center of the store QR code', () => {
    render(<StoreQRCode merchantId="merchant-1" merchantName="Warung SaDesa" slug="warung-sadesa" />);

    fireEvent.click(screen.getByRole('button', { name: /qr code toko/i }));

    const dialog = screen.getByRole('dialog');
    const qrCode = dialog.querySelector('svg');
    expect(qrCode).toBeInTheDocument();
    expect(qrCode?.querySelector('image')).toHaveAttribute('href', '/branding/sadesa-mark.png');
  });
});
