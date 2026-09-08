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
          'flex h-14 w-14 items-center justify-center rounded-lg border transition duration-200 shadow-sm',
          'group-hover:-translate-y-0.5 group-hover:shadow-md group-active:scale-95',
          colorClass
        )}
      >
        <Icon className="h-6 w-6" />
      </div>
      <span className="line-clamp-1 w-full text-center text-[10px] font-semibold text-muted-foreground">{name}</span>
    </Link>
  );
}
