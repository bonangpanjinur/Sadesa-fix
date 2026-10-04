import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { useUserRoles } from '@/hooks/useUserRoles';
import { ProtectedRoute } from './ProtectedRoute';

vi.mock('@/contexts/AuthContext', () => ({ useAuth: vi.fn() }));
vi.mock('@/hooks/useUserRoles', () => ({ useUserRoles: vi.fn() }));

function renderMerchantRoute() {
  return render(
    <MemoryRouter initialEntries={['/merchant']}>
      <Routes>
        <Route path="/merchant" element={<ProtectedRoute><div>Merchant dashboard</div></ProtectedRoute>} />
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
  beforeEach(() => vi.clearAllMocks());

  it('waits for merchant profile recovery instead of briefly denying access', () => {
    mockRoles(['buyer'], true);

    renderMerchantRoute();

    expect(screen.getByText('Memuat...')).toBeInTheDocument();
    expect(screen.queryByText('Access denied')).not.toBeInTheDocument();
    expect(screen.queryByText('Merchant dashboard')).not.toBeInTheDocument();
  });

  it('allows the merchant once profile recovery restores the role', () => {
    mockRoles(['merchant', 'buyer'], false);

    renderMerchantRoute();

    expect(screen.getByText('Merchant dashboard')).toBeInTheDocument();
    expect(screen.queryByText('Access denied')).not.toBeInTheDocument();
  });

  it('still denies a user with no merchant role after recovery completes', () => {
    mockRoles(['buyer'], false);

    renderMerchantRoute();

    expect(screen.getByText('Access denied')).toBeInTheDocument();
    expect(screen.queryByText('Merchant dashboard')).not.toBeInTheDocument();
  });
});
