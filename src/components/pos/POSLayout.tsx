import { ReactNode } from 'react';
import { Button } from '@/components/ui/button';
import { MerchantLayout } from '@/components/merchant/MerchantLayout';
import { usePOS } from '@/contexts/POSContext';
import { useNavigate } from 'react-router-dom';
import { POSErrorState, POSLoadingState } from './POSPageStates';
import { ErrorBoundary } from '@/components/ui/ErrorBoundary';

interface POSLayoutProps {
  children: ReactNode;
  title?: string;
  subtitle?: string;
  actions?: ReactNode;
  fullWidth?: boolean;
}

export function POSLayout({ children, title, subtitle, actions, fullWidth }: POSLayoutProps) {
  const { tenant, loading, error: tenantError, refetchTenant } = usePOS();
  const navigate = useNavigate();

  if (loading) {
    return (
      <POSLoadingState label="Memuat data usaha..." />
    );
  }

  if (tenantError) {
    return (
      <MerchantLayout title={title ?? 'POS'} subtitle={subtitle} actions={actions} fullWidth={fullWidth}>
        <POSErrorState title="Data usaha belum dapat dimuat" description={tenantError} onRetry={() => void refetchTenant()} />
      </MerchantLayout>
    );
  }

  if (!tenant) {
    return (
      <MerchantLayout title="Siapkan POS" subtitle="Aktifkan kasir dan operasional outlet dari workspace merchant">
        <div className="flex min-h-[calc(100dvh-10rem)] items-center justify-center p-4">
          <div className="w-full max-w-sm rounded-2xl border border-primary/20 bg-card p-6 text-center shadow-sm">
            <h2 className="text-xl font-bold">Aktifkan POS untuk toko Anda</h2>
            <p className="mt-2 text-sm leading-6 text-muted-foreground">
              Buat workspace POS dan outlet pertama untuk mulai menggunakan kasir. Data toko online Anda tetap berada di workspace merchant yang sama.
            </p>
            <Button onClick={() => navigate('/merchant/pos/setup')} className="mt-4 w-full">
              Siapkan POS Sekarang
            </Button>
          </div>
        </div>
      </MerchantLayout>
    );
  }

  return (
    <MerchantLayout
      title={title ?? 'POS'}
      subtitle={subtitle}
      actions={actions}
      fullWidth={fullWidth}
    >
      <ErrorBoundary
        fallback={
          <POSErrorState
            title="Halaman POS belum dapat ditampilkan"
            description="Terjadi kendala saat menampilkan modul ini. Muat ulang untuk mengambil data terbaru."
            onRetry={() => window.location.reload()}
          />
        }
      >
        {children}
      </ErrorBoundary>
    </MerchantLayout>
  );
}
