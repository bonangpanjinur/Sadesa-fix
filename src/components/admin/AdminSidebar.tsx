import { useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import {
  Activity,
  BarChart3,
  Bike,
  Bell,
  Clock3,
  ChevronDown,
  ChevronLeft,
  Database,
  DollarSign,
  FileCheck2,
  FileText,
  Gift,
  HeadphonesIcon,
  Image,
  Key,
  LayoutDashboard,
  MessageCircle,
  MapPin,
  Megaphone,
  Package,
  Percent,
  Receipt,
  RotateCcw,
  Search,
  Settings,
  Shield,
  ShieldCheck,
  ShieldOff,
  Smartphone,
  Store,
  Tags,
  TicketCheck,
  Truck,
  Users,
  Wallet,
  X,
} from 'lucide-react';
import { cn } from '@/lib/utils';

interface SidebarItem {
  label: string;
  href: string;
  icon: React.ReactNode;
  badge?: number;
}

interface SidebarGroup {
  label: string;
  items: SidebarItem[];
  defaultOpen?: boolean;
}

interface AdminSidebarProps {
  pendingMerchants?: number;
  pendingVillages?: number;
  pendingCouriers?: number;
  pendingOrders?: number;
  pendingRefunds?: number;
  pendingWithdrawals?: number;
  pendingVerifikatorWithdrawals?: number;
  onClose?: () => void;
}

export function AdminSidebar({
  pendingMerchants = 0,
  pendingVillages = 0,
  pendingCouriers = 0,
  pendingOrders = 0,
  pendingRefunds = 0,
  pendingWithdrawals = 0,
  pendingVerifikatorWithdrawals = 0,
  onClose,
}: AdminSidebarProps) {
  const location = useLocation();
  const [searchTerm, setSearchTerm] = useState('');
  const [openGroups, setOpenGroups] = useState<Record<string, boolean>>({
    Overview: true,
    Operasional: true,
    Keuangan: true,
    Growth: false,
    Compliance: false,
    Sistem: false,
  });

  const groups: SidebarGroup[] = [
    {
      label: 'Overview',
      items: [
        { label: 'Dashboard', href: '/admin', icon: <LayoutDashboard className="h-4 w-4" /> },
        { label: 'Realtime Monitor', href: '/admin/realtime', icon: <Activity className="h-4 w-4" /> },
      ],
    },
    {
      label: 'Operasional',
      items: [
        { label: 'Pesanan', href: '/admin/orders', icon: <Receipt className="h-4 w-4" />, badge: pendingOrders },
        { label: 'Chat Admin', href: '/admin/chat', icon: <MessageCircle className="h-4 w-4" /> },
        { label: 'Pedagang', href: '/admin/merchants', icon: <Store className="h-4 w-4" />, badge: pendingMerchants },
        { label: 'Desa Wisata', href: '/admin/villages', icon: <MapPin className="h-4 w-4" />, badge: pendingVillages },
        { label: 'Ojek', href: '/admin/couriers', icon: <Bike className="h-4 w-4" />, badge: pendingCouriers },
        { label: 'Master Ekspedisi', href: '/admin/expeditions', icon: <Truck className="h-4 w-4" /> },
        { label: 'Kasir POS', href: '/admin/pos', icon: <Receipt className="h-4 w-4" /> },
        { label: 'Paket Kuota Marketplace', href: '/admin/transaction-quota', icon: <Package className="h-4 w-4" /> },
        { label: 'Toko & Komisi Referral', href: '/admin/verifier-commerce', icon: <Store className="h-4 w-4" /> },
        { label: 'Pedagang Tier Gratis', href: '/admin/free-quota', icon: <Clock3 className="h-4 w-4" /> },
        { label: 'Kategori Produk', href: '/admin/categories', icon: <Tags className="h-4 w-4" /> },
        { label: 'Dispute Center', href: '/admin/disputes', icon: <FileText className="h-4 w-4" /> },
        { label: 'Sengketa Jasa', href: '/admin/service-disputes', icon: <ShieldCheck className="h-4 w-4" /> },
      ],
    },
    {
      label: 'Keuangan',
      items: [
        { label: 'Refund', href: '/admin/refunds', icon: <RotateCcw className="h-4 w-4" />, badge: pendingRefunds },
        { label: 'Approval Center', href: '/admin/approval-center', icon: <FileCheck2 className="h-4 w-4" /> },
        { label: 'Penarikan Pedagang', href: '/admin/withdrawals', icon: <RotateCcw className="h-4 w-4" />, badge: pendingWithdrawals },
        { label: 'WD Verifikator', href: '/admin/verifikator-withdrawals', icon: <Wallet className="h-4 w-4" /> },
        { label: 'Komisi Platform', href: '/admin/komisi', icon: <DollarSign className="h-4 w-4" /> },
        { label: 'Komisi Verifikator', href: '/admin/verifikator-commissions', icon: <Percent className="h-4 w-4" />, badge: pendingVerifikatorWithdrawals },
        { label: 'Laporan Keuangan', href: '/admin/finance', icon: <DollarSign className="h-4 w-4" /> },
        { label: 'Escrow Jasa', href: '/admin/services', icon: <ShieldCheck className="h-4 w-4" /> },
        { label: 'Program Cashback', href: '/admin/cashback', icon: <Gift className="h-4 w-4" /> },
      ],
    },
    {
      label: 'Growth',
      items: [
        { label: 'Banner Homepage', href: '/admin/banners', icon: <Image className="h-4 w-4" /> },
        { label: 'Promosi', href: '/admin/promotions', icon: <Megaphone className="h-4 w-4" /> },
        { label: 'Iklan Berbayar', href: '/admin/iklan', icon: <Megaphone className="h-4 w-4" /> },
        { label: 'Laporan Performa Iklan', href: '/admin/iklan/laporan', icon: <BarChart3 className="h-4 w-4" /> },
        { label: 'Broadcast', href: '/admin/broadcast', icon: <Bell className="h-4 w-4" /> },
        { label: 'Push Notification', href: '/admin/push-notification', icon: <Bell className="h-4 w-4" /> },
        { label: 'SEO & Konten', href: '/admin/seo', icon: <Search className="h-4 w-4" /> },
      ],
    },
    {
      label: 'Compliance',
      items: [
        { label: 'Pengguna', href: '/admin/users', icon: <Users className="h-4 w-4" /> },
        { label: 'Sebaran Pengguna', href: '/admin/users/geography', icon: <MapPin className="h-4 w-4" /> },
        { label: 'Role & Permission', href: '/admin/roles', icon: <Shield className="h-4 w-4" /> },
        { label: 'Tim Verifikator', href: '/admin/verifikator-teams', icon: <Users className="h-4 w-4" /> },
        { label: 'Sertifikasi Halal', href: '/admin/halal', icon: <ShieldCheck className="h-4 w-4" /> },
        { label: 'Regulasi Halal', href: '/admin/halal-regulation', icon: <FileText className="h-4 w-4" /> },
        { label: 'Audit Log', href: '/admin/audit-log', icon: <Shield className="h-4 w-4" /> },
        { label: 'Kode Verifikator', href: '/admin/codes', icon: <TicketCheck className="h-4 w-4" /> },
        { label: 'Tiket Support', href: '/admin/support-tickets', icon: <HeadphonesIcon className="h-4 w-4" /> },
      ],
    },
    {
      label: 'Sistem',
      items: [
        { label: 'PWA Devices', href: '/admin/pwa-devices', icon: <Smartphone className="h-4 w-4" /> },
        { label: 'Fraud Blocks', href: '/admin/fraud-blocks', icon: <ShieldOff className="h-4 w-4" /> },
        { label: 'Backup Data', href: '/admin/backup', icon: <Database className="h-4 w-4" /> },
        { label: 'Ojek Desa', href: '/admin/rides', icon: <Activity className="h-4 w-4" /> },
        { label: 'System Logs', href: '/admin/logs', icon: <FileText className="h-4 w-4" /> },
        { label: 'Kesehatan Sistem', href: '/admin/system-health', icon: <Activity className="h-4 w-4" /> },
        { label: 'API Keys', href: '/admin/api-keys', icon: <Key className="h-4 w-4" /> },
        { label: 'Pengaturan', href: '/admin/settings', icon: <Settings className="h-4 w-4" /> },
      ],
    },
  ];

  const normalizedSearch = searchTerm.trim().toLowerCase();
  const visibleGroups = groups
    .map((group) => ({
      ...group,
      items: normalizedSearch
        ? group.items.filter((item) => item.label.toLowerCase().includes(normalizedSearch))
        : group.items,
    }))
    .filter((group) => group.items.length > 0);

  const pendingCount = pendingMerchants + pendingVillages + pendingCouriers + pendingOrders + pendingRefunds + pendingWithdrawals + pendingVerifikatorWithdrawals;
  const isActive = (href: string) => location.pathname === href || (href !== '/admin' && href !== '/admin/users' && location.pathname.startsWith(href));

  const toggleGroup = (label: string) => {
    setOpenGroups((current) => ({ ...current, [label]: !current[label] }));
  };

  return (
    <aside className="w-full h-screen bg-card border-r border-border flex flex-col sticky top-0 overflow-hidden">
      <div className="p-3 sm:p-4 border-b border-border flex items-center justify-between">
        <div className="flex items-center gap-2 min-w-0">
          <div className="h-8 w-8 rounded-xl bg-primary/10 flex items-center justify-center">
            <ShieldCheck className="h-5 w-5 text-primary" />
          </div>
          <div className="min-w-0">
            <span className="font-semibold text-sm sm:text-lg truncate block">Admin Panel</span>
            <span className="text-[10px] text-muted-foreground">Kontrol SaDesa</span>
          </div>
        </div>
        <button onClick={onClose} className="sm:hidden p-1 hover:bg-secondary rounded-md transition-colors" aria-label="Tutup navigasi">
          <X className="h-5 w-5" />
        </button>
      </div>

      <div className="p-3 border-b border-border space-y-3">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <input
            value={searchTerm}
            onChange={(event) => setSearchTerm(event.target.value)}
            placeholder="Cari menu admin..."
            aria-label="Cari menu admin"
            className="w-full h-9 rounded-lg bg-secondary pl-9 pr-3 text-xs outline-none ring-offset-background transition focus-visible:ring-2 focus-visible:ring-primary/40"
          />
        </div>
        <Link
          to="/admin/approval-center"
          onClick={onClose}
          className="flex items-center justify-between rounded-lg border border-border bg-background px-3 py-2 text-xs hover:border-primary/50 hover:bg-primary/5 transition-colors"
        >
          <span className="flex items-center gap-2"><FileCheck2 className="h-4 w-4 text-primary" /> Tugas perlu ditinjau</span>
          <span className={cn('rounded-full px-2 py-0.5 text-[10px] font-semibold', pendingCount > 0 ? 'bg-destructive text-destructive-foreground' : 'bg-muted text-muted-foreground')}>
            {pendingCount}
          </span>
        </Link>
      </div>

      <nav className="min-h-0 flex-1 p-2 sm:p-3 space-y-2 overflow-y-auto overscroll-contain scrollbar-subtle" aria-label="Navigasi admin">
        {visibleGroups.map((group) => {
          const groupOpen = normalizedSearch.length > 0 || openGroups[group.label] === true;
          return (
            <section key={group.label}>
              <button
                type="button"
                onClick={() => toggleGroup(group.label)}
                className="w-full flex items-center justify-between px-2 py-1.5 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground hover:text-foreground transition-colors"
                aria-expanded={groupOpen}
              >
                <span>{group.label}</span>
                <ChevronDown className={cn('h-3.5 w-3.5 transition-transform', groupOpen && 'rotate-180')} />
              </button>
              {groupOpen && (
                <div className="space-y-0.5">
                  {group.items.map((item) => {
                    const active = isActive(item.href);
                    return (
                      <Link
                        key={item.href}
                        to={item.href}
                        onClick={onClose}
                        aria-current={active ? 'page' : undefined}
                        className={cn(
                          'flex items-center justify-between px-2 sm:px-3 py-2 rounded-lg text-xs sm:text-sm font-medium transition-colors group',
                          active ? 'bg-primary text-primary-foreground shadow-sm' : 'text-muted-foreground hover:bg-secondary hover:text-foreground',
                        )}
                      >
                        <span className="flex items-center gap-2 sm:gap-3 min-w-0">
                          <span className="flex-shrink-0">{item.icon}</span>
                          <span className="truncate">{item.label}</span>
                        </span>
                        {item.badge !== undefined && item.badge > 0 && (
                          <span className={cn('text-[10px] px-1.5 py-0.5 rounded-full flex-shrink-0 ml-1 font-semibold', active ? 'bg-primary-foreground/20 text-primary-foreground' : 'bg-destructive text-destructive-foreground')}>
                            {item.badge > 99 ? '99+' : item.badge}
                          </span>
                        )}
                      </Link>
                    );
                  })}
                </div>
              )}
            </section>
          );
        })}
        {visibleGroups.length === 0 && <p className="px-3 py-8 text-center text-xs text-muted-foreground">Menu tidak ditemukan.</p>}
      </nav>

      <div className="p-2 sm:p-3 border-t border-border">
        <Link to="/" state={{ skipRoleRedirect: true }} onClick={onClose} className="flex items-center gap-2 px-2 sm:px-3 py-2 rounded-lg text-xs sm:text-sm font-medium text-muted-foreground hover:bg-secondary hover:text-foreground transition-colors">
          <ChevronLeft className="h-4 w-4 flex-shrink-0" />
          <span className="truncate">Kembali ke Aplikasi</span>
        </Link>
      </div>
    </aside>
  );
}
