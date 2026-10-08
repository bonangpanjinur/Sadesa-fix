import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ReviewImageGallery } from './ReviewImageGallery';

describe('ReviewImageGallery', () => {
  it('renders each attached review photo as a thumbnail', () => {
    render(<ReviewImageGallery imageUrls={[
      'https://example.com/review-1.jpg',
      'https://example.com/review-2.jpg',
    ]} />);

    expect(screen.getByRole('img', { name: 'Foto dari ulasan pembeli 1' })).toHaveAttribute('src', 'https://example.com/review-1.jpg');
    expect(screen.getByRole('img', { name: 'Foto dari ulasan pembeli 2' })).toHaveAttribute('src', 'https://example.com/review-2.jpg');
    expect(screen.getAllByRole('button', { name: /^Buka foto ulasan/ })).toHaveLength(2);
  });

  it('does not render an empty gallery when a review has no usable image URLs', () => {
    const { container } = render(<ReviewImageGallery imageUrls={['', '   ']} />);
    expect(container.firstChild).toBeNull();
  });
});
