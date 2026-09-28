import { Apple, Bike, Coffee, Package, ShoppingBasket, Sprout, Shapes, UtensilsCrossed, Wheat, Wrench, type LucideIcon } from 'lucide-react';
import { Link } from 'react-router-dom';
import { useAdminCategories } from '@/hooks/useAdminCategories';

const categoryIcons: Record<string, LucideIcon> = {
  buah: Apple,
  kuliner: UtensilsCrossed,
  makanan: UtensilsCrossed,
  minuman: Coffee,
  sembako: ShoppingBasket,
  kelontongan: ShoppingBasket,
  kerajinan: Shapes,
  kriya: Shapes,
  pertanian: Sprout,
  peternakan: Wheat,
  perikanan: Wheat,
  jasa: Wrench,
  ojek: Bike,
};

function getCategoryIcon(slug: string, icon?: string | null) {
  const normalized = slug.toLowerCase().trim();
  if (categoryIcons[normalized]) return categoryIcons[normalized];
  if (icon?.toLowerCase().includes('utensil')) return UtensilsCrossed;
  if (icon?.toLowerCase().includes('shop')) return ShoppingBasket;
  if (icon?.toLowerCase().includes('wrench')) return Wrench;
  return Package;
}

export function ProductCategoryCards() {
  const { data: categories = [], isLoading } = useAdminCategories();
  const parentCategories = categories.filter((category) => !category.parent_id);

  if (isLoading || parentCategories.length === 0) return null;

  return (
    <section className="mx-4 mt-4" aria-labelledby="product-categories-title">
      <div className="mb-2 flex items-center justify-between">
        <h2 id="product-categories-title" className="text-sm font-bold text-foreground">Kategori Produk</h2>
      </div>
      <div className="flex gap-2 overflow-x-auto pb-1 hide-scrollbar">
        {parentCategories.map((category) => {
          const Icon = getCategoryIcon(category.slug, category.icon);
          return (
            <Link
              key={category.id}
              to={`/products?type=${encodeURIComponent(category.slug)}`}
              className="flex min-w-[74px] shrink-0 flex-col items-center gap-1 rounded-xl border border-border/70 bg-card px-2 py-2 text-center transition hover:border-primary/40 hover:bg-primary/5 active:scale-95"
            >
              <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-secondary text-primary">
                <Icon className="h-4 w-4" aria-hidden="true" />
              </span>
              <span className="line-clamp-2 text-[10px] font-medium leading-tight text-foreground">{category.name}</span>
            </Link>
          );
        })}
      </div>
    </section>
  );
}
