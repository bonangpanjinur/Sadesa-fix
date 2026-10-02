import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POSOnboardingChecklist } from './POSOnboardingChecklist';

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
  getPrinterSettings: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: mocks.from },
}));

vi.mock('@/lib/thermalPrinter', () => ({
  getPrinterSettings: mocks.getPrinterSettings,
}));

describe('POSOnboardingChecklist', () => {
  beforeEach(() => {
    const query = {
      select: vi.fn().mockReturnThis(),
      eq: vi.fn().mockResolvedValue({ count: 1, error: null }),
    };
    mocks.from.mockReturnValue(query);
    mocks.getPrinterSettings.mockReturnValue({ autoPrint: false });
  });

  it('lets merchants finish required onboarding while keeping printer setup optional', async () => {
    render(
      <MemoryRouter>
        <POSOnboardingChecklist
          tenantId="tenant-1"
          tenantName="Toko Contoh"
          outletCount={1}
          activeOutletName="Outlet Utama"
          enabledModuleCount={2}
        />
      </MemoryRouter>,
    );

    expect(await screen.findByText('4 dari 4 langkah wajib selesai.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Printer struk \(opsional\)/ })).toHaveTextContent('browser print masih tersedia');
    expect(screen.queryByRole('button', { name: 'Buka kasir untuk menyelesaikan onboarding' })).not.toBeInTheDocument();
  });

  it('does not label a failed transaction-count check as no sales', async () => {
    const query = {
      select: vi.fn().mockReturnThis(),
      eq: vi.fn().mockResolvedValue({ count: null, error: new Error('database unavailable') }),
    };
    mocks.from.mockReturnValue(query);

    render(
      <MemoryRouter>
        <POSOnboardingChecklist
          tenantId="tenant-1"
          tenantName="Toko Contoh"
          outletCount={1}
          enabledModuleCount={2}
        />
      </MemoryRouter>,
    );

    expect(await screen.findByText('Status transaksi belum dapat diverifikasi')).toBeInTheDocument();
    expect(screen.queryByText('Belum ada transaksi')).not.toBeInTheDocument();
  });
});
