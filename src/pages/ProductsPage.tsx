import { useState, useMemo, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useSearchParams } from 'react-router-dom';
import { motion } from 'framer-motion';
import { Map as MapIcon, MapPin, ArrowUpDown, PackageOpen, Search, SlidersHorizontal } from 'lucide-react';
import { Header } from '../components/layout/Header';
import { BottomNav } from '../components/layout/BottomNav';
import { ProductCard } from '../components/ProductCard';
import { Skeleton } from '../components/ui/skeleton';
import { Button } from '../components/ui/button';
import { fetchProducts } from '../lib/api';
import { calculateDistance, useUserLocation, sortByDistance } from '../hooks/useUserLocation';
import { cn } from '../lib/utils';
import { FoodFilterSheet, type FoodFilters, type FoodType, defaultFoodFilters } from '../components/product/FoodFilterSheet';
import { ProductMerchantMap } from '../components/product/ProductMerchantMap';
import { useAdminCategories } from '../hooks/useAdminCategories';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '../components/ui/select';
import type { Product } from '../types';

type SortMode = 'nearest' | 'cheapest' | 'expensive' | 'newest';
type ViewMode = 'products' | 'map';
type MapRadius = 'all' | '1' | '3' | '5' | '10';

interface CatalogProfile {
  title: string;
  description: string;
  placeholder: string;
  filterTitle: string;
  isFood: boolean;
}

function getCatalogProfile(category?: { slug: string; name: string }, requestedSlug?: string): CatalogProfile {
  const slug = normalize(requestedSlug || category?.slug);
  const name = normalize(category?.name);
  const isFood = ['makanan', 'minuman', 'kuliner'].includes(slug) || /makanan|minuman|kuliner/.test(name);

  if (slug === 'belanja') {
    return {
      title: 'Belanja',
      description: 'Temukan kebutuhan harian dan produk lokal dari toko sekitar.',
      placeholder: 'Cari kebutuhan harian, produk, atau toko',
      filterTitle: 'Filter belanja',
      isFood: false,
    };
  }
  if (isFood) {
    return {
      title: 'Makanan & Minuman',
      description: 'Temukan menu favorit dari warung dan merchant sekitar.',
      placeholder: 'Cari makanan, minuman, atau toko',
      filterTitle: 'Filter makanan & minuman',
      isFood: true,
    };
  }
  if (slug === 'sembako') {
    return {
      title: category?.name || 'Sembako',
      description: 'Belanja kebutuhan harian dari toko terdekat.',
      placeholder: 'Cari beras, minyak, telur, atau toko',
      filterTitle: 'Filter sembako',
      isFood: false,
    };
  }
  if (category) {
    return {
      title: category.name,
      description: `Temukan ${category.name.toLowerCase()} dari merchant sekitar.`,
      placeholder: `Cari ${category.name.toLowerCase()} atau toko`,
      filterTitle: `Filter ${category.name.toLowerCase()}`,
      isFood: false,
    };
  }
  return {
    title: 'Katalog produk',
    description: 'Temukan produk lokal dari merchant sekitar.',
    placeholder: 'Cari produk atau toko',
    filterTitle: 'Filter katalog',
    isFood: false,
  };
}

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

function matchesFoodType(product: Product, type: FoodType) {
  if (type === 'all') return true;
  if (normalize(type) === 'kuliner') return ['makanan', 'minuman', 'kuliner'].includes(normalize(product.category));
  if (normalize(type) === 'belanja') return ['sembako', 'kelontongan', 'sayuran', 'buah', 'rumah-tangga', 'elektronik'].includes(normalize(product.category));
  return normalize(product.category) === normalize(type);
}

export default function ProductsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const initialType = (searchParams.get('type') as FoodType | null) || 'all';
  const [searchQuery, setSearchQuery] = useState(searchParams.get('q') || '');
  const [foodFilters, setFoodFilters] = useState<FoodFilters>({ ...defaultFoodFilters, type: initialType });
  const [sortMode, setSortMode] = useState<SortMode>('newest');
  const [viewMode, setViewMode] = useState<ViewMode>('products');
  const [mapRadius, setMapRadius] = useState<MapRadius>('all');
  const { location: userLocation } = useUserLocation();
  const { data: categories = [] } = useAdminCategories();

  const categoryOptions = useMemo(
    () => categories.map((category) => ({ slug: category.slug, name: category.name })),
    [categories],
  );
  const selectedCategory = useMemo(
    () => categories.find((category) => category.slug === foodFilters.type),
    [categories, foodFilters.type],
  );
  const catalogProfile = useMemo(
    () => getCatalogProfile(selectedCategory, foodFilters.type),
    [selectedCategory, foodFilters.type],
  );
  useEffect(() => {
    if (!catalogProfile.isFood && foodFilters.halalOnly) {
      setFoodFilters((previous) => ({ ...previous, halalOnly: false }));
    }
  }, [catalogProfile.isFood, foodFilters.halalOnly]);

  // A removed/deactivated category must not remain selected from an old URL.
  useEffect(() => {
    const isVirtualCategory = ['kuliner', 'belanja'].includes(foodFilters.type);
    if (foodFilters.type !== 'all' && !isVirtualCategory && categories.length > 0 && !categories.some((category) => category.slug === foodFilters.type)) {
      setFoodFilters((previous) => ({ ...previous, type: 'all' }));
      const nextParams = new URLSearchParams(searchParams);
      nextParams.delete('type');
      setSearchParams(nextParams, { replace: true });
    }
  }, [categories, foodFilters.type, searchParams, setSearchParams]);

  const { data: products = [], isLoading: loading, isError, refetch } = useQuery<Product[]>({
    queryKey: ['all-products'],
    queryFn: () => fetchProducts(),
    staleTime: 120_000,
  });

  const filteredAndSortedProducts = useMemo(() => {
    let result = products.filter((product) => {
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
      case 'newest': result = [...result].sort((a, b) => (Date.parse(b.createdAt || '') || 0) - (Date.parse(a.createdAt || '') || 0)); break;
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

  const mapProducts = useMemo(() => {
    if (mapRadius === 'all' || !userLocation) return filteredAndSortedProducts;
    const radiusKm = Number(mapRadius);
    return filteredAndSortedProducts.filter((product) => (
      calculateDistance(userLocation.lat, userLocation.lng, product.locationLat, product.locationLng) <= radiusKm
    ));
  }, [filteredAndSortedProducts, mapRadius, userLocation]);

  const handleTypeChange = (type: FoodType) => {
    setFoodFilters((previous) => ({ ...previous, type }));
    const nextParams = new URLSearchParams(searchParams);
    if (type === 'all') nextParams.delete('type');
    else nextParams.set('type', type);
    setSearchParams(nextParams);
  };

  const handleFiltersChange = (nextFilters: FoodFilters) => {
    setFoodFilters(nextFilters);
    const nextParams = new URLSearchParams(searchParams);
    if (nextFilters.type === 'all') nextParams.delete('type');
    else nextParams.set('type', nextFilters.type);
    setSearchParams(nextParams, { replace: true });
  };

  return (
    <div className="mobile-shell flex min-h-screen flex-col bg-background">
      <Header />

      <div className="border-b border-border/40 bg-card px-5 pb-4 pt-4">
        <div className="mb-3 flex items-start gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary"><PackageOpen className="h-5 w-5" /></div>
          <div>
            <h1 className="font-heading text-lg font-extrabold text-foreground">{catalogProfile.title}</h1>
            <p className="text-xs text-muted-foreground">{catalogProfile.description}</p>
          </div>
        </div>

        <div className="flex gap-2">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <input value={searchQuery} onChange={(event) => setSearchQuery(event.target.value)} placeholder={catalogProfile.placeholder} aria-label={catalogProfile.placeholder} className="h-11 w-full rounded-2xl border border-border bg-background pl-10 pr-3 text-sm outline-none transition focus:border-primary/40 focus:ring-4 focus:ring-primary/10" />
          </div>
          <FoodFilterSheet
            filters={foodFilters}
            onFiltersChange={handleFiltersChange}
            activeFilterCount={activeFilterCount}
            categories={categoryOptions}
            title={catalogProfile.filterTitle}
            description={catalogProfile.description}
            showHalal={catalogProfile.isFood}
          />
        </div>

        <div className="mt-3 flex gap-2 overflow-x-auto pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
          {[{ slug: 'all', name: 'Semua' }, { slug: 'kuliner', name: 'Makanan & Minuman' }, { slug: 'belanja', name: 'Belanja' }, ...categoryOptions].map(({ slug, name }) => (
            <button key={slug} type="button" onClick={() => handleTypeChange(slug)} className={cn('shrink-0 rounded-full px-3 py-1.5 text-xs font-semibold transition active:scale-95', foodFilters.type === slug ? 'bg-primary text-primary-foreground shadow-sm' : 'bg-secondary text-secondary-foreground hover:bg-secondary/80')}>
              {name}
            </button>
          ))}
        </div>

        <div className="mt-3 grid grid-cols-2 gap-1 rounded-xl bg-secondary p-1" role="tablist" aria-label="Tampilan katalog">
          <button
            type="button"
            role="tab"
            aria-selected={viewMode === 'products'}
            onClick={() => setViewMode('products')}
            className={cn('flex h-9 items-center justify-center gap-1.5 rounded-lg text-xs font-semibold transition', viewMode === 'products' ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground')}
          >
            <PackageOpen className="h-3.5 w-3.5" /> Produk
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={viewMode === 'map'}
            onClick={() => setViewMode('map')}
            className={cn('flex h-9 items-center justify-center gap-1.5 rounded-lg text-xs font-semibold transition', viewMode === 'map' ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground')}
          >
            <MapIcon className="h-3.5 w-3.5" /> Toko di Maps
          </button>
        </div>

        <div className="mt-3 flex items-center gap-2">
          <Select value={sortMode} onValueChange={(value) => setSortMode(value as SortMode)}>
            <SelectTrigger className="h-9 flex-1 rounded-xl text-xs"><ArrowUpDown className="mr-1.5 h-3.5 w-3.5" /><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="newest">Terbaru</SelectItem>
              {userLocation && <SelectItem value="nearest">Terdekat dari saya</SelectItem>}
              <SelectItem value="cheapest">Harga terendah</SelectItem>
              <SelectItem value="expensive">Harga tertinggi</SelectItem>
            </SelectContent>
          </Select>
          <div className="flex items-center gap-1 text-xs text-muted-foreground"><SlidersHorizontal className="h-3.5 w-3.5" />{activeFilterCount ? `${activeFilterCount} filter aktif` : 'Filter katalog'}</div>
        </div>

        {viewMode === 'map' && (
          <div className="mt-3 grid grid-cols-2 gap-2">
            <Select value={foodFilters.type} onValueChange={(value) => handleTypeChange(value as FoodType)}>
              <SelectTrigger className="h-9 rounded-xl text-xs"><PackageOpen className="mr-1.5 h-3.5 w-3.5" /><SelectValue placeholder="Kategori produk" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Semua kategori</SelectItem>
                <SelectItem value="kuliner">Makanan & Minuman</SelectItem>
                <SelectItem value="belanja">Belanja</SelectItem>
                {categoryOptions.map((category) => <SelectItem key={category.slug} value={category.slug}>{category.name}</SelectItem>)}
              </SelectContent>
            </Select>
            <Select value={mapRadius} onValueChange={(value) => setMapRadius(value as MapRadius)}>
              <SelectTrigger className="h-9 rounded-xl text-xs"><MapPin className="mr-1.5 h-3.5 w-3.5" /><SelectValue placeholder="Jarak toko" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Semua jarak</SelectItem>
                <SelectItem value="1">Terdekat, maksimal 1 km</SelectItem>
                <SelectItem value="3">Maksimal 3 km</SelectItem>
                <SelectItem value="5">Maksimal 5 km</SelectItem>
                <SelectItem value="10">Maksimal 10 km</SelectItem>
              </SelectContent>
            </Select>
          </div>
        )}
      </div>

      {userLocation && sortMode === 'nearest' && !loading && (
        <div className="px-5 py-2"><div className="flex items-center gap-1.5 rounded-lg bg-muted/50 px-3 py-2 text-xs text-muted-foreground"><MapPin className="h-3.5 w-3.5 text-primary" />Diurutkan berdasarkan lokasi {userLocation.source === 'gps' ? 'GPS kamu' : 'terdekat'}</div></div>
      )}

      <div className="flex-1 overflow-y-auto pb-24">
        <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="px-5 py-4">
          <div className="mb-3 flex items-center justify-between text-sm"><span className="font-semibold text-foreground">{loading ? 'Memuat katalog...' : viewMode === 'map' ? 'Lokasi toko merchant' : `${filteredAndSortedProducts.length} produk ditemukan`}</span><span className="text-xs text-muted-foreground">{viewMode === 'map' ? `${mapProducts.length} produk sesuai filter` : 'Produk terbaru'}</span></div>
          {loading ? (
            <div className="grid grid-cols-2 gap-3">{Array.from({ length: 6 }).map((_, index) => <ProductSkeleton key={index} />)}</div>
          ) : isError ? (
            <div className="rounded-2xl border border-dashed border-destructive/30 bg-destructive/5 px-5 py-10 text-center">
              <p className="font-semibold text-foreground">Katalog belum dapat dimuat</p>
              <p className="mx-auto mt-1 max-w-[260px] text-sm text-muted-foreground">Periksa koneksi internetmu lalu coba lagi.</p>
              <Button type="button" variant="outline" size="sm" onClick={() => refetch()} className="mt-4 rounded-full">Coba lagi</Button>
            </div>
          ) : viewMode === 'map' ? (
            <ProductMerchantMap
              products={mapProducts}
              center={userLocation || { lat: -7.3274, lng: 108.2207 }}
              userLocation={userLocation}
            />
          ) : filteredAndSortedProducts.length === 0 ? (
            <div className="py-12 text-center"><div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-muted"><PackageOpen className="h-8 w-8 text-muted-foreground" /></div><p className="font-semibold text-foreground">Produk belum ditemukan</p><p className="mx-auto mt-1 max-w-[260px] text-sm text-muted-foreground">Coba ganti kata kunci atau kurangi filter katalog.</p></div>
          ) : (
            <div className="grid grid-cols-2 gap-3">{filteredAndSortedProducts.map((product, index) => <ProductCard key={product.id} product={product} index={index} showCategoryBadge />)}</div>
          )}
        </motion.div>
      </div>
      <BottomNav />
    </div>
  );
}
