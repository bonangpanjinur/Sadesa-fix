import { ReactNode, useCallback, useEffect, useRef, useState } from 'react';
import { MerchantSidebar } from './MerchantSidebar';
import { MerchantBottomNavigation } from './MerchantBottomNavigation';
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
  const [isDesktop, setIsDesktop] = useState(() => (
    typeof window !== 'undefined'
    && typeof window.matchMedia === 'function'
    && window.matchMedia('(min-width: 1024px)').matches
  ));
  const sidebarDialogRef = useRef<HTMLDivElement>(null);
  const sidebarTriggerRef = useRef<HTMLButtonElement>(null);
  const isMobileDialogOpen = sidebarOpen && !isDesktop;
  const isSidebarVisible = sidebarOpen || isDesktop;
  const openSidebar = (trigger: HTMLButtonElement) => {
    sidebarTriggerRef.current = trigger;
    setSidebarOpen(true);
  };
  const setSidebarDialogRef = useCallback((element: HTMLDivElement | null) => {
    sidebarDialogRef.current = element;
    if (element) element.inert = !isSidebarVisible;
  }, [isSidebarVisible]);

  useEffect(() => {
    if (typeof window.matchMedia !== 'function') return;

    const mediaQuery = window.matchMedia('(min-width: 1024px)');
    const updateViewport = (event?: MediaQueryListEvent) => {
      const desktop = event?.matches ?? mediaQuery.matches;
      setIsDesktop(desktop);
      if (desktop) setSidebarOpen(false);
    };

    updateViewport();
    mediaQuery.addEventListener('change', updateViewport);
    return () => mediaQuery.removeEventListener('change', updateViewport);
  }, []);

  useEffect(() => {
    if (!isMobileDialogOpen) return;

    const previousOverflow = document.body.style.overflow;
    const sidebarTrigger = sidebarTriggerRef.current;
    const previousFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    document.body.style.overflow = 'hidden';

    const focusFrame = window.requestAnimationFrame(() => {
      const closeButton = sidebarDialogRef.current?.querySelector<HTMLButtonElement>('[aria-label="Tutup navigasi"]');
      (closeButton ?? sidebarDialogRef.current)?.focus();
    });

    const onDialogKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        setSidebarOpen(false);
        return;
      }

      if (event.key !== 'Tab' || !sidebarDialogRef.current) return;
      const focusable = Array.from(sidebarDialogRef.current.querySelectorAll<HTMLElement>(
        'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
      )).filter((element) => element.getClientRects().length > 0);
      if (!focusable.length) {
        event.preventDefault();
        sidebarDialogRef.current.focus();
        return;
      }

      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && (document.activeElement === first || !sidebarDialogRef.current.contains(document.activeElement))) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && (document.activeElement === last || !sidebarDialogRef.current.contains(document.activeElement))) {
        event.preventDefault();
        first.focus();
      }
    };

    document.addEventListener('keydown', onDialogKeyDown);
    return () => {
      window.cancelAnimationFrame(focusFrame);
      document.removeEventListener('keydown', onDialogKeyDown);
      document.body.style.overflow = previousOverflow;
      if (sidebarTrigger?.isConnected && sidebarTrigger.getClientRects().length > 0) sidebarTrigger.focus();
      else if (previousFocus?.isConnected && previousFocus.getClientRects().length > 0) previousFocus.focus();
    };
  }, [isMobileDialogOpen]);

  return (
    <div className="fixed inset-0 flex overflow-hidden bg-background">
      {isMobileDialogOpen && (
        <button
          type="button"
          aria-label="Tutup menu pedagang"
          aria-hidden="true"
          tabIndex={-1}
          className="fixed inset-0 z-40 cursor-default bg-slate-950/35 backdrop-blur-[1px] lg:hidden"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      <div
        ref={setSidebarDialogRef}
        id="merchant-mobile-drawer"
        role={isMobileDialogOpen ? 'dialog' : undefined}
        aria-modal={isMobileDialogOpen || undefined}
        aria-label={isMobileDialogOpen ? 'Menu pedagang' : undefined}
        aria-hidden={!isSidebarVisible || undefined}
        tabIndex={isMobileDialogOpen ? -1 : undefined}
        className={cn(
          'fixed inset-y-0 left-0 z-50 transform-gpu transition-transform duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] motion-reduce:transition-none lg:relative lg:z-0 lg:translate-x-0',
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
            <Button
              variant="ghost"
              size="icon"
              className="h-11 w-11 rounded-xl lg:hidden"
              onClick={(event) => openSidebar(event.currentTarget)}
              aria-label="Buka navigasi pedagang"
              aria-controls="merchant-mobile-drawer"
              aria-expanded={isMobileDialogOpen}
              title="Buka navigasi pedagang"
            >
              <Menu className="h-5 w-5" />
            </Button>
            <div className="min-w-0">
              <h1 className="font-semibold lg:text-xl truncate">{title}</h1>
              {subtitle && <p className="hidden lg:block text-muted-foreground text-xs">{subtitle}</p>}
            </div>
          </div>
          <div className="flex w-full shrink-0 flex-wrap items-center justify-end gap-1.5 sm:w-auto sm:gap-2">
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
          fullWidth ? 'overflow-hidden' : 'overflow-x-hidden overflow-y-auto overscroll-contain p-4 pb-[calc(6rem+env(safe-area-inset-bottom))] lg:p-8 lg:pb-8',
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
      {!fullWidth && (
        <MerchantBottomNavigation
          menuExpanded={isMobileDialogOpen}
          onOpenMenu={openSidebar}
        />
      )}
    </div>
  );
}
