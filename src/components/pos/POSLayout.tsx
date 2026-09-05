import { ReactNode, useState } from 'react';
import { useLocation } from 'react-router-dom';
import { POSSidebar } from './POSSidebar';
import { Menu } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { usePOS } from '@/contexts/POSContext';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { QROrderNotificationBell } from './QROrderNotificationBell';
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
  const [sidebarOpen, setSidebarOpen] = useState(false);
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
    <div className="flex h-dvh min-h-0 bg-background">
      {sidebarOpen && (
        <div className="fixed inset-0 bg-black/50 z-40 lg:hidden" onClick={() => setSidebarOpen(false)} />
      )}

        <div className={cn(
        'fixed inset-y-0 left-0 z-50 transform transition-transform duration-200 lg:relative lg:z-0',
        sidebarOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'
      )}>
        <POSSidebar />
      </div>

      <div className="flex min-h-0 min-w-0 flex-1 flex-col">
        <div className="sticky top-0 z-30 flex shrink-0 items-center justify-between gap-3 border-b border-border bg-background/95 px-3 py-3 backdrop-blur sm:px-4 lg:px-6">
          <div className="flex items-center gap-3">
            <Button variant="ghost" size="icon" aria-label="Buka menu POS" className="lg:hidden h-8 w-8" onClick={() => setSidebarOpen(true)}>
              <Menu className="h-4 w-4" />
            </Button>
            <div className="min-w-0">
              <h1 className="font-semibold text-base lg:text-lg">{title}</h1>
              {subtitle && <p className="text-xs text-muted-foreground hidden lg:block">{subtitle}</p>}
            </div>
          </div>
          <div className="flex min-w-0 flex-wrap items-center justify-end gap-2">
            <QROrderNotificationBell />
            {actions}
          </div>
        </div>

        <main className="min-h-0 flex-1 overflow-y-auto overscroll-contain p-3 sm:p-4 lg:p-6">
          <div className={fullWidth ? 'w-full min-w-0' : 'mx-auto w-full max-w-7xl min-w-0'}>
            {children}
          </div>
        </main>
      </div>
    </div>
  );
}
