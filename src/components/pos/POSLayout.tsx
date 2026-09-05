import { ReactNode } from 'react';
import { useLocation } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { MerchantLayout } from '@/components/merchant/MerchantLayout';
import { usePOS } from '@/contexts/POSContext';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { canAccessPOSPath } from './posPermissions';
import { POSErrorState, POSLoadingState } from './POSPageStates';

interface POSLayoutProps {
  children: ReactNode;
  title?: string;
  subtitle?: string;
  actions?: ReactNode;
  fullWidth?: boolean;
}

export function POSLayout({ children, title, subtitle, actions, fullWidth }: POSLayoutProps) {
  const { tenant, loading, posRole, posRoleLoading, error: tenantError, refetchTenant } = usePOS();
  const { user, roles, rolesLoading } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  if (loading || rolesLoading || posRoleLoading) {
    return (
      <POSLoadingState label="Memuat data usaha..." />
    );
  }

  if (!user) {
    navigate('/auth');
    return null;
  }

  if (!canAccessPOSPath(roles, location.pathname, posRole)) {
    navigate('/unauthorized', { replace: true });
    return null;
  }

  if (tenantError) {
    return (
      <POSErrorState title="Data usaha belum dapat dimuat" description={tenantError} onRetry={() => void refetchTenant()} />
    );
  }

  if (!tenant) {
    return (
      <div className="flex min-h-screen items-center justify-center p-4">
        <div className="w-full max-w-sm rounded-xl border bg-card p-6 text-center shadow-sm">
          <h2 className="text-xl font-bold">Buat Usaha Anda</h2>
          <p className="mt-2 text-sm text-muted-foreground">
            Anda belum memiliki usaha yang terdaftar di sistem POS. Buat usaha terlebih dahulu untuk mulai menggunakan kasir.
          </p>
          <Button onClick={() => navigate('/merchant/pos/setup')} className="mt-4 w-full bg-emerald-600 hover:bg-emerald-700">
            Buat Usaha Sekarang
          </Button>
        </div>
      </div>
    );
  }

  return (
    <MerchantLayout
      title={title ?? 'POS'}
      subtitle={subtitle}
      actions={actions}
      fullWidth={fullWidth}
    >
      {children}
    </MerchantLayout>
  );
}
