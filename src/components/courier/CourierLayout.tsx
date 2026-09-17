import { ReactNode, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { Menu, X, LayoutDashboard, Bike, Package, History, Wallet } from 'lucide-react';
import { CourierSidebar } from './CourierSidebar';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

interface CourierLayoutProps { children: ReactNode; title: string; subtitle?: string; }

const mobileNav = [
  { label: 'Dashboard', href: '/courier', icon: LayoutDashboard },
  { label: 'Ojek', href: '/courier/rides', icon: Bike },
  { label: 'Barang', href: '/courier/deliveries', icon: Package },
  { label: 'Riwayat', href: '/courier/history', icon: History },
  { label: 'Pendapatan', href: '/courier/earnings', icon: Wallet },
];

export function CourierLayout({ children, title, subtitle }: CourierLayoutProps) {
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const location = useLocation();
  const isActive = (href: string) => location.pathname === href;

  return (
    <div className="flex min-h-dvh w-full flex-col overflow-x-hidden bg-background">
      {sidebarOpen && (
        <div className="fixed inset-0 z-40 bg-black/50" onClick={() => setSidebarOpen(false)} aria-hidden="true" />
      )}

      {/* Drawer only: it never consumes page width, including on desktop-sized mobile browsers. */}
      <div className={cn(
        'fixed inset-y-0 left-0 z-50 w-72 max-w-[86vw] transform transition-transform duration-200',
        sidebarOpen ? 'translate-x-0' : '-translate-x-full',
      )}>
        <div className="h-full shadow-2xl"><CourierSidebar /></div>
        <Button variant="secondary" size="icon" className="absolute right-2 top-3" onClick={() => setSidebarOpen(false)} aria-label="Tutup menu">
          <X className="h-5 w-5" />
        </Button>
      </div>

      <header className="sticky top-0 z-30 flex min-h-16 items-center gap-3 border-b border-border bg-background/95 px-4 backdrop-blur supports-[backdrop-filter]:bg-background/60 sm:px-6">
        <Button variant="ghost" size="icon" onClick={() => setSidebarOpen(true)} aria-label="Buka menu kurir">
          <Menu className="h-5 w-5" />
        </Button>
        <div className="min-w-0 flex-1">
          <h1 className="truncate text-base font-semibold sm:text-xl">{title}</h1>
          {subtitle && <p className="hidden truncate text-xs text-muted-foreground sm:block">{subtitle}</p>}
        </div>
      </header>

      <main className="min-h-0 w-full flex-1 overflow-x-hidden overflow-y-auto overscroll-contain px-4 pb-24 pt-4 sm:px-6 sm:pt-6">
        <div className="mx-auto w-full max-w-3xl">{children}</div>
      </main>

      <nav className="fixed inset-x-0 bottom-0 z-30 border-t border-border bg-background/95 px-1 pb-[env(safe-area-inset-bottom)] shadow-[0_-4px_16px_rgba(0,0,0,0.06)] backdrop-blur" aria-label="Navigasi kurir">
        <div className="mx-auto grid h-16 w-full max-w-3xl grid-cols-5">
          {mobileNav.map(({ label, href, icon: Icon }) => (
            <Link key={href} to={href} className={cn('flex min-w-0 flex-col items-center justify-center gap-0.5 text-[10px] font-medium transition-colors', isActive(href) ? 'text-primary' : 'text-muted-foreground')}>
              <Icon className={cn('h-5 w-5', isActive(href) && 'stroke-[2.5]')} />
              <span className="truncate">{label}</span>
            </Link>
          ))}
        </div>
      </nav>
    </div>
  );
}
