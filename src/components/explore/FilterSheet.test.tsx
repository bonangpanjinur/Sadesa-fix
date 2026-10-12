import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { FilterSheet, type FilterOptions } from './FilterSheet';

const emptyFilters: FilterOptions = { priceRange: null, districts: [], minRating: null };

describe('FilterSheet', () => {
  it('exposes a named modal and selected filter state', () => {
    render(
      <FilterSheet
        isOpen
        onClose={vi.fn()}
        filters={{ ...emptyFilters, districts: [] }}
        onApplyFilters={vi.fn()}
        availableDistricts={['Bantul']}
      />,
    );

    expect(screen.getByRole('dialog', { name: 'Filter' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Tutup dialog' })).toBeInTheDocument();
    const district = screen.getByRole('button', { name: 'Bantul' });
    expect(district).toHaveAttribute('aria-pressed', 'false');
    fireEvent.click(district);
    expect(district).toHaveAttribute('aria-pressed', 'true');
  });

  it('closes on Escape through the shared dialog behavior', () => {
    const onClose = vi.fn();
    render(
      <FilterSheet
        isOpen
        onClose={onClose}
        filters={{ ...emptyFilters, districts: [] }}
        onApplyFilters={vi.fn()}
        availableDistricts={[]}
      />,
    );

    fireEvent.keyDown(document, { key: 'Escape' });
    expect(onClose).toHaveBeenCalledOnce();
  });
});
