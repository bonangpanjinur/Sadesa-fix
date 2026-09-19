import { useState, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useSearchParams } from 'react-router-dom';
import { motion } from 'framer-motion';
import { MapPin, ArrowUpDown, UtensilsCrossed, Search, SlidersHorizontal } from 'lucide-react';
import { Header } from '../components/layout/Header';
import { BottomNav } from '../components/layout/BottomNav';
import { ProductCard } from '../components/ProductCard';
import { Skeleton } from '../components/ui/skeleton';
import { fetchProducts } from '../lib/api';
import { useUserLocation, sortByDistance } from '../hooks/useUserLocation';
import { cn } from '../lib/utils';
import { FoodFilterSheet, type FoodFilters, type FoodType, defaultFoodFilters } from '../components/product/FoodFilterSheet';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '../components/ui/select';
import type { Product } from '../types';

type SortMode = 'nearest' | 'cheapest' | 'expensive' | 'newest';

function ProductSkeleton() {
  return (
    <div className="overflow-hidden rounded-xl border border-border bg-card">
      <Skeleton className="aspect-square w-full" />
      <div className="space-y-2 p-3"><Skeleton className="h-3 w-3/4" /><Skeleton className="h-4 w-1/2" /><Skeleton className="h-3 w-2/3" /></div>
    </div>
  );
}

function normalize(value: string | undefined) {
  return (value || '').toLowerCase().trim();
}

function isFoodProduct(product: Product) {
  const category = normalize(product.category);
  return ['kuliner', 'makanan', 'minuman', 'camilan', 'sembako', 'snack', 'kopi'].some((keyword) => category.includes(keyword));
}

function matchesFoodType(product: Product, type: FoodType) {
  if (type === 'all') return true;
  const haystack = `${normalize(product.category)} ${normalize(product.name)} ${normalize(product.description)}`;
  if (type === 'minuman') return /minum|kopi|teh|jus|susu|es |cokelat|cafe|latte|smoothie|drink/.test(haystack);
  if (type === 'camilan') return /camil|snack|goreng|keripik|roti|kue|dessert|jajan/.test(haystack);
  if (type === 'sembako') return /sembako|beras|minyak|gula|telur|bumbu/.test(haystack);
  return !matchesFoodType(product, 'minuman') && !matchesFoodType(product, 'camilan') && !matchesFoodType(product, 'sembako');
}

export default function ProductsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const initialType = (searchParams.get('type') as FoodType | null) || 'all';
  const [searchQuery, setSearchQuery] = useState(searchParams.get('q') || '');
  const [foodFilters, setFoodFilters] = useState<FoodFilters>({ ...defaultFoodFilters, type: initialType });
  const [sortMode, setSortMode] = useState<SortMode>('nearest');
  const { location: userLocation } = useUserLocation();

  const { data: products = [], isLoading: loading } = useQuery<Product[]>({
    queryKey: ['all-products'],
    queryFn: fetchProducts,
    staleTime: 120_000,
  });

  const filteredAndSortedProducts = useMemo(() => {
    let result = products.filter((product) => {
      if (!isFoodProduct(product)) return false;
      const query = normalize(searchQuery);
      const haystack = `${normalize(product.name)} ${normalize(product.description)} ${normalize(product.merchantName)} ${normalize(product.category)}`;
      if (query && !haystack.includes(query)) return false;
      if (!matchesFoodType(product, foodFilters.type)) return false;
      if (foodFilters.openNow && product.isMerchantOpen === false) return false;
      if (foodFilters.promoOnly && !product.isPromo) return false;
      if (foodFilters.halalOnly && product.halal_status !== 'VERIFIED') return false;
      if (foodFilters.maxPrice < 100000 && product.price > foodFilters.maxPrice) return false;
      return true;
    });

    switch (sortMode) {
      case 'nearest':
        if (userLocation) result = sortByDistance(result, userLocation.lat, userLocation.lng);
        break;
      case 'cheapest': result = [...result].sort((a, b) => a.price - b.price); break;
      case 'expensive': result = [...result].sort((a, b) => b.price - a.price); break;
      case 'newest': break;
    }
    return result;
  }, [products, searchQuery, foodFilters, sortMode, userLocation]);

  const activeFilterCount = useMemo(() => (
    (foodFilters.type !== 'all' ? 1 : 0) +
    (foodFilters.openNow ? 1 : 0) +
    (foodFilters.promoOnly ? 1 : 0) +
    (foodFilters.halalOnly ? 1 : 0) +
    (foodFilters.maxPrice < 100000 ? 1 : 0)
  ), [foodFilters]);

  const handleTypeChange = (type: FoodType) => {
    setFoodFilters((previous) => ({ ...previous, type }));
    if (type === 'all') searchParams.delete('type');
    else searchParams.set('type', type);
    setSearchParams(searchParams);
  };

  return (
    <div className="mobile-shell flex min-h-screen flex-col bg-background">
      <Header />

      <div className="border-b border-border/40 bg-card px-5 pb-4 pt-4">
        <div className="mb-3 flex items-start gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary"><UtensilsCrossed className="h-5 w-5" /></div>
          <div>
            <h1 className="font-heading text-lg font-extrabold text-foreground">Makanan & Minuman</h1>
            <p className="text-xs text-muted-foreground">Cari menu yang ingin kamu nikmati hari ini.</p>
          </div>
        </div>

        <div className="flex gap-2">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <input value={searchQuery} onChange={(event) => setSearchQuery(event.target.value)} placeholder="Cari nasi, kopi, ayam, camilan..." aria-label="Cari makanan dan minuman" className="h-11 w-full rounded-2xl border border-border bg-background pl-10 pr-3 text-sm outline-none transition focus:border-primary/40 focus:ring-4 focus:ring-primary/10" />
          </div>
          <FoodFilterSheet filters={foodFilters} onFiltersChange={setFoodFilters} activeFilterCount={activeFilterCount} />
        </div>

        <div className="mt-3 flex gap-2 overflow-x-auto pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
          {([
            ['all', 'Semua menu'],
            ['makanan', 'Makanan'],
            ['minuman', 'Minuman'],
            ['camilan', 'Camilan'],
            ['sembako', 'Kebutuhan dapur'],
          ] as const).map(([value, label]) => (
            <button key={value} type="button" onClick={() => handleTypeChange(value)} className={cn('shrink-0 rounded-full px-3 py-1.5 text-xs font-semibold transition active:scale-95', foodFilters.type === value ? 'bg-primary text-primary-foreground shadow-sm' : 'bg-secondary text-secondary-foreground hover:bg-secondary/80')}>
              {label}
            </button>
          ))}
        </div>

        <div className="mt-3 flex items-center gap-2">
          <Select value={sortMode} onValueChange={(value) => setSortMode(value as SortMode)}>
            <SelectTrigger className="h-9 flex-1 rounded-xl text-xs"><ArrowUpDown className="mr-1.5 h-3.5 w-3.5" /><SelectValue /></SelectTrigger>
            <SelectContent>
              {userLocation && <SelectItem value="nearest">Terdekat dari saya</SelectItem>}
              <SelectItem value="cheapest">Harga terendah</SelectItem>
              <SelectItem value="expensive">Harga tertinggi</SelectItem>
              <SelectItem value="newest">Menu terbaru</SelectItem>
            </SelectContent>
          </Select>
          <div className="flex items-center gap-1 text-xs text-muted-foreground"><SlidersHorizontal className="h-3.5 w-3.5" />{activeFilterCount ? `${activeFilterCount} filter aktif` : 'Filter pintar'}</div>
        </div>
      </div>

      {userLocation && sortMode === 'nearest' && !loading && (
        <div className="px-5 py-2"><div className="flex items-center gap-1.5 rounded-lg bg-muted/50 px-3 py-2 text-xs text-muted-foreground"><MapPin className="h-3.5 w-3.5 text-primary" />Diurutkan berdasarkan lokasi {userLocation.source === 'gps' ? 'GPS kamu' : 'terdekat'}</div></div>
      )}

      <div className="flex-1 overflow-y-auto pb-24">
        <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="px-5 py-4">
          <div className="mb-3 flex items-center justify-between text-sm"><span className="font-semibold text-foreground">{loading ? 'Memuat menu...' : `${filteredAndSortedProducts.length} menu ditemukan`}</span><span className="text-xs text-muted-foreground">Makanan & minuman</span></div>
          {loading ? (
            <div className="grid grid-cols-2 gap-3">{Array.from({ length: 6 }).map((_, index) => <ProductSkeleton key={index} />)}</div>
          ) : filteredAndSortedProducts.length === 0 ? (
            <div className="py-12 text-center"><div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-muted"><UtensilsCrossed className="h-8 w-8 text-muted-foreground" /></div><p className="font-semibold text-foreground">Menu belum ditemukan</p><p className="mx-auto mt-1 max-w-[260px] text-sm text-muted-foreground">Coba ganti kata kunci atau kurangi filter makanan dan minuman.</p></div>
          ) : (
            <div className="grid grid-cols-2 gap-3">{filteredAndSortedProducts.map((product, index) => <ProductCard key={product.id} product={product} index={index} showCategoryBadge />)}</div>
          )}
        </motion.div>
      </div>
      <BottomNav />
    </div>
  );
}
