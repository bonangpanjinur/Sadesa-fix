import { render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { MemoryRouter } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { DesaSidebar } from './DesaSidebar';

vi.mock('@/contexts/AuthContext', () => ({ useAuth: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: vi.fn() } }));

describe('DesaSidebar', () => {
  beforeEach(() => {
    vi.mocked(useAuth).mockReturnValue({ user: null } as unknown as ReturnType<typeof useAuth>);
  });

  it('uses Pedagang in the merchant verification menu label', () => {
    render(
      <MemoryRouter>
        <DesaSidebar />
      </MemoryRouter>,
    );

    expect(screen.getByRole('link', { name: 'Verifikasi Pedagang' })).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Verifikasi Merchant' })).not.toBeInTheDocument();
  });
});
