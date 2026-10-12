import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { ClickableImage, ImageLightbox } from './ImageLightbox';

describe('ImageLightbox', () => {
  it('provides a named dialog and accessible labels for icon controls', () => {
    render(<ImageLightbox images={['/first.jpg', '/second.jpg']} open initialIndex={0} onOpenChange={() => {}} />);

    expect(screen.getByRole('dialog', { name: 'Pratinjau gambar 1 dari 2' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Tutup pratinjau gambar' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Gambar sebelumnya' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Gambar berikutnya' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Perkecil gambar' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Perbesar gambar' })).toBeInTheDocument();
  });

  it('opens from a named keyboard-operable image button and restores focus on close', async () => {
    render(<ClickableImage src="/photo.jpg" alt="Foto produk" />);
    const trigger = screen.getByRole('button', { name: 'Perbesar gambar: Foto produk' });
    trigger.focus();
    fireEvent.click(trigger);
    expect(screen.getByRole('dialog', { name: 'Pratinjau gambar 1 dari 1' })).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'Tutup pratinjau gambar' }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(document.activeElement).toBe(trigger);
  });
});
