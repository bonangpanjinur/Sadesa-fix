import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes, useLocation } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { DashboardRoute } from './DashboardRoute';

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: vi.fn(),
}));

function LocationProbe() {
  const location = useLocation();
  const state = location.state as { from?: { pathname?: string } } | null;
  return (
    <>
      <output data-testid="current-path">{location.pathname}</output>
      <output data-testid="from-path">{state?.from?.pathname || ''}</output>
    </>
  );
}

function renderDashboardRoute() {
  return render(
    <MemoryRouter initialEntries={['/dashboard']}>
      <Routes>
        <Route path="/dashboard" element={<DashboardRoute />} />
        <Route path="*" element={<LocationProbe />} />
      </Routes>
    </MemoryRouter>,
  );
}

describe('DashboardRoute', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it.each([
    { roles: ['admin', 'buyer'], destination: '/admin' },
    { roles: ['admin_desa', 'buyer'], destination: '/desa' },
    { roles: ['verifikator', 'buyer'], destination: '/verifikator' },
    { roles: ['merchant', 'buyer'], destination: '/merchant' },
    { roles: ['courier', 'buyer'], destination: '/courier' },
    { roles: ['service_provider', 'buyer'], destination: '/services' },
    { roles: ['buyer'], destination: '/' },
  ])('routes $roles to $destination', ({ roles, destination }) => {
    vi.mocked(useAuth).mockReturnValue({
      user: { id: 'user-1', email: 'user@example.test' },
      roles,
      loading: false,
      rolesLoading: false,
    } as ReturnType<typeof useAuth>);

    renderDashboardRoute();

    expect(screen.getByTestId('current-path')).toHaveTextContent(destination);
  });

  it('redirects signed-out visitors to login and keeps the intended path', () => {
    vi.mocked(useAuth).mockReturnValue({
      user: null,
      roles: [],
      loading: false,
      rolesLoading: false,
    } as ReturnType<typeof useAuth>);

    renderDashboardRoute();

    expect(screen.getByTestId('current-path')).toHaveTextContent('/auth');
    expect(screen.getByTestId('from-path')).toHaveTextContent('/dashboard');
  });

  it('waits for roles before choosing a dashboard', () => {
    vi.mocked(useAuth).mockReturnValue({
      user: { id: 'user-1', email: 'user@example.test' },
      roles: ['buyer'],
      loading: false,
      rolesLoading: true,
    } as ReturnType<typeof useAuth>);

    renderDashboardRoute();

    expect(screen.getByRole('status')).toHaveTextContent('Memuat dashboard');
    expect(screen.queryByTestId('current-path')).not.toBeInTheDocument();
  });

  it('waits for merchant profile recovery before choosing a dashboard', () => {
    vi.mocked(useAuth).mockReturnValue({
      user: { id: 'user-1', email: 'user@example.test' },
      roles: ['buyer'],
      loading: false,
      rolesLoading: false,
      merchantRoleRecoveryLoading: true,
    } as ReturnType<typeof useAuth>);

    renderDashboardRoute();

    expect(screen.getByRole('status')).toHaveTextContent('Memuat dashboard');
    expect(screen.queryByTestId('current-path')).not.toBeInTheDocument();
  });
});
