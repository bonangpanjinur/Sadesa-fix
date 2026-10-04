import { LayoutDashboard, MoreHorizontal, Package, ShoppingBag } from 'lucide-react';
import { Link, useLocation } from 'react-router-dom';
import { cn } from '@/lib/utils';

const QUICK_DESTINATIONS = [
  { label: 'Beranda', href: '/merchant', icon: LayoutDashboard },
  { label: 'Pesanan', href: '/merchant/orders', icon: ShoppingBag },
  { label: 'Produk', href: '/merchant/products', icon: Package },
] as const;

interface MerchantBottomNavigationProps {
  menuExpanded: boolean;
  onOpenMenu: (trigger: HTMLButtonElement) => void;
}

function isDestinationActive(pathname: string, href: string) {
  if (href === '/merchant') return pathname === href;
  return pathname === href || pathname.startsWith(`${href}/`);
}

export function MerchantBottomNavigation({ menuExpanded, onOpenMenu }: MerchantBottomNavigationProps) {
  const { pathname } = useLocation();
  const activeQuickDestination = QUICK_DESTINATIONS.some((item) => isDestinationActive(pathname, item.href));
  const menuIsCurrent = !activeQuickDestination;

  return (
    <nav
      aria-label="Navigasi cepat pedagang"
      className="fixed inset-x-0 bottom-0 z-30 border-t border-border bg-background/95 pb-[env(safe-area-inset-bottom)] shadow-[0_-4px_12px_rgba(0,0,0,0.06)] backdrop-blur supports-[backdrop-filter]:bg-background/85 lg:hidden"
    >
      <div className="mx-auto grid h-16 max-w-xl grid-cols-4 items-center px-2">
        {QUICK_DESTINATIONS.map(({ label, href, icon: Icon }) => {
          const active = isDestinationActive(pathname, href);
          return (
            <Link
              key={href}
              to={href}
              aria-current={active ? 'page' : undefined}
              className={cn(
                'group flex h-14 min-w-0 flex-col items-center justify-center gap-0.5 rounded-xl px-1 text-[10px] transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2',
                active ? 'font-semibold text-primary' : 'font-medium text-muted-foreground hover:text-foreground',
              )}
            >
              <span className={cn(
                'flex h-7 w-12 items-center justify-center rounded-full transition-colors',
                active ? 'bg-primary/10' : 'group-hover:bg-muted',
              )}>
                <Icon className="h-[1.125rem] w-[1.125rem]" strokeWidth={active ? 2.4 : 1.9} aria-hidden="true" />
              </span>
              <span className="truncate">{label}</span>
            </Link>
          );
        })}
        <button
          type="button"
          aria-label="Buka semua menu pedagang"
          aria-controls="merchant-mobile-drawer"
          aria-haspopup="dialog"
          aria-expanded={menuExpanded}
          aria-current={menuIsCurrent ? 'page' : undefined}
          onClick={(event) => onOpenMenu(event.currentTarget)}
          className={cn(
            'group flex h-14 min-w-0 flex-col items-center justify-center gap-0.5 rounded-xl px-1 text-[10px] transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2',
            menuIsCurrent ? 'font-semibold text-primary' : 'font-medium text-muted-foreground hover:text-foreground',
          )}
        >
          <span className={cn(
            'flex h-7 w-12 items-center justify-center rounded-full transition-colors',
            menuIsCurrent ? 'bg-primary/10' : 'group-hover:bg-muted',
          )}>
            <MoreHorizontal className="h-5 w-5" strokeWidth={menuIsCurrent ? 2.4 : 1.9} aria-hidden="true" />
          </span>
          <span>Menu</span>
        </button>
      </div>
    </nav>
  );
}
