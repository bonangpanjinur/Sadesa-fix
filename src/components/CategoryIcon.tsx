import { Link } from 'react-router-dom';
import { UtensilsCrossed, Shirt, Shapes, MapPin, Package, ShoppingBasket, Wrench, Sprout, HeartPulse, Bike, Smartphone, Car, House, Calendar, Briefcase } from 'lucide-react';
import { getHomepageCategoryHref } from '@/lib/homeCategories';
import { cn } from '@/lib/utils';

const icons: Record<string, React.ComponentType<{ className?: string }>> = {
  utensils: UtensilsCrossed,
  shirt: Shirt,
  shapes: Shapes,
  'map-location-dot': MapPin,
  'shopping-basket': ShoppingBasket,
  wrench: Wrench,
  sprout: Sprout,
  'heart-pulse': HeartPulse,
  bike: Bike,
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
