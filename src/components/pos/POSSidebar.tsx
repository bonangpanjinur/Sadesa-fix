import { useEffect, useMemo, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import {
  LayoutDashboard, ShoppingCart, ClipboardList, Package, Tag,
  Users, Truck, Archive, BarChart3, UserCog, Settings,
  ChevronLeft, ChevronDown, Store, RotateCcw, ShoppingBag, Wallet,
  TrendingUp, UserCheck, BoxesIcon, PieChart,
  ArrowRightLeft, GitCompare, Shield, KeyRound, Warehouse,
  Ticket, Star, Globe, Banknote, BookOpen,
  FlaskConical, ChefHat, Table2, Tv2,
  Calendar, Clock, DollarSign, Target, CreditCard, QrCode, WifiOff,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { usePOS } from '@/contexts/POSContext';
import { useAuth } from '@/contexts/AuthContext';
import { canAccessPOSPath } from './posPermissions';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';

interface SidebarItem {
  label: string;
  href: string;
  icon: React.ReactNode;
  badge?: number;
}

interface SidebarCategory {
  id: string;
  label: string;
  icon: React.ReactNode;
  items: SidebarItem[];
}

const menuCategories: SidebarCategory[] = [
  {
    id: 'operasional', label: 'Operasional', icon: <ShoppingCart className="h-4 w-4" />,
    items: [
      { label: 'Dashboard', href: '/pos', icon: <LayoutDashboard className="h-4 w-4" /> },
      { label: 'Kasir', href: '/pos/kasir', icon: <ShoppingCart className="h-4 w-4" /> },
      { label: 'Manajemen Meja', href: '/pos/meja', icon: <Table2 className="h-4 w-4" /> },
      { label: 'Menu Digital QR', href: '/pos/menu-qr', icon: <QrCode className="h-4 w-4" /> },
      { label: 'KDS (Dapur)', href: '/pos/kds', icon: <Tv2 className="h-4 w-4" /> },
      { label: 'Transaksi', href: '/pos/transaksi', icon: <ClipboardList className="h-4 w-4" /> },
      { label: 'Retur', href: '/pos/retur', icon: <RotateCcw className="h-4 w-4" /> },
      { label: 'Pembelian', href: '/pos/pembelian', icon: <ShoppingBag className="h-4 w-4" /> },
      { label: 'Kas Harian', href: '/pos/kas', icon: <Wallet className="h-4 w-4" /> },
    ],
  },
  {
    id: 'inventori', label: 'Inventori & Pembelian', icon: <Package className="h-4 w-4" />,
    items: [
      { label: 'Produk', href: '/pos/produk', icon: <Package className="h-4 w-4" /> },
      { label: 'Bahan Baku', href: '/pos/bahan-baku', icon: <FlaskConical className="h-4 w-4" /> },
      { label: 'Resep Produk', href: '/pos/resep', icon: <ChefHat className="h-4 w-4" /> },
      { label: 'Kategori', href: '/pos/kategori', icon: <Tag className="h-4 w-4" /> },
      { label: 'Supplier', href: '/pos/supplier', icon: <Truck className="h-4 w-4" /> },
      { label: 'Hutang Supplier', href: '/pos/hutang', icon: <CreditCard className="h-4 w-4" /> },
      { label: 'Stok', href: '/pos/stok', icon: <Archive className="h-4 w-4" /> },
      { label: 'Transfer Stok', href: '/pos/transfer-stok', icon: <ArrowRightLeft className="h-4 w-4" /> },
      { label: 'Multi-Gudang', href: '/pos/gudang', icon: <Warehouse className="h-4 w-4" /> },
    ],
  },
  {
    id: 'pelanggan', label: 'Pelanggan & Marketing', icon: <Users className="h-4 w-4" />,
    items: [
      { label: 'Customer', href: '/pos/customer', icon: <Users className="h-4 w-4" /> },
      { label: 'Promosi & Voucher', href: '/pos/promosi', icon: <Ticket className="h-4 w-4" /> },
      { label: 'Program Loyalty', href: '/pos/loyalty', icon: <Star className="h-4 w-4" /> },
      { label: 'Analitik Pelanggan', href: '/pos/analitik', icon: <PieChart className="h-4 w-4" /> },
    ],
  },
  {
    id: 'laporan', label: 'Laporan & Analitik', icon: <BarChart3 className="h-4 w-4" />,
    items: [
      { label: 'Lap. Penjualan', href: '/pos/laporan', icon: <BarChart3 className="h-4 w-4" /> },
      { label: 'Lap. Laba Rugi', href: '/pos/laporan/laba-rugi', icon: <TrendingUp className="h-4 w-4" /> },
      { label: 'Lap. Per Kasir', href: '/pos/laporan/kasir', icon: <UserCheck className="h-4 w-4" /> },
      { label: 'Lap. Stok', href: '/pos/laporan/stok', icon: <BoxesIcon className="h-4 w-4" /> },
      { label: 'Lap. Cashflow', href: '/pos/laporan/cashflow', icon: <Banknote className="h-4 w-4" /> },
      { label: 'Lap. Outlet', href: '/pos/laporan/outlet', icon: <GitCompare className="h-4 w-4" /> },
      { label: 'Analitik Produk', href: '/pos/analitik-produk', icon: <TrendingUp className="h-4 w-4" /> },
    ],
  },
  {
    id: 'sdm-keuangan', label: 'Keuangan & SDM', icon: <Wallet className="h-4 w-4" />,
    items: [
      { label: 'Hutang & Piutang', href: '/pos/hutang-piutang', icon: <CreditCard className="h-4 w-4" /> },
      { label: 'Ekspor Akuntansi', href: '/pos/akuntansi', icon: <BookOpen className="h-4 w-4" /> },
      { label: 'Jadwal Shift', href: '/pos/jadwal', icon: <Calendar className="h-4 w-4" /> },
      { label: 'Absensi', href: '/pos/absensi', icon: <Clock className="h-4 w-4" /> },
      { label: 'Penggajian', href: '/pos/penggajian', icon: <DollarSign className="h-4 w-4" /> },
      { label: 'Target Omzet', href: '/pos/target-omzet', icon: <Target className="h-4 w-4" /> },
    ],
  },
  {
    id: 'administrasi', label: 'Administrasi & Integrasi', icon: <Settings className="h-4 w-4" />,
    items: [
      { label: 'Audit Trail', href: '/pos/audit', icon: <Shield className="h-4 w-4" /> },
      { label: 'Offline Conflict Center', href: '/pos/offline-conflicts', icon: <WifiOff className="h-4 w-4" /> },
      { label: 'Manajemen Akses', href: '/pos/akses', icon: <KeyRound className="h-4 w-4" /> },
      { label: 'Pengguna', href: '/pos/pengguna', icon: <UserCog className="h-4 w-4" /> },
      { label: 'Integrasi Marketplace', href: '/pos/integrasi', icon: <Globe className="h-4 w-4" /> },
      { label: 'Pengaturan', href: '/pos/pengaturan', icon: <Settings className="h-4 w-4" /> },
    ],
  },
];

function isItemActive(pathname: string, href: string) {
  return href === '/pos' ? pathname === '/pos' : pathname.startsWith(href);
}

export function POSSidebar() {
  const location = useLocation();
  const { tenant, outlets, activeOutlet, setActiveOutlet, posRole } = usePOS();
  const { roles } = useAuth();
  const visibleCategories = useMemo(() => menuCategories.map((category) => ({
    ...category,
    items: category.items.filter((item) => canAccessPOSPath(roles, item.href, posRole)),
  })).filter((category) => category.items.length > 0), [roles, posRole]);
  const activeCategoryId = visibleCategories.find((category) => category.items.some((item) => isItemActive(location.pathname, item.href)))?.id;
  const [openCategories, setOpenCategories] = useState<Record<string, boolean>>(() => {
    try {
      const stored = window.localStorage.getItem('pos-sidebar-categories');
      return stored ? JSON.parse(stored) as Record<string, boolean> : { operasional: true };
    } catch {
      return { operasional: true };
    }
  });

  useEffect(() => {
    if (!activeCategoryId) return;
    setOpenCategories((current) => current[activeCategoryId] ? current : { ...current, [activeCategoryId]: true });
  }, [activeCategoryId]);

  useEffect(() => {
    try { window.localStorage.setItem('pos-sidebar-categories', JSON.stringify(openCategories)); } catch { /* storage optional */ }
  }, [openCategories]);

  const toggleCategory = (id: string) => {
    setOpenCategories((current) => ({ ...current, [id]: !current[id] }));
  };

  return (
    <div className="flex h-dvh w-64 flex-col border-r border-border bg-card">
      <div className="border-b border-border p-4">
        <div className="mb-3 flex items-center gap-2">
          <Store className="h-5 w-5 text-emerald-600" />
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-bold">{tenant?.name || 'SaDesa POS'}</p>
            <p className="text-xs text-muted-foreground">Sistem Kasir UMKM</p>
          </div>
        </div>
        {outlets.length > 1 && (
          <Select value={activeOutlet?.id} onValueChange={(value) => {
            const outlet = outlets.find((candidate) => candidate.id === value);
            if (outlet) setActiveOutlet(outlet);
          }}>
            <SelectTrigger className="h-8 text-xs"><SelectValue placeholder="Pilih outlet" /></SelectTrigger>
            <SelectContent>{outlets.map((outlet) => <SelectItem key={outlet.id} value={outlet.id} className="text-xs">{outlet.name}</SelectItem>)}</SelectContent>
          </Select>
        )}
        {outlets.length === 1 && activeOutlet && <div className="truncate rounded bg-muted px-2 py-1 text-xs text-muted-foreground">📍 {activeOutlet.name}</div>}
      </div>

      <nav aria-label="Navigasi POS" className="min-h-0 flex-1 space-y-1 overflow-y-auto p-3">
        {visibleCategories.map((category) => {
          const isOpen = Boolean(openCategories[category.id]);
          const hasActiveItem = category.id === activeCategoryId;
          return (
            <section key={category.id} aria-label={category.label} className="rounded-lg">
              <button
                type="button"
                aria-expanded={isOpen}
                onClick={() => toggleCategory(category.id)}
                className={cn(
                  'flex w-full items-center justify-between rounded-lg px-3 py-2.5 text-left text-sm font-semibold transition-colors',
                  hasActiveItem ? 'bg-emerald-50 text-emerald-700' : 'text-foreground hover:bg-secondary'
                )}
              >
                <span className="flex min-w-0 items-center gap-3">
                  <span className={cn(hasActiveItem ? 'text-emerald-600' : 'text-muted-foreground')}>{category.icon}</span>
                  <span className="truncate">{category.label}</span>
                  <span className="rounded-full bg-muted px-1.5 py-0.5 text-[10px] font-medium text-muted-foreground">{category.items.length}</span>
                </span>
                <ChevronDown className={cn('h-4 w-4 shrink-0 text-muted-foreground transition-transform', !isOpen && '-rotate-90')} />
              </button>
              {isOpen && (
                <div className="mt-1 space-y-0.5 pl-2">
                  {category.items.map((item) => {
                    const isActive = isItemActive(location.pathname, item.href);
                    return (
                      <Link
                        key={item.href}
                        to={item.href}
                        aria-current={isActive ? 'page' : undefined}
                        className={cn(
                          'flex items-center justify-between rounded-lg px-3 py-2 text-sm font-medium transition-colors',
                          isActive ? 'bg-emerald-600 text-white shadow-sm' : 'text-muted-foreground hover:bg-secondary hover:text-foreground'
                        )}
                      >
                        <span className="flex min-w-0 items-center gap-3">{item.icon}<span className="truncate">{item.label}</span></span>
                        {item.badge !== undefined && item.badge > 0 && <span className="rounded-full bg-destructive px-1.5 py-0.5 text-xs text-white">{item.badge}</span>}
                      </Link>
                    );
                  })}
                </div>
              )}
            </section>
          );
        })}
      </nav>

      <div className="border-t border-border p-3">
        <Link to="/" aria-label="Kembali ke marketplace" className="flex items-center gap-2 rounded-lg px-3 py-2 text-xs font-medium text-muted-foreground transition-colors hover:bg-secondary">
          <ChevronLeft className="h-3.5 w-3.5" /> Kembali ke Marketplace
        </Link>
      </div>
    </div>
  );
}
