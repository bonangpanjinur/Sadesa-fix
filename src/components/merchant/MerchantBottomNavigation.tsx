import { Boxes, ClipboardList, House, Menu, PackageSearch } from 'lucide-react';
import { Link, useLocation } from 'react-router-dom';
import { cn } from '@/lib/utils';

const QUICK_DESTINATIONS = [
  { label: 'Beranda', href: '/merchant', icon: House },
  { label: 'Pesanan', href: '/merchant/orders', icon: ClipboardList },
  { label: 'Produk', href: '/merchant/products', icon: PackageSearch },
  { label: 'Stok', href: '/merchant/stock', icon: Boxes },
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
      className="fixed inset-x-0 bottom-0 z-30 border-t border-border/80 bg-background/95 pb-[env(safe-area-inset-bottom)] shadow-[0_-8px_24px_rgba(15,23,42,0.08)] backdrop-blur supports-[backdrop-filter]:bg-background/85 lg:hidden"
    >
      <div className="mx-auto grid h-[4.25rem] max-w-xl grid-cols-5 items-center gap-1 px-2 sm:px-4">
        {QUICK_DESTINATIONS.map(({ label, href, icon: Icon }) => {
          const active = isDestinationActive(pathname, href);
          return (
            <Link
              key={href}
              to={href}
              aria-current={active ? 'page' : undefined}
              title={label}
              className={cn(
                'group relative flex h-[3.75rem] min-w-0 flex-col items-center justify-center gap-1 rounded-2xl px-1 text-[10px] transition-all duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 active:scale-95',
                active ? 'font-bold text-primary' : 'font-medium text-muted-foreground hover:bg-muted/70 hover:text-foreground',
              )}
            >
              <span className={cn(
                'relative flex h-7 w-12 items-center justify-center rounded-full transition-all duration-200',
                active ? 'bg-primary/12 text-primary shadow-sm shadow-primary/10' : 'text-muted-foreground group-hover:bg-muted',
              )}>
                <Icon className="h-[1.2rem] w-[1.2rem]" strokeWidth={active ? 2.35 : 1.85} aria-hidden="true" />
                {active && <span className="absolute -bottom-1 h-1 w-1 rounded-full bg-primary" aria-hidden="true" />}
              </span>
              <span className="truncate">{label}</span>
            </Link>
          );
        })}
        <button
          type="button"
          aria-label="Buka semua menu pedagang"
          title="Buka semua menu pedagang"
          aria-controls="merchant-mobile-drawer"
          aria-haspopup="dialog"
          aria-expanded={menuExpanded}
          aria-current={menuIsCurrent ? 'page' : undefined}
          onClick={(event) => onOpenMenu(event.currentTarget)}
          className={cn(
            'group flex h-[3.75rem] min-w-0 flex-col items-center justify-center gap-1 rounded-2xl px-1 text-[10px] transition-all duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 active:scale-95',
            menuIsCurrent ? 'font-bold text-primary' : 'font-medium text-muted-foreground hover:bg-muted/70 hover:text-foreground',
          )}
        >
          <span className={cn(
            'relative flex h-7 w-12 items-center justify-center rounded-full transition-all duration-200',
            menuIsCurrent ? 'bg-primary/12 text-primary shadow-sm shadow-primary/10' : 'text-muted-foreground group-hover:bg-muted',
          )}>
            <Menu className="h-[1.2rem] w-[1.2rem]" strokeWidth={menuIsCurrent ? 2.35 : 1.85} aria-hidden="true" />
            {menuIsCurrent && <span className="absolute -bottom-1 h-1 w-1 rounded-full bg-primary" aria-hidden="true" />}
          </span>
          <span>Menu</span>
        </button>
      </div>
    </nav>
  );
}
