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
import { POS_MENU_CATEGORIES } from '@/components/pos/POSSidebar';
import { canAccessPOSPath } from '@/components/pos/posPermissions';
import { useAuth } from '@/contexts/AuthContext';
import { usePOS } from '@/contexts/POSContext';
import { supabase } from '@/integrations/supabase/client';
import { cn } from '@/lib/utils';

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

function isItemActive(pathname: string, href: string) {
  if (href === '/merchant' || href === '/merchant/pos') return pathname === href;
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
  const isPOSPath = location.pathname.startsWith('/merchant/pos');
  const canSeePOS = roles.some((role) => role === 'merchant' || role === 'admin');
  const [openGroupId, setOpenGroupId] = useState<string | null>(() => {
    try {
      return window.localStorage.getItem('merchant-sidebar-group') || 'sales';
    } catch {
      return 'sales';
    }
  });
  const [posOpen, setPosOpen] = useState(isPOSPath);
  const [openPOSCategories, setOpenPOSCategories] = useState<Record<string, boolean>>(() => {
    try {
      const stored = window.localStorage.getItem('merchant-pos-sidebar-categories');
      return stored ? JSON.parse(stored) as Record<string, boolean> : { operasional: true };
    } catch {
      return { operasional: true };
    }
  });

  useEffect(() => {
    if (!user) return;

    const fetchBadges = async () => {
      const { data: merchant } = await supabase
        .from('merchants')
        .select('id')
        .eq('user_id', user.id)
        .maybeSingle();

      if (!merchant) return;

      const [ordersRes, reviewsRes, lowStockRes] = await Promise.all([
        supabase.from('orders').select('*', { count: 'exact', head: true }).eq('merchant_id', merchant.id).in('status', ['NEW', 'PENDING_CONFIRMATION']),
        supabase.from('reviews').select('*', { count: 'exact', head: true }).eq('merchant_id', merchant.id).is('merchant_reply', null),
        supabase.from('products').select('id, stock, low_stock_threshold').eq('merchant_id', merchant.id).eq('is_active', true),
      ]);

      setPendingOrders(ordersRes.count || 0);
      setUnrepliedReviews(reviewsRes.count || 0);
      setLowStockCount(lowStockRes.data?.filter((product) => product.stock <= (product.low_stock_threshold || 5)).length || 0);

      const { data: merchantOrders } = await supabase.from('orders').select('id').eq('merchant_id', merchant.id);
      if (merchantOrders && merchantOrders.length > 0) {
        const { count } = await supabase
          .from('refund_requests')
          .select('*', { count: 'exact', head: true })
          .in('order_id', merchantOrders.map((order) => order.id))
          .eq('status', 'PENDING');
        setPendingRefunds(count || 0);
      }
    };

    void fetchBadges();
    const channel = supabase
      .channel(`merchant-sidebar-${user.id}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'orders' }, () => void fetchBadges())
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'orders' }, () => void fetchBadges())
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'reviews' }, () => setUnrepliedReviews((count) => count + 1))
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'refund_requests' }, () => setPendingRefunds((count) => count + 1))
      .subscribe();

    return () => {
      void channel.unsubscribe();
      void supabase.removeChannel(channel);
    };
  }, [user]);

  const groups = useMemo<SidebarGroup[]>(() => [
    {
      id: 'sales', label: 'Penjualan', icon: <ShoppingBag className="h-4 w-4" />, items: [
        { label: 'Pesanan', href: '/merchant/orders', icon: <Receipt className="h-4 w-4" />, badge: pendingOrders },
        { label: 'Fulfillment Parsial', href: '/merchant/fulfillment', icon: <Truck className="h-4 w-4" /> },
        { label: 'Refund', href: '/merchant/refunds', icon: <RotateCcw className="h-4 w-4" />, badge: pendingRefunds },
        { label: 'Chat', href: '/merchant/chat', icon: <MessageCircle className="h-4 w-4" /> },
      ],
    },
    {
      id: 'catalog', label: 'Produk & Stok', icon: <Package className="h-4 w-4" />, items: [
        { label: 'Produk', href: '/merchant/products', icon: <Package className="h-4 w-4" />, badge: lowStockCount },
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
      id: 'insights', label: 'Analitik & Keuangan', icon: <BarChart3 className="h-4 w-4" />, items: [
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
  ], [lowStockCount, pendingOrders, pendingRefunds, unrepliedReviews]);

  const visiblePOSCategories = useMemo(() => POS_MENU_CATEGORIES.map((category) => ({
    ...category,
    items: category.items.filter((item) => canAccessPOSPath(roles, item.href, posRole)),
  })).filter((category) => category.items.length > 0), [roles, posRole]);

  const activeMerchantGroupId = groups.find((group) => group.items.some((item) => isItemActive(location.pathname, item.href)))?.id;
  const activePOSCategoryId = visiblePOSCategories.find((category) => category.items.some((item) => isItemActive(location.pathname, item.href)))?.id;

  useEffect(() => {
    if (isPOSPath) {
      setPosOpen(true);
      setOpenGroupId(null);
      return;
    }
    if (activeMerchantGroupId) {
      setOpenGroupId(activeMerchantGroupId);
      setPosOpen(false);
    }
  }, [activeMerchantGroupId, isPOSPath]);

  useEffect(() => {
    if (!activePOSCategoryId) return;
    setOpenPOSCategories({ [activePOSCategoryId]: true });
  }, [activePOSCategoryId]);

  useEffect(() => {
    try {
      if (openGroupId) window.localStorage.setItem('merchant-sidebar-group', openGroupId);
      window.localStorage.setItem('merchant-pos-sidebar-categories', JSON.stringify(openPOSCategories));
    } catch {
      // Sidebar preferences are optional.
    }
  }, [openGroupId, openPOSCategories]);

  const toggleMerchantGroup = (id: string) => {
    setOpenGroupId((current) => current === id ? null : id);
    setPosOpen(false);
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
    <aside className="flex h-dvh w-[min(18rem,calc(100vw-2rem))] flex-col border-r border-sidebar-border bg-sidebar font-body text-sidebar-foreground lg:w-72" aria-label="Navigasi merchant dan POS">
      <div className="flex h-16 shrink-0 items-center justify-between border-b border-sidebar-border px-5">
        <Link to="/merchant" onClick={onNavigate} className="flex min-w-0 items-center gap-3">
          <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-sidebar-primary text-sidebar-primary-foreground">
            <Store className="h-5 w-5" />
          </span>
          <span className="truncate font-heading text-sm font-semibold">Merchant & POS</span>
        </Link>
        <Button type="button" variant="ghost" size="icon" className="h-9 w-9 lg:hidden" onClick={onClose} aria-label="Tutup navigasi">
          <X className="h-5 w-5" />
        </Button>
      </div>

      <nav className="min-h-0 flex-1 overflow-y-auto py-4" aria-label="Menu merchant">
        <p className="mb-2 px-5 font-heading text-[10px] font-bold uppercase text-muted-foreground">Merchant</p>
        {renderItem({ label: 'Dashboard', href: '/merchant', icon: <LayoutDashboard className="h-4 w-4" /> })}

        <div className="mt-2 space-y-0.5">
          {groups.map((group) => {
            const open = openGroupId === group.id;
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
        </div>

        {canSeePOS && (
          <section className="mt-5 border-t border-sidebar-border pt-4" aria-label="Point of Sale">
            <p className="mb-2 px-5 font-heading text-[10px] font-bold uppercase text-muted-foreground">Point of Sale</p>
            <Button
              type="button"
              variant="ghost"
              aria-expanded={posOpen}
              onClick={() => {
                setPosOpen((current) => !current);
                setOpenGroupId(null);
              }}
              className={cn(
                'h-10 w-full justify-between rounded-none border-l-2 px-4 font-body text-sm',
                isPOSPath ? 'border-sidebar-primary bg-sidebar-accent text-sidebar-accent-foreground' : 'border-transparent text-sidebar-foreground',
              )}
            >
              <span className="flex min-w-0 items-center gap-3">
                <Receipt className={cn('h-4 w-4 shrink-0 text-muted-foreground', isPOSPath && 'text-sidebar-primary')} />
                <span className="truncate">Kasir & POS</span>
                <span className="rounded-full bg-muted px-1.5 py-0.5 text-[10px] font-semibold text-muted-foreground">
                  {visiblePOSCategories.reduce((total, category) => total + category.items.length, 0)}
                </span>
              </span>
              <ChevronDown className={cn('h-4 w-4 shrink-0 text-muted-foreground transition-transform', !posOpen && '-rotate-90')} />
            </Button>

            {posOpen && (
              <div className="pb-1">
                <div className="mx-4 my-2 border-l-2 border-sidebar-border pl-3">
                  <p className="truncate font-heading text-xs font-semibold text-sidebar-foreground">{tenant?.name || 'POS belum disiapkan'}</p>
                  {outlets.length > 1 && (
                    <Select value={activeOutlet?.id} onValueChange={(value) => {
                      const outlet = outlets.find((candidate) => candidate.id === value);
                      if (outlet) setActiveOutlet(outlet);
                    }}>
                      <SelectTrigger className="mt-2 h-8 border-sidebar-border bg-sidebar text-xs"><SelectValue placeholder="Pilih outlet" /></SelectTrigger>
                      <SelectContent>{outlets.map((outlet) => <SelectItem key={outlet.id} value={outlet.id} className="text-xs">{outlet.name}</SelectItem>)}</SelectContent>
                    </Select>
                  )}
                  {outlets.length === 1 && activeOutlet && <p className="mt-1 truncate text-xs text-muted-foreground">{activeOutlet.name}</p>}
                  <Link to="/merchant/pos/subscribe" onClick={onNavigate} className="mt-2 flex items-center gap-2 py-1.5 text-xs font-medium text-muted-foreground transition-colors hover:text-sidebar-primary">
                    <CreditCard className="h-3.5 w-3.5" /> Langganan POS
                  </Link>
                </div>

                {visiblePOSCategories.map((category) => {
                  const open = Boolean(openPOSCategories[category.id]);
                  const active = category.id === activePOSCategoryId;
                  return (
                    <div key={category.id}>
                      <Button
                        type="button"
                        variant="ghost"
                        aria-expanded={open}
                        onClick={() => setOpenPOSCategories((current) => current[category.id] ? {} : { [category.id]: true })}
                        className={cn(
                          'h-10 w-full justify-between rounded-none border-l-2 px-4 pl-7 font-body text-xs',
                          active ? 'border-sidebar-primary text-sidebar-accent-foreground' : 'border-transparent text-muted-foreground',
                        )}
                      >
                        <span className="flex min-w-0 items-center gap-2.5">
                          <span className={cn('shrink-0', active && 'text-sidebar-primary')}>{category.icon}</span>
                          <span className="truncate">{category.label}</span>
                          <span className="text-[10px] text-muted-foreground">{category.items.length}</span>
                        </span>
                        <ChevronDown className={cn('h-3.5 w-3.5 shrink-0 transition-transform', !open && '-rotate-90')} />
                      </Button>
                      {open && <div>{category.items.map((item) => renderItem(item, true))}</div>}
                    </div>
                  );
                })}
              </div>
            )}
          </section>
        )}

        <section className="mt-5 border-t border-sidebar-border pt-4" aria-label="Pengaturan">
          <p className="mb-2 px-5 font-heading text-[10px] font-bold uppercase text-muted-foreground">Pengaturan</p>
          {renderItem({ label: 'Pengaturan Toko', href: '/merchant/settings', icon: <Settings className="h-4 w-4" /> })}
        </section>
      </nav>

      <div className="shrink-0 border-t border-sidebar-border bg-sidebar-accent/50 p-3">
        <Link to="/" onClick={onNavigate} className="flex min-h-10 items-center gap-3 rounded-md px-3 text-sm font-medium text-muted-foreground transition-colors hover:bg-sidebar-accent hover:text-sidebar-foreground">
          <ChevronLeft className="h-4 w-4" />
          <span>Kembali ke Aplikasi</span>
        </Link>
      </div>
    </aside>
  );
}
