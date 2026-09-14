import { ReactNode, useCallback, useEffect, useState } from 'react';
import { AdminSidebar } from './AdminSidebar';
import { fetchAdminStats, clearAllSystemCache } from '@/lib/adminApi';
import { Menu, RefreshCw, X } from 'lucide-react';
import { NotificationDropdown } from '@/components/notifications/NotificationDropdown';
import { Button } from '@/components/ui/button';
import { useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { cn } from '@/lib/utils';
import { supabase } from '@/integrations/supabase/client';

interface AdminLayoutProps {
  children: ReactNode;
  title: string;
  subtitle?: string;
  rightElement?: ReactNode;
}

export function AdminLayout({ children, title, subtitle, rightElement }: AdminLayoutProps) {
  const [pendingMerchants, setPendingMerchants] = useState(0);
  const [pendingVillages, setPendingVillages] = useState(0);
  const [pendingCouriers, setPendingCouriers] = useState(0);
  const [pendingWithdrawals, setPendingWithdrawals] = useState(0);
  const [pendingVerifikatorWithdrawals, setPendingVerifikatorWithdrawals] = useState(0);
  const [pendingOrders, setPendingOrders] = useState(0);
  const [pendingRefunds, setPendingRefunds] = useState(0);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [statsUpdatedAt, setStatsUpdatedAt] = useState<Date | null>(null);
  const queryClient = useQueryClient();

  const loadStats = useCallback(async () => {
    try {
      const stats = await fetchAdminStats();
      setPendingMerchants(stats.pendingMerchants);
      setPendingVillages(stats.pendingVillages);
      setPendingCouriers(stats.pendingCouriers);

      const [merchantWithdrawals, verifikatorWithdrawals, ordersCount, refundsCount] = await Promise.all([
        supabase.from('withdrawal_requests').select('*', { count: 'exact', head: true }).eq('status', 'PENDING'),
        supabase.from('verifikator_withdrawals').select('*', { count: 'exact', head: true }).eq('status', 'PENDING'),
        supabase.from('orders').select('*', { count: 'exact', head: true }).eq('status', 'NEW'),
        supabase.from('refund_requests').select('*', { count: 'exact', head: true }).eq('status', 'PENDING'),
      ]);

      setPendingWithdrawals(merchantWithdrawals.count ?? 0);
      setPendingVerifikatorWithdrawals(verifikatorWithdrawals.count ?? 0);
      setPendingOrders(ordersCount.count ?? 0);
      setPendingRefunds(refundsCount.count ?? 0);
      setStatsUpdatedAt(new Date());
    } catch (error) {
      console.error('Error loading admin stats:', error);
    }
  }, []);

  const handleRefresh = async () => {
    try {
      setIsRefreshing(true);
      await queryClient.invalidateQueries();
      await clearAllSystemCache();
      await loadStats();
      toast.success('Data sistem berhasil disegarkan');
    } catch (error) {
      console.error('Error refreshing data:', error);
      toast.error('Gagal menyegarkan data');
    } finally {
      setIsRefreshing(false);
    }
  };

  useEffect(() => {
    void loadStats();
  }, [loadStats]);

  useEffect(() => {
    const handleResize = () => {
      if (window.innerWidth >= 1024) setSidebarOpen(false);
    };
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  return (
    <div className="flex h-dvh max-h-dvh overflow-hidden bg-background">
      {sidebarOpen && <div className="fixed inset-0 bg-black/50 z-40 lg:hidden" onClick={() => setSidebarOpen(false)} aria-hidden="true" />}

      <div className={cn(
        'w-[min(17rem,calc(100vw-2rem))] sm:w-64 lg:w-64 flex-shrink-0 transition-transform duration-200 ease-out',
        'fixed sm:relative inset-y-0 left-0 z-50 lg:z-0',
        sidebarOpen ? 'translate-x-0' : '-translate-x-full sm:translate-x-0',
      )}>
        <AdminSidebar
          pendingMerchants={pendingMerchants}
          pendingVillages={pendingVillages}
          pendingCouriers={pendingCouriers}
          pendingOrders={pendingOrders}
          pendingRefunds={pendingRefunds}
          pendingWithdrawals={pendingWithdrawals}
          pendingVerifikatorWithdrawals={pendingVerifikatorWithdrawals}
          onClose={() => setSidebarOpen(false)}
        />
      </div>

      <div className="flex min-h-0 min-w-0 flex-1 flex-col h-full w-full">
        <header className="flex items-center justify-between p-3 sm:p-4 lg:px-6 border-b border-border bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60 sticky top-0 z-30 gap-2">
          <div className="flex items-center gap-2 sm:gap-3 min-w-0">
            <Button variant="ghost" size="icon" className="sm:hidden h-8 w-8" onClick={() => setSidebarOpen((open) => !open)} aria-label="Buka navigasi admin">
              {sidebarOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
            </Button>
            <div className="min-w-0">
              <h1 className="font-semibold text-sm sm:text-base lg:text-xl truncate">{title}</h1>
              {subtitle && <p className="text-muted-foreground text-[10px] sm:text-xs lg:text-sm truncate">{subtitle}</p>}
              {statsUpdatedAt && <p className="hidden lg:block text-[10px] text-muted-foreground/70 mt-0.5">Data tugas diperbarui {statsUpdatedAt.toLocaleTimeString('id-ID')}</p>}
            </div>
          </div>
          <div className="flex items-center gap-1 sm:gap-2 flex-shrink-0">
            <Button
              variant="ghost"
              size="icon"
              className={cn('h-8 w-8 sm:h-9 sm:w-9 rounded-full border border-border bg-secondary text-secondary-foreground hover:scale-105 transition', isRefreshing && 'animate-spin')}
              onClick={() => void handleRefresh()}
              disabled={isRefreshing}
              title="Segarkan data"
              aria-label="Segarkan data admin"
            >
              <RefreshCw className="h-4 w-4" />
            </Button>
            <NotificationDropdown />
            {rightElement && <div className="hidden sm:block">{rightElement}</div>}
          </div>
        </header>

        <main className="min-h-0 flex-1 overflow-x-hidden overflow-y-auto overscroll-contain scrollbar-subtle p-3 sm:p-4 lg:p-6 xl:p-8">
          <div className="mx-auto min-w-0 max-w-7xl">{children}</div>
        </main>
      </div>
    </div>
  );
}
