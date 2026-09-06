import { useState, useEffect, useMemo } from 'react';

import { Link, useLocation } from 'react-router-dom';
import { 
  LayoutDashboard, 
  Package, 
  Receipt, 
  Settings, 
  ChevronLeft,
  ChevronDown,
  Store,
  BarChart3,
  Star,
  Percent,
  Wallet,
  CreditCard,
  Zap,
  Ticket,
  Calendar,
  Eye,
  RotateCcw,
  MessageCircle,
  Truck,
  Wallet as WalletIcon,
  MessageSquare,
  FileSpreadsheet,
  Lightbulb,
  Megaphone,
  Images,
  TrendingUp,
  Layers,
  Clock,
  FileText,
  BookOpen,
  Gift
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { usePOS } from '@/contexts/POSContext';
import { canAccessPOSPath } from '@/components/pos/posPermissions';
import { POS_MENU_CATEGORIES } from '@/components/pos/POSSidebar';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';

interface SidebarItem {
  label: string;
  href: string;
  icon: React.ReactNode;
  badge?: number;
}

export function MerchantSidebar() {
  const location = useLocation();
  const { user, roles } = useAuth();
  const { tenant, outlets, activeOutlet, setActiveOutlet, posRole } = usePOS();
  const [pendingOrders, setPendingOrders] = useState(0);
  const [unrepliedReviews, setUnrepliedReviews] = useState(0);
  const [pendingRefunds, setPendingRefunds] = useState(0);
  const [lowStockCount, setLowStockCount] = useState(0);
  const isPOSPath = location.pathname.startsWith('/merchant/pos');
  const canSeePOS = roles.some((role) => role === 'merchant' || role === 'admin');
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
      if (!user) return;
      
      const { data: merchant } = await supabase
        .from('merchants')
        .select('id')
        .eq('user_id', user.id)
        .maybeSingle();

      if (!merchant) return;

      const [ordersRes, reviewsRes, lowStockRes] = await Promise.all([
        supabase
          .from('orders')
          .select('*', { count: 'exact', head: true })
          .eq('merchant_id', merchant.id)
          .in('status', ['NEW', 'PENDING_CONFIRMATION']),
        supabase
          .from('reviews')
          .select('*', { count: 'exact', head: true })
          .eq('merchant_id', merchant.id)
          .is('merchant_reply', null),
        supabase
          .from('products')
          .select('id, stock, low_stock_threshold')
          .eq('merchant_id', merchant.id)
          .eq('is_active', true),
      ]);

      setPendingOrders(ordersRes.count || 0);
      setUnrepliedReviews(reviewsRes.count || 0);
      const lowCount = lowStockRes.data?.filter(p => p.stock <= (p.low_stock_threshold || 5)).length || 0;
      setLowStockCount(lowCount);

      // Refund via merchant orders
      const { data: mOrders } = await supabase
        .from('orders')
        .select('id')
        .eq('merchant_id', merchant.id);
      if (mOrders && mOrders.length > 0) {
        const { count: refCount } = await supabase
          .from('refund_requests')
          .select('*', { count: 'exact', head: true })
          .in('order_id', mOrders.map(o => o.id))
          .eq('status', 'PENDING');
        setPendingRefunds(refCount || 0);
      }
    };

    fetchBadges();

    // P1.2: Real-time badge via SSE — pesanan baru langsung muncul di sidebar
    const channel = supabase
      .channel(`merchant-sidebar-${user.id}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'orders' }, () => {
        fetchBadges();
      })
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'orders' }, () => {
        fetchBadges();
      })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'reviews' }, () => {
        setUnrepliedReviews((prev) => prev + 1);
      })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'refund_requests' }, () => {
        setPendingRefunds((prev) => prev + 1);
      })
      .subscribe();

    return () => {
      // Unsubscribe before removing so a remount cannot reuse a channel that
      // still has an active subscription and reject new postgres_changes hooks.
      void channel.unsubscribe();
      void supabase.removeChannel(channel);
    };
  }, [user]);

  useEffect(() => {
    if (isPOSPath) setPosOpen(true);
  }, [isPOSPath]);

  useEffect(() => {
    try {
      window.localStorage.setItem('merchant-pos-sidebar-categories', JSON.stringify(openPOSCategories));
    } catch {
      // Sidebar preferences are optional.
    }
  }, [openPOSCategories]);

  const visiblePOSCategories = useMemo(() => POS_MENU_CATEGORIES.map((category) => ({
    ...category,
    items: category.items.filter((item) => canAccessPOSPath(roles, item.href, posRole)),
  })).filter((category) => category.items.length > 0), [roles, posRole]);
  const activePOSCategoryId = visiblePOSCategories.find((category) => (
    category.items.some((item) => (
      item.href === '/merchant/pos'
        ? location.pathname === '/merchant/pos'
        : location.pathname.startsWith(item.href)
    ))
  ))?.id;

  useEffect(() => {
    if (!activePOSCategoryId) return;
    setOpenPOSCategories((current) => current[activePOSCategoryId] ? current : {
      ...current,
      [activePOSCategoryId]: true,
    });
  }, [activePOSCategoryId]);

  const menuItems: SidebarItem[] = [
    { label: 'Dashboard', href: '/merchant', icon: <LayoutDashboard className="h-4 w-4" /> },
    { label: 'Pesanan', href: '/merchant/orders', icon: <Receipt className="h-4 w-4" />, badge: pendingOrders },
    { label: 'Fulfillment Parsial', href: '/merchant/fulfillment', icon: <Truck className="h-4 w-4" /> },
    { label: 'Price Book', href: '/merchant/price-book', icon: <BookOpen className="h-4 w-4" /> },
    { label: 'Loyalty Rules', href: '/merchant/loyalty-rules', icon: <Gift className="h-4 w-4" /> },
    { label: 'Produk', href: '/merchant/products', icon: <Package className="h-4 w-4" />, badge: lowStockCount },
    { label: 'Manajemen Stok', href: '/merchant/stock', icon: <Layers className="h-4 w-4" />, badge: lowStockCount > 0 ? lowStockCount : undefined },
    { label: 'Galeri Toko', href: '/merchant/gallery', icon: <Images className="h-4 w-4" /> },
    { label: 'Laporan Keuangan', href: '/merchant/finance', icon: <TrendingUp className="h-4 w-4" /> },
    { label: 'Import / Export', href: '/merchant/import-export', icon: <FileSpreadsheet className="h-4 w-4" /> },
    { label: 'Notifikasi WA', href: '/merchant/notifikasi-wa', icon: <MessageSquare className="h-4 w-4" /> },
    { label: 'Insight Bisnis', href: '/merchant/insight', icon: <Lightbulb className="h-4 w-4" /> },
    { label: 'Iklan Berbayar', href: '/merchant/iklan', icon: <Megaphone className="h-4 w-4" /> },
    { label: 'Analitik', href: '/merchant/analytics', icon: <BarChart3 className="h-4 w-4" /> },
    { label: 'Statistik Pengunjung', href: '/merchant/visitor-stats', icon: <Eye className="h-4 w-4" /> },
    { label: 'Ulasan', href: '/merchant/reviews', icon: <Star className="h-4 w-4" />, badge: unrepliedReviews },
    { label: 'Chat', href: '/merchant/chat', icon: <MessageCircle className="h-4 w-4" /> },
    { label: 'Refund', href: '/merchant/refunds', icon: <RotateCcw className="h-4 w-4" />, badge: pendingRefunds },
    { label: 'Flash Sale', href: '/merchant/flash-sale', icon: <Zap className="h-4 w-4" /> },
    { label: 'Jadwal Promo', href: '/merchant/scheduled-promo', icon: <Calendar className="h-4 w-4" /> },
    { label: 'Voucher', href: '/merchant/vouchers', icon: <Ticket className="h-4 w-4" /> },
    { label: 'Promo', href: '/merchant/promo', icon: <Percent className="h-4 w-4" /> },
    { label: 'Bundle Produk', href: '/merchant/bundle', icon: <Package className="h-4 w-4" /> },
    { label: 'Pre-order & Reservasi', href: '/merchant/preorder', icon: <Clock className="h-4 w-4" /> },
    { label: 'Grosir & B2B', href: '/merchant/grosir', icon: <Layers className="h-4 w-4" /> },
    { label: 'Laporan Pajak', href: '/merchant/pajak', icon: <FileText className="h-4 w-4" /> },
    { label: 'Kuota Transaksi Marketplace', href: '/merchant/subscription', icon: <CreditCard className="h-4 w-4" /> },
    { label: 'Penarikan', href: '/merchant/withdrawal', icon: <Wallet className="h-4 w-4" /> },
    { label: 'Iuran Kas', href: '/merchant/dues', icon: <WalletIcon className="h-4 w-4" /> },
    { label: 'Pengaturan', href: '/merchant/settings', icon: <Settings className="h-4 w-4" /> },
  ];

  return (
    <div className="w-64 h-screen bg-card border-r border-border flex flex-col sticky top-0">
      <div className="p-4 border-b border-border">
        <div className="flex items-center gap-2">
          <Store className="h-6 w-6 text-primary" />
          <span className="font-semibold text-lg">Merchant & POS</span>
        </div>
      </div>

      <nav className="flex-1 p-3 space-y-1 overflow-y-auto scrollbar-thin scrollbar-thumb-border">
        {menuItems.map((item) => {
          const isActive = item.href === '/merchant' 
            ? location.pathname === '/merchant' 
            : location.pathname.startsWith(item.href);
          
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
        {canSeePOS && (
          <section className="mt-3 rounded-lg border border-emerald-200/70 bg-emerald-50/30 p-1">
            <button
              type="button"
              aria-expanded={posOpen}
              onClick={() => setPosOpen((current) => !current)}
              className={cn(
                'flex w-full items-center justify-between rounded-lg px-3 py-2.5 text-left text-sm font-semibold transition-colors',
                isPOSPath ? 'bg-emerald-100 text-emerald-800' : 'text-foreground hover:bg-emerald-100/70'
              )}
            >
              <span className="flex min-w-0 items-center gap-3">
                <Receipt className="h-4 w-4 text-emerald-600" />
                <span className="truncate">Kasir & POS</span>
                <span className="rounded-full bg-emerald-100 px-1.5 py-0.5 text-[10px] font-medium text-emerald-700">
                  {visiblePOSCategories.reduce((total, category) => total + category.items.length, 0)}
                </span>
              </span>
              <ChevronDown className={cn('h-4 w-4 shrink-0 text-emerald-700 transition-transform', !posOpen && '-rotate-90')} />
            </button>

            {posOpen && (
              <div className="mt-1 space-y-1 px-1 pb-1">
                <div className="rounded-lg border border-emerald-100 bg-card p-2">
                  <div className="mb-2 flex items-center gap-2 px-2 text-xs font-semibold text-emerald-700">
                    <Store className="h-3.5 w-3.5" />
                    {tenant?.name || 'POS belum disiapkan'}
                  </div>
                  {outlets.length > 1 && (
                    <Select value={activeOutlet?.id} onValueChange={(value) => {
                      const outlet = outlets.find((outlet) => outlet.id === value);
                      if (outlet) setActiveOutlet(outlet);
                    }}>
                      <SelectTrigger className="h-8 text-xs">
                        <SelectValue placeholder="Pilih outlet" />
                      </SelectTrigger>
                      <SelectContent>
                        {outlets.map((outlet) => (
                          <SelectItem key={outlet.id} value={outlet.id} className="text-xs">
                            {outlet.name}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                  {outlets.length === 1 && activeOutlet && (
                    <div className="truncate rounded bg-muted px-2 py-1 text-xs text-muted-foreground">
                      📍 {activeOutlet.name}
                    </div>
                  )}
                  <Link
                    to="/merchant/pos/subscribe"
                    className="mt-2 flex items-center gap-2 rounded-lg px-2 py-2 text-xs font-medium text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
                  >
                    <CreditCard className="h-3.5 w-3.5" />
                    Langganan POS
                  </Link>
                </div>

                {visiblePOSCategories.map((category) => {
                  const isOpen = Boolean(openPOSCategories[category.id]);
                  const hasActiveItem = category.id === activePOSCategoryId;
                  return (
                    <div key={category.id} className="rounded-lg">
                      <button
                        type="button"
                        aria-expanded={isOpen}
                        onClick={() => setOpenPOSCategories((current) => ({
                          ...current,
                          [category.id]: !current[category.id],
                        }))}
                        className={cn(
                          'flex w-full items-center justify-between rounded-lg px-3 py-2 text-left text-xs font-semibold transition-colors',
                          hasActiveItem ? 'text-emerald-700' : 'text-muted-foreground hover:bg-secondary'
                        )}
                      >
                        <span className="flex min-w-0 items-center gap-2">
                          <span className={cn(hasActiveItem ? 'text-emerald-600' : 'text-muted-foreground')}>
                            {category.icon}
                          </span>
                          <span className="truncate">{category.label}</span>
                          <span className="rounded-full bg-muted px-1.5 py-0.5 text-[10px] font-medium text-muted-foreground">
                            {category.items.length}
                          </span>
                        </span>
                        <ChevronDown className={cn('h-3.5 w-3.5 shrink-0 transition-transform', !isOpen && '-rotate-90')} />
                      </button>
                      {isOpen && (
                        <div className="space-y-0.5 pl-2">
                          {category.items.map((item) => {
                            const isActive = item.href === '/merchant/pos'
                              ? location.pathname === '/merchant/pos'
                              : location.pathname.startsWith(item.href);
                            return (
                              <Link
                                key={item.href}
                                to={item.href}
                                aria-current={isActive ? 'page' : undefined}
                                className={cn(
                                  'flex items-center justify-between rounded-lg px-3 py-2 text-xs font-medium transition-colors',
                                  isActive
                                    ? 'bg-emerald-600 text-white shadow-sm'
                                    : 'text-muted-foreground hover:bg-secondary hover:text-foreground'
                                )}
                              >
                                <span className="flex min-w-0 items-center gap-2">
                                  {item.icon}
                                  <span className="truncate">{item.label}</span>
                                </span>
                                {item.badge !== undefined && item.badge > 0 && (
                                  <span className="rounded-full bg-destructive px-1.5 py-0.5 text-xs text-white">
                                    {item.badge}
                                  </span>
                                )}
                              </Link>
                            );
                          })}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </section>
        )}
      </nav>

      <div className="p-3 border-t border-border">
        <Link
          to="/"
          className="flex items-center gap-2 px-3 py-2.5 rounded-lg text-sm font-medium text-muted-foreground hover:bg-secondary hover:text-foreground transition-colors"
        >
          <ChevronLeft className="h-4 w-4" />
          Kembali ke Aplikasi
        </Link>
      </div>
    </div>
  );
}
