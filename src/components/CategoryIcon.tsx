import { Link } from 'react-router-dom';
import { ArrowRight, UtensilsCrossed, Shapes, MapPin, Package, ShoppingBasket, Wrench, Sprout, Bike, Wheat } from 'lucide-react';
import { getHomepageCategoryHref } from '@/lib/homeCategories';
import { cn } from '@/lib/utils';

function MotorcycleIcon({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden="true"
    >
      <circle cx="5.5" cy="17.5" r="2.5" />
      <circle cx="18.5" cy="17.5" r="2.5" />
      <path d="M8 17.5h3.5l2-4h3l2 4h.5" />
      <path d="M10.5 13.5h4l1.5 2.5h-5.5l-1.5-2.5Z" />
      <path d="M13 13.5 11.5 11h3l2 2.5" />
      <path d="M16.5 13.5h2l1-2h1" />
      <path d="M11.5 11H9.75" />
    </svg>
  );
}

const icons: Record<string, React.ComponentType<{ className?: string }>> = {
  utensils: UtensilsCrossed,
  shapes: Shapes,
  'map-location-dot': MapPin,
  'shopping-basket': ShoppingBasket,
  wrench: Wrench,
  sprout: Sprout,
  wheat: Wheat,
  bike: Bike,
};

interface CategoryIconProps {
  id: string;
  name: string;
  icon: string;
  colorClass: string;
  route?: string;
}

export function CategoryIcon({ id, name, icon, colorClass, route }: CategoryIconProps) {
  const Icon = id === 'ojek' ? MotorcycleIcon : icons[icon] || Package;
  const isTransport = id === 'ojek';
  const displayName = isTransport ? 'Ojek & Kurir' : 'Pesan Makanan';
  const description = isTransport ? 'Antar saya atau kirim barang' : 'Makanan & minuman di sekitar kamu';
  
  return (
    <Link
      to={route || getHomepageCategoryHref({ id, name, icon, colorClass })}
      className={cn(
        'group relative min-h-[142px] min-w-0 overflow-hidden rounded-[1.35rem] border p-4 shadow-[0_10px_30px_-18px_hsl(var(--foreground)/0.55)] transition duration-200 hover:-translate-y-0.5 hover:shadow-lg active:scale-[0.98]',
        isTransport
          ? 'border-primary/20 bg-[linear-gradient(145deg,hsl(var(--primary)),hsl(162_70%_20%))] text-primary-foreground'
          : 'border-orange-200/80 bg-[linear-gradient(145deg,hsl(38_100%_97%),hsl(28_100%_92%))] text-foreground',
      )}
    >
      <div className={cn('pointer-events-none absolute -right-7 -top-8 h-24 w-24 rounded-full opacity-40', isTransport ? 'bg-white/10' : 'bg-orange-300/20')} />
      <div 
        className={cn(
          'relative flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl border shadow-sm transition-transform duration-200 group-hover:scale-105',
          isTransport
            ? 'border-primary-foreground/20 bg-primary-foreground/15 text-primary-foreground'
            : 'border-accent/30 bg-card text-accent-foreground',
        )}
      >
        <Icon className="relative h-6 w-6 stroke-[2.1]" />
      </div>
      <span className="relative min-w-0 flex-1 self-end text-left">
        <span className="block truncate font-heading text-[15px] font-bold leading-tight">{displayName}</span>
        <span className={cn('mt-1 block text-[10px] leading-tight', isTransport ? 'text-primary-foreground/75' : 'text-muted-foreground')}>
          {description}
        </span>
      </span>
      <ArrowRight className={cn('absolute bottom-4 right-4 h-4 w-4 shrink-0 transition-transform group-hover:translate-x-0.5', isTransport ? 'text-primary-foreground/80' : 'text-accent-foreground')} />
    </Link>
  );
}
