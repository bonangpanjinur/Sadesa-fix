import { ReactNode, useState } from 'react';
import { MerchantSidebar } from './MerchantSidebar';
import { Menu, Volume2 } from 'lucide-react';
import { NotificationDropdown } from '@/components/notifications/NotificationDropdown';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { ErrorBoundary } from '@/components/ui/ErrorBoundary';
import { MerchantCardError } from './MerchantDataState';
import { unlockOrderNotificationAudio } from '@/lib/orderNotificationSound';
import { OrderAlarmSettingsControl } from '@/components/notifications/OrderAlarmSettingsControl';

interface MerchantLayoutProps {
  children: ReactNode;
  title: string;
  subtitle?: string;
  actions?: ReactNode;
  fullWidth?: boolean;
}

export function MerchantLayout({ children, title, subtitle, actions, fullWidth = false }: MerchantLayoutProps) {
  const [sidebarOpen, setSidebarOpen] = useState(false);

  return (
    <div className="fixed inset-0 flex overflow-hidden bg-background">
      {sidebarOpen && (
        <div
          className="fixed inset-0 bg-foreground/50 z-40 lg:hidden"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      <div
        className={cn(
          'fixed inset-y-0 left-0 z-50 lg:relative lg:z-0 transform transition-transform duration-200',
          sidebarOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'
        )}
      >
        <MerchantSidebar
          onClose={() => setSidebarOpen(false)}
          onNavigate={() => setSidebarOpen(false)}
        />
      </div>

      <div className="flex min-h-0 min-w-0 flex-1 flex-col">
        {/* Header (Fixed) */}
        <div className="sticky top-0 z-30 flex flex-wrap items-center justify-between gap-2 border-b border-border bg-background/95 p-3 backdrop-blur supports-[backdrop-filter]:bg-background/60 sm:p-4 lg:px-8">
          <div className="flex min-w-0 flex-1 items-center gap-2 sm:gap-3">
            <Button variant="ghost" size="icon" className="lg:hidden" onClick={() => setSidebarOpen(true)} aria-label="Buka navigasi pedagang" title="Buka navigasi pedagang">
              <Menu className="h-5 w-5" />
            </Button>
            <div className="min-w-0">
              <h1 className="font-semibold lg:text-xl truncate">{title}</h1>
              {subtitle && <p className="hidden lg:block text-muted-foreground text-xs">{subtitle}</p>}
            </div>
          </div>
          <div className="flex shrink-0 items-center gap-1.5 sm:gap-2">
            {actions}
            <Button
              variant="outline"
              size="sm"
              className="min-h-9 gap-1.5 text-xs"
              onClick={unlockOrderNotificationAudio}
              aria-label="Aktifkan nada alarm pesanan"
            >
              <Volume2 className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">Aktifkan Nada</span>
            </Button>
            <OrderAlarmSettingsControl audience="merchant" />
            <NotificationDropdown />
          </div>
        </div>

        {/* Content (Scrollable) */}
        <div className={cn(
          'min-h-0 min-w-0 flex-1 scrollbar-subtle',
          fullWidth ? 'overflow-hidden' : 'overflow-x-hidden overflow-y-auto overscroll-contain p-4 lg:p-8',
        )}>
          <div className={fullWidth ? 'h-full min-h-0 min-w-0' : 'mx-auto max-w-6xl'}>
            <ErrorBoundary
              fallback={
                <MerchantCardError
                  message="Halaman merchant mengalami kendala. Coba muat ulang untuk mengambil data terbaru."
                  onRetry={() => window.location.reload()}
                />
              }
            >
              {children}
            </ErrorBoundary>
          </div>
        </div>
      </div>
    </div>
  );
}
