import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import type { Product } from '@/types';

vi.mock('@/contexts/CartContext', () => ({
  useCart: () => ({ addToCart: vi.fn() }),
}));

vi.mock('@/hooks/useFlashSales', () => ({
  useProductFlashSale: () => ({ flashSale: null }),
}));

vi.mock('@/components/WishlistButton', () => ({
  WishlistButton: () => null,
}));

vi.mock('@/components/ui/OptimizedImage', () => ({
  OptimizedImage: ({ src, alt }: { src: string; alt: string }) => <img src={src} alt={alt} />,
}));

import { ProductCard } from './ProductCard';

const baseProduct: Product = {
  id: 'product-1',
  merchantId: 'merchant-1',
  merchantName: 'Warung Uji',
  name: 'Nasi Uji',
  description: '',
  price: 12000,
  stock: 3,
  image: '/product.jpg',
  category: 'kuliner',
  isActive: true,
  isAvailable: false,
  hasQuota: true,
};

function renderProduct(product: Product) {
  return render(
    <MemoryRouter>
      <ProductCard product={product} flashSaleOverride={null} />
    </MemoryRouter>,
  );
}

describe('ProductCard availability indicators', () => {
  it('shows an open-store badge on available products', () => {
    renderProduct({ ...baseProduct, isAvailable: true, isMerchantOpen: true });

    expect(screen.getByRole('status', { name: /toko buka/i })).toHaveTextContent('Buka');
  });

  it('shows a red stock-empty badge and prevents adding the unavailable item to cart', () => {
    renderProduct({ ...baseProduct, stock: 0, unavailableReason: 'Stok Habis' });

    expect(screen.getByRole('status', { name: /stok habis/i })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /tambahkan nasi uji ke keranjang/i })).not.toBeInTheDocument();
  });

  it('shows a distinct store-closed badge for products that still have stock', () => {
    renderProduct({
      ...baseProduct,
      isMerchantOpen: false,
      unavailableReason: 'Toko Tutup',
    });

    expect(screen.getByRole('status', { name: /toko tutup/i })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /tambahkan nasi uji ke keranjang/i })).not.toBeInTheDocument();
  });

  it('shows both indicators when the store is closed and stock is empty', () => {
    renderProduct({
      ...baseProduct,
      stock: 0,
      isMerchantOpen: false,
      unavailableReason: 'Toko Tutup',
    });

    expect(screen.getByRole('status', { name: /stok habis/i })).toBeInTheDocument();
    expect(screen.getByRole('status', { name: /toko tutup/i })).toBeInTheDocument();
  });
});
