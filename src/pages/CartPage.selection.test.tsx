import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { setLocale } from '@/lib/i18n';
import { getCartItemKey } from '@/lib/cartItemIdentity';
import type { CartItem, Product } from '@/types';

const mockCart = vi.hoisted(() => ({
  items: [] as unknown[],
  selectedItemIds: [] as string[],
  stockRows: [] as unknown[],
  loadProductStock: false,
  updateQuantity: vi.fn(),
  syncProductStock: vi.fn(),
  removeFromCart: vi.fn(),
  removeCartItem: vi.fn(),
  selectItemKeys: vi.fn(),
  clearCart: vi.fn(),
  toast: vi.fn(),
}));

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: { id: 'buyer-1' } }),
}));

vi.mock('@/contexts/CartContext', async () => {
  const React = await import('react');
  const { getCartItemKey: getMockCartItemKey } = await import('@/lib/cartItemIdentity');
  return {
    useCart: () => {
      const items = mockCart.items as CartItem[];
      const [selectedItemIds, setSelectedItemIds] = React.useState(mockCart.selectedItemIds);
      const toggleItemSelection = React.useCallback((productId: string) => {
        setSelectedItemIds((current) => current.includes(productId)
          ? current.filter((id) => id !== productId)
          : [...current, productId]);
      }, []);
      return {
        items,
        selectedItemIds,
        selectedItems: items.filter((item) => selectedItemIds.includes(getMockCartItemKey(item))),
        toggleItemSelection,
        selectItemKeys: mockCart.selectItemKeys,
        updateQuantity: mockCart.updateQuantity,
        syncProductStock: mockCart.syncProductStock,
        removeFromCart: mockCart.removeFromCart,
        removeCartItem: mockCart.removeCartItem,
        clearCart: mockCart.clearCart,
      };
    },
  };
});

vi.mock('@/hooks/useGuestCheckoutEnabled', () => ({
  useGuestCheckoutEnabled: () => ({ enabled: true, loading: false }),
}));

vi.mock('@/hooks/use-toast', () => ({
  toast: mockCart.toast,
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (table: string) => ({
      select: () => ({
        in: () => table === 'products' && mockCart.loadProductStock
          ? Promise.resolve({ data: mockCart.stockRows, error: null })
          : new Promise(() => {}),
      }),
    }),
  },
}));

import CartPage from './CartPage';

function product(id: string, merchantId: string, merchantName: string): Product {
  return {
    id,
    merchantId,
    merchantName,
    name: `Produk ${id}`,
    description: '',
    price: 10_000,
    stock: 10,
    image: 'https://example.com/product.jpg',
    category: 'Makanan',
    isActive: true,
  };
}

function item(productValue: Product, toppingId?: string): CartItem {
  return {
    product: productValue,
    quantity: 1,
    toppings: toppingId
      ? [{ product: { id: toppingId, name: `Topping ${toppingId}`, price: 1_000, stock: 10 }, quantity: 1 }]
      : undefined,
  };
}

function CurrentPath() {
  const location = useLocation();
  return <output data-testid="current-path">{location.pathname}</output>;
}

function renderCart() {
  return render(
    <MemoryRouter initialEntries={['/cart']}>
      <CartPage />
      <CurrentPath />
    </MemoryRouter>,
  );
}

beforeEach(() => {
  mockCart.items = [];
  mockCart.selectedItemIds = [];
  mockCart.stockRows = [];
  mockCart.loadProductStock = false;
  vi.clearAllMocks();
  setLocale('id');
});

describe('CartPage selection and checkout guard', () => {
  it('selects and deselects each unique product once when a product has multiple topping variants', () => {
    const productA = product('a', 'merchant-a', 'Toko A');
    mockCart.items = [
      item(productA, 'cheese'),
      item(productA, 'chili'),
      item(product('b', 'merchant-a', 'Toko A')),
    ];
    renderCart();

    const selectAll = screen.getByRole('button', { name: 'Pilih semua produk dari Toko A' });
    fireEvent.click(selectAll);
    expect(screen.getAllByRole('checkbox')).toHaveLength(3);
    screen.getAllByRole('checkbox').forEach((checkbox) => expect(checkbox).toBeChecked());

    fireEvent.click(screen.getByRole('button', { name: 'Batal pilih produk dari Toko A' }));
    screen.getAllByRole('checkbox').forEach((checkbox) => expect(checkbox).not.toBeChecked());
  });

  it('keeps select-all scoped to a merchant ID when two merchants have the same display name', () => {
    mockCart.items = [
      item(product('a', 'merchant-a', 'Toko Sama')),
      item(product('b', 'merchant-b', 'Toko Sama')),
    ];
    renderCart();

    const selectAllButtons = screen.getAllByRole('button', { name: 'Pilih semua produk dari Toko Sama' });
    expect(selectAllButtons).toHaveLength(2);
    fireEvent.click(selectAllButtons[0]);

    const checkboxes = screen.getAllByRole('checkbox');
    expect(checkboxes[0]).toBeChecked();
    expect(checkboxes[1]).not.toBeChecked();
  });

  it('checks out one merchant and selects only that merchant’s cart-line keys', () => {
    const merchantAItem = item(product('a', 'merchant-a', 'Toko A'), 'cheese');
    const merchantBItem = item(product('b', 'merchant-b', 'Toko B'));
    mockCart.items = [merchantAItem, merchantBItem];
    renderCart();

    fireEvent.click(screen.getAllByRole('button', { name: 'Checkout Toko Ini' })[0]);

    expect(mockCart.selectItemKeys).toHaveBeenCalledWith([getCartItemKey(merchantAItem)]);
    expect(screen.getByTestId('current-path')).toHaveTextContent('/checkout');
  });

  it('does not navigate to checkout when no cart product is selected', () => {
    mockCart.items = [item(product('a', 'merchant-a', 'Toko A'))];
    renderCart();

    fireEvent.click(screen.getByRole('button', { name: 'Lanjut ke Checkout' }));

    expect(screen.getByTestId('current-path')).toHaveTextContent('/cart');
    expect(mockCart.toast).toHaveBeenCalledWith(expect.objectContaining({
      title: 'Pilih produk terlebih dahulu',
      variant: 'destructive',
    }));
  });

  it('exposes named quantity and remove controls and sends a bounded quantity update', () => {
    const productA = product('a', 'merchant-a', 'Toko A');
    mockCart.items = [{ ...item(productA), quantity: 1 }];
    renderCart();

    expect(screen.getByRole('button', { name: 'Hapus Produk a dari keranjang' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Tambah Produk a' }));
    expect(mockCart.updateQuantity).toHaveBeenCalledWith('a', 2, undefined);
  });

  it('blocks checkout when the refreshed server stock is exhausted', async () => {
    const cartItem = item(product('a', 'merchant-a', 'Toko A'));
    mockCart.items = [cartItem];
    mockCart.selectedItemIds = [getCartItemKey(cartItem)];
    mockCart.loadProductStock = true;
    mockCart.stockRows = [{ id: 'a', stock: 0, is_active: true, price: 10_000, name: 'Produk a' }];
    renderCart();

    expect(await screen.findByRole('alert')).toHaveTextContent('Checkout diblokir');
    expect(screen.getByRole('button', { name: 'Periksa Stok Produk' })).toBeDisabled();
  });
});
