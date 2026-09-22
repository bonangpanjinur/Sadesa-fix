import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { MerchantAvatar } from './MerchantAvatar';

describe('MerchantAvatar', () => {
  it('renders the merchant profile photo when available', () => {
    render(<MerchantAvatar imageUrl="https://cdn.example.test/toko.jpg" merchantName="Mie Ayam Abah Yudi" />);

    expect(screen.getByRole('img', { name: 'Foto profil Mie Ayam Abah Yudi' })).toHaveAttribute(
      'src',
      'https://cdn.example.test/toko.jpg',
    );
  });

  it('falls back to the store icon when no photo is available or the image fails', () => {
    const { rerender } = render(<MerchantAvatar imageUrl={null} merchantName="Toko Tanpa Foto" />);
    expect(screen.queryByRole('img')).not.toBeInTheDocument();
    expect(screen.getByLabelText('Foto profil Toko Tanpa Foto')).toBeInTheDocument();

    rerender(<MerchantAvatar imageUrl="https://cdn.example.test/rusak.jpg" merchantName="Toko Rusak" />);
    fireEvent.error(screen.getByRole('img', { name: 'Foto profil Toko Rusak' }));
    expect(screen.queryByRole('img')).not.toBeInTheDocument();
  });
});
