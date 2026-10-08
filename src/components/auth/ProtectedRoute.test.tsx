import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act, render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { useUserRoles } from '@/hooks/useUserRoles';
import { supabase } from '@/integrations/supabase/client';
import { ProtectedRoute } from './ProtectedRoute';

vi.mock('@/contexts/AuthContext', () => ({ useAuth: vi.fn() }));
vi.mock('@/hooks/useUserRoles', () => ({ useUserRoles: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: vi.fn() } }));

function renderMerchantRoute() {
  return render(
    <MemoryRouter initialEntries={['/merchant']}>
      <Routes>
        <Route path="/merchant" element={<ProtectedRoute><div>Merchant dashboard</div></ProtectedRoute>} />
        <Route path="/account" element={<div>Complete your address</div>} />
        <Route path="/unauthorized" element={<div>Access denied</div>} />
      </Routes>
    </MemoryRouter>,
  );
}

function mockRoles(roles: string[], merchantRoleRecoveryLoading: boolean) {
  vi.mocked(useAuth).mockReturnValue({
    user: { id: 'merchant-1', email: 'merchant@example.test' },
    loading: false,
    rolesLoading: false,
    merchantRoleRecoveryLoading,
  } as ReturnType<typeof useAuth>);
  vi.mocked(useUserRoles).mockReturnValue({
    roles,
    loading: false,
    merchantRoleRecoveryLoading,
    hasAnyRole: (required: string[]) => required.some((role) => roles.includes(role)),
  } as ReturnType<typeof useUserRoles>);
}

describe('ProtectedRoute merchant role recovery', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    const query = { select: vi.fn(), eq: vi.fn(), maybeSingle: vi.fn() };
    query.select.mockReturnValue(query);
    query.eq.mockReturnValue(query);
    query.maybeSingle.mockResolvedValue({
      data: { province_id: 'p', city_id: 'c', district_id: 'd', village_id: 'v' },
      error: null,
    });
    vi.mocked(supabase.from).mockReturnValue(query as never);
  });

  it('waits for merchant profile recovery instead of briefly denying access', async () => {
    mockRoles(['buyer'], true);

    await act(async () => {
      renderMerchantRoute();
      await Promise.resolve();
    });

    expect(screen.getByText('Memuat...')).toBeInTheDocument();
    expect(screen.queryByText('Access denied')).not.toBeInTheDocument();
    expect(screen.queryByText('Merchant dashboard')).not.toBeInTheDocument();
  });

  it('allows the merchant once profile recovery restores the role', async () => {
    mockRoles(['merchant', 'buyer'], false);

    renderMerchantRoute();

    expect(await screen.findByText('Merchant dashboard')).toBeInTheDocument();
    expect(screen.queryByText('Access denied')).not.toBeInTheDocument();
  });

  it('still denies a user with no merchant role after recovery completes', async () => {
    mockRoles(['buyer'], false);

    renderMerchantRoute();

    expect(await screen.findByText('Access denied')).toBeInTheDocument();
    expect(screen.queryByText('Merchant dashboard')).not.toBeInTheDocument();
  });

  it('redirects a signed-in user with an incomplete address to account completion', async () => {
    mockRoles(['merchant', 'buyer'], false);
    vi.mocked(supabase.from).mockImplementation(() => {
      const query = { select: vi.fn(), eq: vi.fn(), maybeSingle: vi.fn() };
      query.select.mockReturnValue(query);
      query.eq.mockReturnValue(query);
      query.maybeSingle.mockResolvedValue({ data: { province_id: null, city_id: null, district_id: null, village_id: null }, error: null });
      return query as never;
    });

    renderMerchantRoute();

    expect(await screen.findByText('Complete your address')).toBeInTheDocument();
    expect(screen.queryByText('Merchant dashboard')).not.toBeInTheDocument();
  });
});
