import { useState, useEffect } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { 
  LayoutDashboard, Store, Bike, Wrench, ChevronLeft, ClipboardCheck, UsersRound,
  Wallet, BarChart3, TrendingUp, Calendar, Search
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';

interface SidebarItem {
  label: string;
  href: string;
  icon: React.ReactNode;
  badge?: number;
}

export function VerifikatorSidebar() {
  const location = useLocation();
  const { user } = useAuth();
  const [pendingMerchants, setPendingMerchants] = useState(0);
  const [pendingCouriers, setPendingCouriers] = useState(0);
  const [pendingServiceProviders, setPendingServiceProviders] = useState(0);
  const [searchTerm, setSearchTerm] = useState('');

  useEffect(() => {
    const fetchPending = async () => {
      if (!user) return;
      const { data: codes } = await supabase
        .from('verifikator_codes')
        .select('code')
        .eq('verifikator_id', user.id)
        .limit(100);

      if (codes && codes.length > 0) {
        const { count } = await supabase
          .from('merchants')
          .select('*', { count: 'exact', head: true })
          .in('verifikator_code', codes.map(code => code.code))
          .eq('registration_status', 'PENDING');
        setPendingMerchants(count || 0);
      }
      const { data: courierCodes } = await supabase
        .from('verifikator_codes')
        .select('code')
        .eq('verifikator_id', user.id)
        .eq('is_active', true);
      const codeValues = (courierCodes || []).map(item => item.code);
      if (codeValues.length > 0) {
        const { count } = await supabase
          .from('couriers')
          .select('*', { count: 'exact', head: true })
          .in('verifikator_code', codeValues)
          .eq('registration_status', 'PENDING');
        setPendingCouriers(count || 0);
        const { count: pendingProviders } = await supabase
          .from('service_profiles')
          .select('*', { count: 'exact', head: true })
          .in('verifikator_code', codeValues)
          .eq('verification_status', 'PENDING');
        setPendingServiceProviders(pendingProviders || 0);
      } else {
        setPendingCouriers(0);
        setPendingServiceProviders(0);
      }
    };
    fetchPending();
  }, [user]);

  const menuItems: SidebarItem[] = [
    { label: 'Dashboard',       href: '/verifikator',               icon: <LayoutDashboard className="h-4 w-4" /> },
    { label: 'Tim & Antrean',   href: '/verifikator/team',          icon: <UsersRound className="h-4 w-4" /> },
    { label: 'Merchant',        href: '/verifikator/merchants',     icon: <Store className="h-4 w-4" />, badge: pendingMerchants },
    { label: 'Ojek',             href: '/verifikator/couriers',      icon: <Bike className="h-4 w-4" />, badge: pendingCouriers },
    { label: 'Penyedia Jasa',   href: '/verifikator/service-providers', icon: <Wrench className="h-4 w-4" />, badge: pendingServiceProviders },
    { label: 'Laporan Kas',     href: '/verifikator/kas-report',    icon: <BarChart3 className="h-4 w-4" /> },
    { label: 'Pendapatan',      href: '/verifikator/earnings',      icon: <Wallet className="h-4 w-4" /> },
    { label: 'Laporan Ekonomi', href: '/verifikator/ekonomi',       icon: <TrendingUp className="h-4 w-4" /> },
    { label: 'Event Desa',      href: '/verifikator/event-desa',    icon: <Calendar className="h-4 w-4" /> },
  ];
  const normalizedSearch = searchTerm.trim().toLowerCase();
  const visibleMenuItems = normalizedSearch
    ? menuItems.filter((item) => item.label.toLowerCase().includes(normalizedSearch))
    : menuItems;

  return (
    <div className="w-64 h-screen bg-card border-r border-border flex flex-col sticky top-0">
      <div className="p-4 border-b border-border">
        <div className="flex items-center gap-2">
          <ClipboardCheck className="h-6 w-6 text-primary" />
          <span className="font-semibold text-lg">Verifikator</span>
        </div>
      </div>

      <nav className="min-h-0 flex-1 p-3 space-y-1 overflow-y-auto overscroll-contain scrollbar-subtle">
        <div className="mb-3 relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <input
            value={searchTerm}
            onChange={(event) => setSearchTerm(event.target.value)}
            placeholder="Cari menu verifikator..."
            aria-label="Cari menu verifikator"
            className="h-9 w-full rounded-lg border border-border bg-secondary pl-9 pr-3 text-xs outline-none transition focus-visible:ring-2 focus-visible:ring-primary/40"
          />
        </div>
        {visibleMenuItems.map((item) => {
          const isActive = location.pathname === item.href;
          return (
            <Link
              key={item.href}
              to={item.href}
              className={cn(
                "flex items-center justify-between px-3 py-2.5 rounded-lg text-sm font-medium transition-colors",
                isActive
                  ? "bg-primary text-primary-foreground"
                  : "text-muted-foreground hover:bg-secondary hover:text-foreground"
              )}
            >
              <div className="flex items-center gap-3">
                {item.icon}
                {item.label}
              </div>
              {item.badge !== undefined && item.badge > 0 && (
                <span className={cn(
                  "text-xs px-2 py-0.5 rounded-full",
                  isActive
                    ? "bg-primary-foreground/20 text-primary-foreground"
                    : "bg-destructive text-destructive-foreground"
                )}>
                  {item.badge}
                </span>
              )}
            </Link>
          );
        })}
        {visibleMenuItems.length === 0 && (
          <p className="px-3 py-8 text-center text-xs text-muted-foreground">Menu tidak ditemukan.</p>
        )}
      </nav>

      <div className="p-3 border-t border-border">
        <Link
          to="/"
          state={{ skipRoleRedirect: true }}
          className="flex items-center gap-2 px-3 py-2.5 rounded-lg text-sm font-medium text-muted-foreground hover:bg-secondary hover:text-foreground transition-colors"
        >
          <ChevronLeft className="h-4 w-4" />
          Kembali ke Aplikasi
        </Link>
      </div>
    </div>
  );
}
