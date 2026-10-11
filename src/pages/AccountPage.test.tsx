import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { MemoryRouter } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import AccountPage from './AccountPage';

vi.mock('@/contexts/AuthContext', () => ({ useAuth: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: vi.fn() } }));
vi.mock('@/components/layout/Header', () => ({ Header: () => null }));
vi.mock('@/components/layout/BottomNav', () => ({ BottomNav: () => null }));
vi.mock('@/components/account/ProfileEditor', () => ({ ProfileEditor: () => null }));
vi.mock('@/components/account/ServiceProviderRegistration', () => ({ ServiceProviderRegistration: () => null }));
vi.mock('@/hooks/use-toast', () => ({ toast: vi.fn() }));

interface QueryResult {
  data: Array<Record<string, unknown>> | null;
  error: { message: string } | null;
}

function createQuery(result: QueryResult) {
  const query = {
    select: vi.fn(),
    eq: vi.fn(),
    order: vi.fn(),
    limit: vi.fn(),
    then: (resolve: (value: QueryResult) => unknown, reject?: (reason: unknown) => unknown) =>
      Promise.resolve(result).then(resolve, reject),
  };
  query.select.mockReturnValue(query);
  query.eq.mockReturnValue(query);
  query.order.mockReturnValue(query);
  query.limit.mockReturnValue(query);
  return query;
}

const appRouter = readFileSync(resolve(process.cwd(), 'src/App.tsx'), 'utf8');
const accountPageSource = readFileSync(resolve(process.cwd(), 'src/pages/AccountPage.tsx'), 'utf8');
const adminCourierEditor = readFileSync(resolve(process.cwd(), 'src/components/admin/CourierEditDialog.tsx'), 'utf8');

describe('AccountPage and /profile route', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(useAuth).mockReturnValue({
      user: { id: 'user-1', email: 'ayu@example.test', user_metadata: { full_name: 'Ayu' } },
      signOut: vi.fn(),
      loading: false,
      isAdmin: false,
      isVerifikator: false,
      isMerchant: false,
      isCourier: false,
      isAdminDesa: false,
      isServiceProvider: false,
    } as unknown as ReturnType<typeof useAuth>);
  });

  it('registers /profile as a protected alias of the account page', () => {
    const profileRoute = appRouter.match(/<Route path="\/profile" element={([\s\S]*?)\} \/>/)?.[1];

    expect(profileRoute).toContain('<ProtectedRoute>');
    expect(profileRoute).toContain('<AccountPage />');
  });

  it('hides courier self-service vehicle changes while retaining admin vehicle editing', () => {
    expect(accountPageSource).not.toContain('CourierVehicleEditor');
    expect(adminCourierEditor).toContain('Jenis Kendaraan');
    expect(adminCourierEditor).toContain('vehicle_plate');
  });

  it('shows an error on profile load failure and successfully retries', async () => {
    const databaseError = { message: 'Temporary profile lookup failure' };
    const profileResults: QueryResult[] = [
      { data: null, error: databaseError },
      { data: null, error: databaseError },
      { data: [{ full_name: 'Ayu', phone: null, address: null }], error: null },
    ];
    vi.mocked(supabase.from).mockImplementation((table) => {
      const result = table === 'profiles'
        ? profileResults.shift() ?? { data: [], error: null }
        : { data: [], error: null };
      return createQuery(result) as never;
    });
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});
    const consoleWarn = vi.spyOn(console, 'warn').mockImplementation(() => {});

    render(
      <MemoryRouter>
        <AccountPage />
      </MemoryRouter>,
    );

    expect(await screen.findByRole('alert')).toHaveTextContent('Profil belum dapat dimuat');
    fireEvent.click(screen.getByRole('button', { name: 'Coba lagi' }));

    expect(await screen.findByRole('heading', { name: 'Ayu' })).toBeInTheDocument();
    expect(screen.getByText('Daftar Pedagang')).toBeInTheDocument();
    expect(screen.queryByText('Daftar Merchant')).not.toBeInTheDocument();
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    consoleError.mockRestore();
    consoleWarn.mockRestore();
  });

  it('uses Pedagang for the merchant dashboard shortcut', async () => {
    vi.mocked(useAuth).mockReturnValue({
      user: { id: 'merchant-user', email: 'pedagang@example.test', user_metadata: { full_name: 'Pedagang' } },
      signOut: vi.fn(),
      loading: false,
      isAdmin: false,
      isVerifikator: false,
      isMerchant: true,
      isCourier: false,
      isAdminDesa: false,
      isServiceProvider: false,
    } as unknown as ReturnType<typeof useAuth>);
    vi.mocked(supabase.from).mockImplementation(() => createQuery({ data: [], error: null }) as never);

    render(
      <MemoryRouter>
        <AccountPage />
      </MemoryRouter>,
    );

    expect(await screen.findByText('Dashboard Pedagang')).toBeInTheDocument();
    expect(screen.queryByText('Dashboard Merchant')).not.toBeInTheDocument();
  });
});
