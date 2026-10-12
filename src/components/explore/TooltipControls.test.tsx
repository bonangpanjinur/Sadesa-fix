import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { TooltipProvider } from '@/components/ui/tooltip';
import { FilterButton } from './FilterSheet';
import { SortDropdown } from './SortDropdown';

const renderWithTooltipProvider = (ui: React.ReactNode) =>
  render(<TooltipProvider>{ui}</TooltipProvider>);

describe('icon-only controls with tooltips', () => {
  it('names the sort button and reports when its options are open', () => {
    renderWithTooltipProvider(<SortDropdown value="relevance" onChange={vi.fn()} />);
    const button = screen.getByRole('button', { name: 'Urutkan; saat ini Relevansi' });
    expect(button).toHaveAttribute('aria-expanded', 'false');
    fireEvent.click(button);
    expect(button).toHaveAttribute('aria-expanded', 'true');
  });

  it('announces the active filter count on the filter button', () => {
    renderWithTooltipProvider(<FilterButton activeCount={2} onClick={vi.fn()} />);
    expect(screen.getByRole('button', { name: 'Filter, 2 filter aktif' })).toBeInTheDocument();
  });

  it('uses a clear accessible name when no filters are active', () => {
    renderWithTooltipProvider(<FilterButton activeCount={0} onClick={vi.fn()} />);
    expect(screen.getByRole('button', { name: 'Filter produk' })).toBeInTheDocument();
  });
});
