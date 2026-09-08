import { Link } from 'react-router-dom';
import { UtensilsCrossed, Shirt, Shapes, MapPin, Package, ShoppingBasket, Wrench, Sprout, HeartPulse, Smartphone, Car, House, Calendar, Briefcase } from 'lucide-react';
import { getHomepageCategoryHref } from '@/lib/homeCategories';
import { cn } from '@/lib/utils';

function MotorbikeIcon({ className }: { className?: string }) {
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
      <circle cx="6" cy="17.5" r="2.5" />
      <circle cx="18" cy="17.5" r="2.5" />
      <path d="M8.5 17.5h3l2-4h3l1.5 4" />
      <path d="M11.5 17.5 10 13h3l1.5-2.5h2.25l1.5 2" />
      <path d="M14.25 10.5 13 8.25" />
      <circle cx="12.25" cy="6.25" r="1.5" />
      <path d="m12.25 7.75 2 1.5" />
      <path d="M16.5 10.5h1.75" />
    </svg>
  );
}

const icons: Record<string, React.ComponentType<{ className?: string }>> = {
  utensils: UtensilsCrossed,
  shirt: Shirt,
  shapes: Shapes,
  'map-location-dot': MapPin,
  'shopping-basket': ShoppingBasket,
  wrench: Wrench,
  sprout: Sprout,
  'heart-pulse': HeartPulse,
  motorcycle: MotorbikeIcon,
  smartphone: Smartphone,
  car: Car,
  house: House,
  calendar: Calendar,
  briefcase: Briefcase,
};

interface CategoryIconProps {
  id: string;
  name: string;
  icon: string;
  colorClass: string;
  route?: string;
}

export function CategoryIcon({ id, name, icon, colorClass, route }: CategoryIconProps) {
  const Icon = icons[icon] || Package;
  
  return (
    <Link
      to={route || getHomepageCategoryHref({ id, name, icon, colorClass })}
      className="group flex min-w-0 flex-col items-center gap-2"
    >
      <div 
        className={cn(
          'relative flex h-16 w-16 items-center justify-center overflow-hidden rounded-[1.25rem] border-2 border-white/70 shadow-[0_6px_16px_-8px_hsl(var(--foreground)/0.35)] transition-all duration-200',
          'before:pointer-events-none before:absolute before:inset-0 before:bg-white/20 before:opacity-0 before:transition-opacity group-hover:-translate-y-1 group-hover:shadow-[0_12px_20px_-10px_hsl(var(--foreground)/0.45)] group-hover:before:opacity-100 group-active:scale-95',
          colorClass
        )}
      >
        <Icon className="relative h-7 w-7 stroke-[2.25] transition-transform duration-200 group-hover:scale-105" />
      </div>
      <span className="line-clamp-1 w-full text-center text-[11px] font-medium leading-tight text-muted-foreground">{name}</span>
    </Link>
  );
}
