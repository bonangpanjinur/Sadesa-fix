import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { Link, useLocation } from 'react-router-dom';
import {
  BarChart3,
  BookOpen,
  Calendar,
  ChevronDown,
  ChevronLeft,
  CircleDollarSign,
  CreditCard,
  Eye,
  FileSpreadsheet,
  FileText,
  Gift,
  Images,
  Layers,
  LayoutDashboard,
  Lightbulb,
  Megaphone,
  MessageCircle,
  MessageSquare,
  Package,
  Percent,
  Receipt,
  RotateCcw,
  Search,
  Settings,
  ShoppingBag,
  Star,
  Store,
  Ticket,
  TrendingUp,
  Truck,
  Wallet,
  X,
  Zap,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { POS_MENU_CATEGORIES } from '@/components/pos/posNavigation';
import { canAccessPOSPath } from '@/components/pos/posPermissionConfig';
import { useAuth } from '@/contexts/AuthContext';
import { usePOS } from '@/contexts/POSContext';
import { supabase } from '@/integrations/supabase/client';
import { cn } from '@/lib/utils';
import { isPOSModuleEnabled, isPOSOperational, isPOSSetupStatus } from '@/lib/posFeatureGate';

interface SidebarItem {
  label: string;
  href: string;
  icon: ReactNode;
  badge?: number;
}

interface SidebarGroup {
  id: string;
  label: string;
  icon: ReactNode;
  items: SidebarItem[];
}

interface MerchantSidebarProps {
  onClose?: () => void;
  onNavigate?: () => void;
}

const POS_GROUP_BY_CATEGORY: Record<string, string> = {
  operasional: 'sales',
  inventori: 'catalog',
  pelanggan: 'customers',
  laporan: 'insights',
  'sdm-keuangan': 'team',
  administrasi: 'team',
};

// POS disembunyikan sementara dari workspace merchant; route dan implementasinya tetap dipertahankan.
const POS_UI_ENABLED = false;

function isItemActive(pathname: string, href: string) {
  if (href === '/merchant') return pathname === href;
  return pathname.startsWith(href);
}

export function MerchantSidebar({ onClose, onNavigate }: MerchantSidebarProps) {
  const location = useLocation();
  const { user, roles } = useAuth();
  const { tenant, outlets, activeOutlet, setActiveOutlet, posRole } = usePOS();
  const [pendingOrders, setPendingOrders] = useState(0);
  const [unrepliedReviews, setUnrepliedReviews] = useState(0);
  const [pendingRefunds, setPendingRefunds] = useState(0);
  const [lowStockCount, setLowStockCount] = useState(0);
  const [searchTerm, setSearchTerm] = useState('');
  const canSeePOS = roles.some((role) => role === 'merchant' || role === 'admin');
  const posEnabled = isPOSOperational(tenant?.status);
  const [openGroupId, setOpenGroupId] = useState<string | null>(() => {
    try {
      return window.localStorage.getItem('merchant-sidebar-group') || 'sales';
    } catch {
      return 'sales';
    }
  });

  useEffect(() => {
    if (!user) {
      setPendingOrders(0);
      setUnrepliedReviews(0);
      setPendingRefunds(0);
      setLowStockCount(0);
      return;
    }

    let active = true;
    let channel: ReturnType<typeof supabase.channel> | null = null;

    const fetchBadges = async (merchantId: string) => {
      const [ordersRes, reviewsRes, lowStockRes] = await Promise.all([
        supabase.from('orders').select('id', { count: 'exact', head: true }).eq('merchant_id', merchantId).in('status', ['NEW', 'PENDING_CONFIRMATION']),
        supabase.from('reviews').select('id', { count: 'exact', head: true }).eq('merchant_id', merchantId).is('merchant_reply', null),
        supabase.from('products').select('id, stock, low_stock_threshold').eq('merchant_id', merchantId).eq('is_active', true),
      ]);

      if (!active) return;
      if (ordersRes.error) console.error('Gagal memuat badge pesanan merchant:', ordersRes.error);
      else setPendingOrders(ordersRes.count || 0);
      if (reviewsRes.error) console.error('Gagal memuat badge ulasan merchant:', reviewsRes.error);
      else setUnrepliedReviews(reviewsRes.count || 0);
      if (lowStockRes.error) console.error('Gagal memuat badge stok merchant:', lowStockRes.error);
      else setLowStockCount(lowStockRes.data?.filter((product) => product.stock <= (product.low_stock_threshold || 5)).length || 0);

      const { data: merchantOrders, error: merchantOrdersError } = await supabase.from('orders').select('id').eq('merchant_id', merchantId);
      if (merchantOrdersError) {
        console.error('Gagal memuat pesanan untuk badge refund merchant:', merchantOrdersError);
        return;
      }
      if (!merchantOrders?.length) {
        setPendingRefunds(0);
        return;
      }

      const { count, error: refundsError } = await supabase
          .from('refund_requests')
          .select('id', { count: 'exact', head: true })
          .in('order_id', merchantOrders.map((order) => order.id))
          .eq('status', 'PENDING');
      if (!active) return;
      if (refundsError) console.error('Gagal memuat badge refund merchant:', refundsError);
      else setPendingRefunds(count || 0);
    };

    const initialize = async () => {
      const { data: merchant, error } = await supabase
        .from('merchants')
        .select('id')
        .eq('user_id', user.id)
        .maybeSingle();

      if (!active) return;
      if (error) {
        console.error('Gagal menentukan merchant aktif untuk badge:', error);
        return;
      }
      if (!merchant) {
        setPendingOrders(0);
        setUnrepliedReviews(0);
        setPendingRefunds(0);
        setLowStockCount(0);
        return;
      }

      const refreshScopedBadges = () => {
        if (active) void fetchBadges(merchant.id);
      };
      channel = supabase
        .channel(`merchant-sidebar-${merchant.id}`)
        .on('postgres_changes', { event: '*', schema: 'public', table: 'orders', filter: `merchant_id=eq.${merchant.id}` }, refreshScopedBadges)
        .on('postgres_changes', { event: '*', schema: 'public', table: 'reviews', filter: `merchant_id=eq.${merchant.id}` }, refreshScopedBadges)
        // Refund rows are linked through order_id, not merchant_id. Invalidate and
        // recompute the merchant-scoped count instead of incrementing globally.
        .on('postgres_changes', { event: '*', schema: 'public', table: 'refund_requests' }, refreshScopedBadges)
        .subscribe();
      void fetchBadges(merchant.id);
    };

    void initialize();

    return () => {
      active = false;
      if (channel) {
        void channel.unsubscribe();
        void supabase.removeChannel(channel);
      }
    };
  }, [user]);

  const groups = useMemo<SidebarGroup[]>(() => [
    {
      id: 'quick-actions', label: 'Aksi cepat', icon: <Zap className="h-4 w-4" />, items: [
        { label: 'Pesanan perlu tindakan', href: '/merchant/orders', icon: <Receipt className="h-4 w-4" />, badge: pendingOrders },
        { label: 'Tambah produk', href: '/merchant/products', icon: <Package className="h-4 w-4" /> },
        { label: 'Manajemen stok', href: '/merchant/stock', icon: <Layers className="h-4 w-4" />, badge: lowStockCount || undefined },
        { label: 'Laporan keuangan', href: '/merchant/finance', icon: <TrendingUp className="h-4 w-4" /> },
      ],
    },
    {
      id: 'sales', label: 'Penjualan & Operasional', icon: <ShoppingBag className="h-4 w-4" />, items: [
        { label: 'Pesanan', href: '/merchant/orders', icon: <Receipt className="h-4 w-4" />, badge: pendingOrders },
        { label: 'Fulfillment Parsial', href: '/merchant/fulfillment', icon: <Truck className="h-4 w-4" /> },
        { label: 'Refund', href: '/merchant/refunds', icon: <RotateCcw className="h-4 w-4" />, badge: pendingRefunds },
        { label: 'Chat', href: '/merchant/chat', icon: <MessageCircle className="h-4 w-4" /> },
      ],
    },
    {
      id: 'catalog', label: 'Katalog, Stok & Pembelian', icon: <Package className="h-4 w-4" />, items: [
        { label: 'Katalog Produk', href: '/merchant/products', icon: <Package className="h-4 w-4" />, badge: lowStockCount },
        { label: 'Belanja dari Admin', href: '/merchant/store', icon: <ShoppingBag className="h-4 w-4" /> },
        { label: 'Manajemen Stok', href: '/merchant/stock', icon: <Layers className="h-4 w-4" />, badge: lowStockCount || undefined },
        { label: 'Price Book', href: '/merchant/price-book', icon: <BookOpen className="h-4 w-4" /> },
        { label: 'Galeri Toko', href: '/merchant/gallery', icon: <Images className="h-4 w-4" /> },
        { label: 'Bundle Produk', href: '/merchant/bundle', icon: <Package className="h-4 w-4" /> },
        { label: 'Pre-order & Reservasi', href: '/merchant/preorder', icon: <Calendar className="h-4 w-4" /> },
        { label: 'Grosir & B2B', href: '/merchant/grosir', icon: <Layers className="h-4 w-4" /> },
      ],
    },
    {
      id: 'customers', label: 'Promosi & Pelanggan', icon: <Ticket className="h-4 w-4" />, items: [
        { label: 'Promo', href: '/merchant/promo', icon: <Percent className="h-4 w-4" /> },
        { label: 'Flash Sale', href: '/merchant/flash-sale', icon: <Zap className="h-4 w-4" /> },
        { label: 'Jadwal Promo', href: '/merchant/scheduled-promo', icon: <Calendar className="h-4 w-4" /> },
        { label: 'Voucher', href: '/merchant/vouchers', icon: <Ticket className="h-4 w-4" /> },
        { label: 'Loyalty Rules', href: '/merchant/loyalty-rules', icon: <Gift className="h-4 w-4" /> },
        { label: 'Ulasan', href: '/merchant/reviews', icon: <Star className="h-4 w-4" />, badge: unrepliedReviews },
        { label: 'Notifikasi WA', href: '/merchant/notifikasi-wa', icon: <MessageSquare className="h-4 w-4" /> },
        { label: 'Iklan Berbayar', href: '/merchant/iklan', icon: <Megaphone className="h-4 w-4" /> },
      ],
    },
    {
      id: 'insights', label: 'Analitik, Laporan & Keuangan', icon: <BarChart3 className="h-4 w-4" />, items: [
        { label: 'Analitik', href: '/merchant/analytics', icon: <BarChart3 className="h-4 w-4" /> },
        { label: 'Statistik Pengunjung', href: '/merchant/visitor-stats', icon: <Eye className="h-4 w-4" /> },
        { label: 'Insight Bisnis', href: '/merchant/insight', icon: <Lightbulb className="h-4 w-4" /> },
        { label: 'Laporan Keuangan', href: '/merchant/finance', icon: <TrendingUp className="h-4 w-4" /> },
        { label: 'Laporan Pajak', href: '/merchant/pajak', icon: <FileText className="h-4 w-4" /> },
        { label: 'Import / Export', href: '/merchant/import-export', icon: <FileSpreadsheet className="h-4 w-4" /> },
        { label: 'Penarikan', href: '/merchant/withdrawal', icon: <Wallet className="h-4 w-4" /> },
        { label: 'Iuran Kas', href: '/merchant/dues', icon: <CircleDollarSign className="h-4 w-4" /> },
        { label: 'Kuota Marketplace', href: '/merchant/subscription', icon: <CreditCard className="h-4 w-4" /> },
      ],
    },
    {
      id: 'team', label: 'Tim, Pengaturan & Integrasi', icon: <Settings className="h-4 w-4" />, items: [
        { label: 'Pengaturan Toko', href: '/merchant/settings', icon: <Settings className="h-4 w-4" /> },
      ],
    },
  ], [lowStockCount, pendingOrders, pendingRefunds, unrepliedReviews]);

  const visiblePOSCategories = useMemo(() => POS_MENU_CATEGORIES.map((category) => ({
    ...category,
    items: category.items.filter((item) => (item.scope === 'merchant' || canAccessPOSPath(roles, item.href, posRole))
      && isPOSModuleEnabled(tenant?.enabled_modules, item.moduleId)),
  })).filter((category) => POS_UI_ENABLED && posEnabled && category.items.length > 0), [posEnabled, roles, posRole, tenant?.enabled_modules]);

  const activeMerchantGroupId = groups.find((group) => group.items.some((item) => isItemActive(location.pathname, item.href)))?.id;
  const normalizedSearch = searchTerm.trim().toLowerCase();
  const showDashboard = !normalizedSearch || 'dashboard'.includes(normalizedSearch);
  const visibleGroups = groups
    .map((group) => ({
      ...group,
      items: normalizedSearch
        ? group.items.filter((item) => item.label.toLowerCase().includes(normalizedSearch))
        : group.items,
    }))
    .filter((group) => group.items.length > 0);
  const visiblePOSCategoriesForSearch = visiblePOSCategories
    .map((category) => ({
      ...category,
      items: normalizedSearch
        ? category.items.filter((item) => item.label.toLowerCase().includes(normalizedSearch))
        : category.items,
    }))
    .filter((category) => category.items.length > 0);
  const hasVisibleMenu = showDashboard || visibleGroups.length > 0 || visiblePOSCategoriesForSearch.length > 0;

  useEffect(() => {
    if (activeMerchantGroupId) {
      setOpenGroupId(activeMerchantGroupId);
    }
  }, [activeMerchantGroupId]);

  useEffect(() => {
    try {
      if (openGroupId) window.localStorage.setItem('merchant-sidebar-group', openGroupId);
    } catch {
      // Sidebar preferences are optional.
    }
  }, [openGroupId]);

  const toggleMerchantGroup = (id: string) => {
    setOpenGroupId((current) => current === id ? null : id);
  };

  const renderItem = (item: SidebarItem, nested = false) => {
    const active = isItemActive(location.pathname, item.href);
    return (
      <Link
        key={item.href}
        to={item.href}
        onClick={onNavigate}
        aria-current={active ? 'page' : undefined}
        className={cn(
          'group relative flex min-h-10 items-center justify-between gap-2 border-l-2 px-4 py-2 text-sm font-medium transition-colors',
          nested && 'pl-11',
          active
            ? 'border-sidebar-primary bg-sidebar-accent text-sidebar-accent-foreground'
            : 'border-transparent text-muted-foreground hover:bg-sidebar-accent/70 hover:text-sidebar-foreground',
        )}
      >
        <span className="flex min-w-0 items-center gap-3">
          <span className={cn('shrink-0', active ? 'text-sidebar-primary' : 'text-muted-foreground group-hover:text-sidebar-primary')}>{item.icon}</span>
          <span className="truncate">{item.label}</span>
        </span>
        {item.badge !== undefined && item.badge > 0 && (
          <span className="min-w-5 shrink-0 rounded-full bg-destructive px-1.5 py-0.5 text-center text-[10px] font-bold leading-none text-destructive-foreground">
            {item.badge > 99 ? '99+' : item.badge}
          </span>
        )}
      </Link>
    );
  };

  return (
    <aside className="flex h-dvh w-[min(17rem,calc(100vw-2rem))] flex-col border-r border-sidebar-border bg-sidebar font-body text-sidebar-foreground lg:w-64" aria-label="Navigasi pedagang dan POS">
      <div className="flex h-16 shrink-0 items-center justify-between border-b border-sidebar-border px-5">
        <Link to="/merchant" onClick={onNavigate} className="flex min-w-0 items-center gap-3">
          <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-sidebar-primary text-sidebar-primary-foreground">
            <Store className="h-5 w-5" />
          </span>
          <span className="truncate font-heading text-sm font-semibold">Ruang Kerja Pedagang</span>
        </Link>
        <Button type="button" variant="ghost" size="icon" className="h-9 w-9 lg:hidden" onClick={onClose} aria-label="Tutup navigasi">
          <X className="h-5 w-5" />
        </Button>
      </div>

      <nav className="min-h-0 flex-1 overflow-y-auto overscroll-contain py-4 scrollbar-subtle" aria-label="Menu pedagang">
        <p className="mb-2 px-5 font-heading text-[10px] font-bold uppercase text-muted-foreground">Pedagang</p>
        <div className="mb-3 px-4">
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <input
              value={searchTerm}
              onChange={(event) => setSearchTerm(event.target.value)}
              placeholder="Cari menu pedagang..."
              aria-label="Cari menu pedagang"
              className="h-9 w-full rounded-lg border border-sidebar-border bg-sidebar-accent/40 pl-9 pr-3 text-xs outline-none transition focus-visible:ring-2 focus-visible:ring-sidebar-primary/40"
            />
          </div>
        </div>
        {showDashboard && renderItem({ label: 'Dashboard', href: '/merchant', icon: <LayoutDashboard className="h-4 w-4" /> })}

        {canSeePOS && POS_UI_ENABLED && (
          <div className="mx-4 mt-4 rounded-lg border border-sidebar-border bg-sidebar-accent/40 p-3">
            <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Toko aktif</p>
            <p className="mt-1 truncate font-heading text-xs font-semibold text-sidebar-foreground">
              {tenant?.name || 'Kasir belum diaktifkan'}
            </p>
            {posEnabled && outlets.length > 1 && (
              <Select value={activeOutlet?.id} onValueChange={(value) => {
                const outlet = outlets.find((candidate) => candidate.id === value);
                if (outlet) setActiveOutlet(outlet);
              }}>
                <SelectTrigger className="mt-2 h-8 border-sidebar-border bg-sidebar text-xs">
                  <SelectValue placeholder="Pilih outlet" />
                </SelectTrigger>
                <SelectContent>
                  {outlets.map((outlet) => (
                    <SelectItem key={outlet.id} value={outlet.id} className="text-xs">{outlet.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            )}
            {posEnabled && outlets.length === 1 && activeOutlet && (
              <p className="mt-1 truncate text-xs text-muted-foreground">{activeOutlet.name}</p>
            )}
            <Link
              to={!tenant ? '/merchant/pos/subscribe' : isPOSSetupStatus(tenant.status) ? '/merchant/pos/setup' : '/merchant/pos/subscribe'}
              onClick={onNavigate}
              className="mt-2 flex items-center gap-2 text-xs font-medium text-muted-foreground transition-colors hover:text-sidebar-primary"
            >
              <CreditCard className="h-3.5 w-3.5" />
              {!tenant ? 'Lihat paket POS' : isPOSSetupStatus(tenant.status) ? 'Lanjutkan setup POS' : 'Kelola langganan POS'}
            </Link>
          </div>
        )}

        <div className="mt-2 space-y-0.5">
          {visibleGroups.map((group) => {
            const open = normalizedSearch.length > 0 || openGroupId === group.id;
            const active = activeMerchantGroupId === group.id;
            return (
              <section key={group.id} aria-label={group.label}>
                <Button
                  type="button"
                  variant="ghost"
                  aria-expanded={open}
                  onClick={() => toggleMerchantGroup(group.id)}
                  className={cn(
                    'h-10 w-full justify-between rounded-none border-l-2 px-4 font-body text-sm',
                    active ? 'border-sidebar-primary text-sidebar-accent-foreground' : 'border-transparent text-sidebar-foreground',
                  )}
                >
                  <span className="flex min-w-0 items-center gap-3">
                    <span className={cn('shrink-0 text-muted-foreground', active && 'text-sidebar-primary')}>{group.icon}</span>
                    <span className="truncate">{group.label}</span>
                  </span>
                  <ChevronDown className={cn('h-4 w-4 shrink-0 text-muted-foreground transition-transform', !open && '-rotate-90')} />
                </Button>
                {open && <div className="pb-1">{group.items.map((item) => renderItem(item, true))}</div>}
              </section>
            );
          })}
          {visiblePOSCategoriesForSearch.length > 0 && (
            <div className="mt-5 border-t border-sidebar-border pt-4">
              <p className="mb-2 px-5 font-heading text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Operasional POS</p>
              {visiblePOSCategoriesForSearch.map((category) => {
                const groupId = `pos:${category.id}`;
                const open = normalizedSearch.length > 0 || openGroupId === groupId;
                const active = category.items.some((item) => isItemActive(location.pathname, item.href));
                return (
                  <section key={category.id} aria-label={category.label}>
                    <Button
                      type="button"
                      variant="ghost"
                      aria-expanded={open}
                      onClick={() => toggleMerchantGroup(groupId)}
                      className={cn(
                        'h-10 w-full justify-between rounded-none border-l-2 px-4 font-body text-sm',
                        active ? 'border-sidebar-primary text-sidebar-accent-foreground' : 'border-transparent text-sidebar-foreground',
                      )}
                    >
                      <span className="flex min-w-0 items-center gap-3">
                        <span className={cn('shrink-0 text-muted-foreground', active && 'text-sidebar-primary')}>{category.icon}</span>
                        <span className="truncate">{category.label}</span>
                      </span>
                      <ChevronDown className={cn('h-4 w-4 shrink-0 text-muted-foreground transition-transform', !open && '-rotate-90')} />
                    </Button>
                    {open && <div className="pb-1">{category.items.map((item) => renderItem({ label: item.label, href: item.href, icon: item.icon, badge: item.badge }, true))}</div>}
                  </section>
                );
              })}
            </div>
          )}
          {!hasVisibleMenu && (
             <p className="px-5 py-8 text-center text-xs text-muted-foreground">Menu tidak ditemukan.</p>
          )}
        </div>
      </nav>

      <div className="shrink-0 border-t border-sidebar-border bg-sidebar-accent/50 p-3">
        <Link to="/" state={{ skipRoleRedirect: true }} onClick={onNavigate} className="flex min-h-10 items-center gap-3 rounded-md px-3 text-sm font-medium text-muted-foreground transition-colors hover:bg-sidebar-accent hover:text-sidebar-foreground">
          <ChevronLeft className="h-4 w-4" />
          <span>Kembali ke Aplikasi</span>
        </Link>
      </div>
    </aside>
  );
}
