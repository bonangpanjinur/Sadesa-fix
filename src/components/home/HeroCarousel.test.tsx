import { act, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { HeroCarousel, type BannerSlide } from './HeroCarousel';

const slides: BannerSlide[] = [
  { id: 'ad-1', title: 'Iklan kategori pertama', image: '/ad-1.jpg', isSponsored: true },
  { id: 'ad-2', title: 'Iklan kategori kedua', image: '/ad-2.jpg', isSponsored: true },
];

afterEach(() => {
  vi.useRealTimers();
});

describe('HeroCarousel iklan kategori', () => {
  it('tidak menampilkan banner ketika daftar banner kosong', () => {
    const { container } = render(<HeroCarousel slides={[]} />);

    expect(container.firstChild).toBeNull();
  });

  it('menampilkan label Iklan untuk slide bersponsor', () => {
    render(<HeroCarousel slides={slides} ariaLabel="Iklan kategori makanan" />);

    expect(screen.getByRole('region', { name: 'Iklan kategori makanan' })).toBeInTheDocument();
    expect(screen.getByText('Iklan')).toBeInTheDocument();
  });

  it('berotasi otomatis ke banner berikutnya setelah interval', async () => {
    vi.useFakeTimers();
    render(<HeroCarousel slides={slides} autoPlayInterval={1000} ariaLabel="Iklan kategori makanan" />);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(1000);
    });

    expect(screen.getByRole('heading', { name: 'Iklan kategori kedua' })).toBeInTheDocument();
  });
});
