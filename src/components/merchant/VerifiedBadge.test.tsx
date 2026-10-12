import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { VerifiedBadge, VerifiedIcon } from './VerifiedBadge';
import { TooltipProvider } from '@/components/ui/tooltip';

const renderWithTooltipProvider = (ui: React.ReactNode) =>
  render(<TooltipProvider>{ui}</TooltipProvider>);

describe('merchant badge tooltips', () => {
  it('exposes icon-only badges to keyboard and assistive technology', () => {
    renderWithTooltipProvider(<VerifiedBadge type="popular" showLabel={false} />);
    const badge = screen.getByRole('img', { name: 'Populer. Toko dengan penjualan dan rating tinggi' });
    expect(badge).toHaveAttribute('tabindex', '0');
  });

  it('makes the verified icon tooltip keyboard-focusable and named', () => {
    renderWithTooltipProvider(<VerifiedIcon />);
    const icon = screen.getByRole('img', { name: 'Toko Terverifikasi. Toko ini telah diverifikasi oleh tim kami' });
    expect(icon).toHaveAttribute('tabindex', '0');
  });

  it('does not add a redundant focus stop when the badge label is visible', () => {
    render(<VerifiedBadge />);
    expect(screen.getByText('Terverifikasi').closest('[role="img"]')).toBeNull();
  });
});
