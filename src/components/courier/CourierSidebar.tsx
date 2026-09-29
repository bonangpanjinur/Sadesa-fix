import { useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import {
  LayoutDashboard,
  Wallet,
  ChevronLeft,
  Bike,
  Package,
  History,
  Banknote,
  MessageCircle,
  PiggyBank,
  Search,
  ShoppingBag,
} from 'lucide-react';
import { cn } from '@/lib/utils';

interface SidebarItem {
  label: string;
  href: string;
  icon: React.ReactNode;
}

interface CourierSidebarProps {
  onNavigate?: () => void;
  chatUnreadCount?: number;
}

export function CourierSidebar({ onNavigate, chatUnreadCount = 0 }: CourierSidebarProps) {
  const location = useLocation();
  const [searchTerm, setSearchTerm] = useState('');

  const menuItems: SidebarItem[] = [
    { label: 'Dashboard', href: '/courier', icon: <LayoutDashboard className="h-4 w-4" /> },
    { label: 'Ojek Desa', href: '/courier/rides', icon: <Bike className="h-4 w-4" /> },
    { label: 'Pengiriman Barang', href: '/courier/deliveries', icon: <Package className="h-4 w-4" /> },
    { label: 'Toko Perlengkapan', href: '/courier/store', icon: <ShoppingBag className="h-4 w-4" /> },
    { label: 'Riwayat Pengiriman', href: '/courier/history', icon: <History className="h-4 w-4" /> },
    { label: 'Chat', href: '/courier/chat', icon: <MessageCircle className="h-4 w-4" /> },
    { label: 'Pendapatan', href: '/courier/earnings', icon: <Wallet className="h-4 w-4" /> },
    { label: 'Setor Saldo', href: '/courier/deposit', icon: <PiggyBank className="h-4 w-4" /> },
    { label: 'Penarikan Saldo', href: '/courier/withdrawal', icon: <Banknote className="h-4 w-4" /> },
  ];
  const normalizedSearch = searchTerm.trim().toLowerCase();
  const visibleMenuItems = normalizedSearch
    ? menuItems.filter((item) => item.label.toLowerCase().includes(normalizedSearch))
    : menuItems;

  return (
    <div className="flex h-[100dvh] w-full flex-col border-r border-border bg-card">
      <div className="border-b border-border p-4">
        <div className="flex items-center gap-2">
          <Bike className="h-6 w-6 shrink-0 text-primary" />
          <span className="text-lg font-semibold">Dashboard Kurir</span>
        </div>
      </div>

      <nav className="scrollbar-subtle min-h-0 flex-1 space-y-1 overflow-y-auto overscroll-contain p-3">
        <div className="relative mb-3">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <input
            value={searchTerm}
            onChange={(event) => setSearchTerm(event.target.value)}
            placeholder="Cari menu kurir..."
            aria-label="Cari menu kurir"
            className="h-9 w-full rounded-lg border border-border bg-secondary pl-9 pr-3 text-xs outline-none transition focus-visible:ring-2 focus-visible:ring-primary/40"
          />
        </div>
        {visibleMenuItems.map((item) => {
          const [itemPath, itemQuery] = item.href.split('?');
          const isActive = location.pathname === itemPath
            && (!itemQuery ? !location.search : location.search.includes(itemQuery));

          return (
            <Link
              key={item.href}
              to={item.href}
              onClick={onNavigate}
              aria-current={isActive ? 'page' : undefined}
              className={cn(
                'flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors',
                isActive
                  ? 'bg-primary text-primary-foreground'
                  : 'text-muted-foreground hover:bg-secondary hover:text-foreground',
              )}
            >
              {item.icon}
              <span className="min-w-0 flex-1 truncate">{item.label}</span>
              {item.href === '/courier/chat' && chatUnreadCount > 0 && (
                <span
                  className="inline-flex min-w-5 items-center justify-center rounded-full bg-destructive px-1.5 py-0.5 text-[10px] font-bold leading-none text-destructive-foreground"
                  aria-label={`${chatUnreadCount} chat belum dibaca`}
                >
                  {chatUnreadCount > 99 ? '99+' : chatUnreadCount}
                </span>
              )}
            </Link>
          );
        })}
        {visibleMenuItems.length === 0 && (
          <p className="px-3 py-8 text-center text-xs text-muted-foreground">Menu tidak ditemukan.</p>
        )}
      </nav>

      <div className="border-t border-border p-3">
        <Link
          to="/"
          state={{ skipRoleRedirect: true }}
          onClick={onNavigate}
          className="flex items-center gap-2 rounded-lg px-3 py-2.5 text-sm font-medium text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
        >
          <ChevronLeft className="h-4 w-4" />
          Kembali ke Aplikasi
        </Link>
      </div>
    </div>
  );
}
