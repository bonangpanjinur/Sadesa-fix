import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { MemoryRouter } from 'react-router-dom';
import { MerchantBottomNavigation } from './MerchantBottomNavigation';

function renderNavigation(path: string, onOpenMenu = vi.fn(), menuExpanded = false) {
  render(
    <MemoryRouter initialEntries={[path]}>
      <MerchantBottomNavigation menuExpanded={menuExpanded} onOpenMenu={onOpenMenu} />
    </MemoryRouter>,
  );
  return onOpenMenu;
}

describe('MerchantBottomNavigation', () => {
  it.each([
    { path: '/merchant', current: 'Beranda' },
    { path: '/merchant/orders/abc', current: 'Pesanan' },
    { path: '/merchant/products/abc', current: 'Produk' },
    { path: '/merchant/pos/kasir', current: 'Buka semua menu pedagang' },
  ])('marks $current current at $path', ({ path, current }) => {
    renderNavigation(path);

    const currentItem = screen.getByRole(current === 'Buka semua menu pedagang' ? 'button' : 'link', { name: current });
    expect(currentItem).toHaveAttribute('aria-current', 'page');
  });

  it('opens the full menu from the bottom navigation and reflects drawer state', () => {
    const onOpenMenu = renderNavigation('/merchant/orders', vi.fn(), true);
    const menuButton = screen.getByRole('button', { name: 'Buka semua menu pedagang' });

    expect(menuButton).toHaveAttribute('aria-controls', 'merchant-mobile-drawer');
    expect(menuButton).toHaveAttribute('aria-haspopup', 'dialog');
    expect(menuButton).toHaveAttribute('aria-expanded', 'true');

    fireEvent.click(menuButton);
    expect(onOpenMenu).toHaveBeenCalledWith(menuButton);
  });
});
