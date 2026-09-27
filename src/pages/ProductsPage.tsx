import { useState, useMemo, useEffect, useDeferredValue, type MouseEvent } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link, useSearchParams } from 'react-router-dom';
import { motion } from 'framer-motion';
import { Map as MapIcon, MapPin, ArrowUpDown, PackageOpen, Search, SlidersHorizontal, ArrowLeft, ChevronRight, Grid2X2, Utensils, Coffee, Soup, Cookie, CupSoda, Heart, Plus } from 'lucide-react';
import { Header } from '../components/layout/Header';
import { BottomNav } from '../components/layout/BottomNav';
import { ProductCard } from '../components/ProductCard';
import { Skeleton } from '../components/ui/skeleton';
import { Button } from '../components/ui/button';
import { fetchProducts } from '../lib/api';
import { calculateDistance, useUserLocation, sortByDistance } from '../hooks/useUserLocation';
import { cn } from '../lib/utils';
import { FoodFilterSheet } from '../components/product/FoodFilterSheet';
import { defaultFoodFilters, type FoodFilters, type FoodType } from '../components/product/foodFilters';
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
import { getCategoryBySlug, getCategoryDescendantSlugs, getCategoryDisplayLabel, getCategoryParent, getCategoryChildren, sortProductCategories, type ProductCategory } from '../lib/productCategories';
import { useCart } from '../contexts/CartContext';
import { toast } from 'sonner';
import { OptimizedImage } from '../components/ui/OptimizedImage';

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

function getCategoryFilterSlugs(type: FoodType, categories: ProductCategory[]) {
  if (type === 'all') return null;
  const selected = getCategoryBySlug(categories, type);
  if (selected) return [selected.slug, ...getCategoryDescendantSlugs(categories, selected.id)];
  if (normalize(type) === 'kuliner') return ['makanan', 'minuman', 'kuliner'];
  if (normalize(type) === 'belanja') return ['sembako', 'kelontongan', 'sayuran', 'buah', 'rumah-tangga', 'elektronik'];
  return [normalize(type)];
}

function matchesFoodType(product: Product, type: FoodType, categories: ProductCategory[]) {
  if (type === 'all') return true;
  return getCategoryFilterSlugs(type, categories)?.includes(normalize(product.category)) ?? false;
}

const foodCategoryItems = [
  { key: 'all', label: 'Semua', icon: Grid2X2 },
  { key: 'nasi', label: 'Nasi', icon: Soup },
  { key: 'mie', label: 'Mie', icon: Utensils },
  { key: 'minuman', label: 'Minuman', icon: CupSoda },
  { key: 'snack', label: 'Snack', icon: Cookie },
  { key: 'kopi', label: 'Kopi', icon: Coffee },
];

function FoodProductCard({ product, index }: { product: Product; index: number }) {
  const { addToCart } = useCart();
  const [liked, setLiked] = useState(false);
  const available = product.isAvailable !== false && product.isActive && product.stock > 0;
  const add = (event: MouseEvent) => {
    event.preventDefault();
    event.stopPropagation();
    if (!available) return;
    addToCart(product, 1);
    toast.success(`${product.name} ditambahkan ke keranjang`);
  };
  return (
    <motion.article initial={index < 8 ? { opacity: 0, y: 12 } : false} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.22, delay: Math.min(index, 7) * 0.025 }} className="group relative min-w-0 overflow-hidden rounded-[1.05rem] border border-[#e7ece4] bg-white shadow-[0_8px_22px_-18px_rgba(12,62,38,0.5)]">
      <Link to={`/product/${product.id}`} className="block">
        <div className="relative aspect-[1.12] overflow-hidden bg-[#eef4e9]">
          <OptimizedImage src={product.image} alt={product.name} className="h-full w-full object-cover transition duration-300 group-hover:scale-105" aspectRatio="auto" lazy />
          <span className="absolute left-2 top-2 rounded-full bg-white/90 px-2 py-1 text-[10px] font-bold text-[#17613d] shadow-sm">★ {(product.merchantRatingAvg || 4.7).toFixed(1)}</span>
          <button type="button" aria-label={liked ? `Hapus ${product.name} dari favorit` : `Simpan ${product.name}`} onClick={(event) => { event.preventDefault(); event.stopPropagation(); setLiked((value) => !value); }} className="absolute right-2 top-2 flex h-7 w-7 items-center justify-center rounded-full bg-white/90 text-[#e34a4a] shadow-sm transition active:scale-90">
            <Heart className={cn('h-3.5 w-3.5', liked && 'fill-current')} />
          </button>
        </div>
        <div className="px-3 pb-3 pt-2.5">
          <p className="truncate text-[10px] text-[#748078]">{product.merchantName}</p>
          <h3 className="mt-0.5 line-clamp-2 min-h-[2.25rem] text-[12px] font-bold leading-snug text-[#18372a]">{product.name}</h3>
          <p className="mt-1 text-[10px] text-[#8a938d]">{product.merchantVillage || 'Sekitar kamu'} · 20–30 menit</p>
          <div className="mt-2 flex items-center justify-between gap-2"><p className="text-[13px] font-extrabold text-[#0b7549]">Rp {product.price.toLocaleString('id-ID')}</p><button type="button" aria-label={`Tambah ${product.name} ke keranjang`} onClick={add} disabled={!available} className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-[#0b7549] text-white shadow-[0_4px_10px_-4px_rgba(11,117,73,0.8)] transition hover:bg-[#075f3b] active:scale-90 disabled:bg-[#b9c5bc]"><Plus className="h-4 w-4" /></button></div>
        </div>
      </Link>
    </motion.article>
  );
}

function FoodMerchantRow({ product, userLocation }: { product: Product; userLocation: { lat: number; lng: number } | null }) {
  const distance = userLocation && product.locationLat != null && product.locationLng != null ? `${calculateDistance(userLocation.lat, userLocation.lng, product.locationLat, product.locationLng).toFixed(1)} km` : 'Lokasi dekat';
  return <Link to={`/products?merchant=${product.merchantId}`} className="flex items-center gap-3 rounded-2xl border border-[#edf0eb] bg-white p-2.5 shadow-[0_7px_20px_-18px_rgba(12,62,38,0.5)] transition hover:border-[#b9d9b9]"><div className="h-14 w-14 shrink-0 overflow-hidden rounded-xl bg-[#eef4e9]"><OptimizedImage src={product.image} alt={product.merchantName} className="h-full w-full object-cover" aspectRatio="auto" lazy /></div><div className="min-w-0 flex-1"><p className="truncate text-[13px] font-bold text-[#18372a]">{product.merchantName}</p><p className="mt-0.5 text-[11px] text-[#7d887f]">★ {(product.merchantRatingAvg || 4.7).toFixed(1)} ({product.merchantRatingCount || 90}+)</p><p className="mt-0.5 truncate text-[10px] text-[#8a938d]">Aneka menu · {distance} · 20–30 menit</p></div><Heart className="mr-1 h-4 w-4 shrink-0 text-[#e35a5a]" /></Link>;
}

function FoodCatalogView({ products, filteredProducts, searchQuery, setSearchQuery, onCategoryChange, activeType, onBack, loading, isError, refetch, filters, onFiltersChange, activeFilterCount, userLocation, categoryOptions }: { products: Product[]; filteredProducts: Product[]; searchQuery: string; setSearchQuery: (value: string) => void; onCategoryChange: (type: FoodType) => void; activeType: FoodType; onBack: () => void; loading: boolean; isError: boolean; refetch: () => void; filters: FoodFilters; onFiltersChange: (filters: FoodFilters) => void; activeFilterCount: number; userLocation: { lat: number; lng: number } | null; categoryOptions: { slug: string; name: string }[] }) {
  const heroProduct = filteredProducts[0] || products[0];
  const merchants = Array.from(new Map(filteredProducts.map((product) => [product.merchantId, product])).values())
    .sort((a, b) => userLocation ? calculateDistance(userLocation.lat, userLocation.lng, a.locationLat, a.locationLng) - calculateDistance(userLocation.lat, userLocation.lng, b.locationLat, b.locationLng) : 0)
    .slice(0, 4);
  const recommendations = filteredProducts.slice(0, 6);
  return <div className="min-h-screen bg-[#f8fbf7] pb-28 text-[#18372a]"><header className="sticky top-0 z-40 flex items-center gap-3 border-b border-[#edf1eb] bg-white/95 px-5 py-3 backdrop-blur-xl"><button type="button" onClick={onBack} aria-label="Kembali" className="flex h-9 w-9 items-center justify-center rounded-full text-[#18372a] transition hover:bg-[#eef6e9] active:scale-90"><ArrowLeft className="h-5 w-5" /></button><h1 className="text-[17px] font-extrabold">Makanan & Minuman</h1><Link to="/cart" className="ml-auto flex h-9 w-9 items-center justify-center rounded-full bg-[#eef7e9] text-[#0b7549]"><PackageOpen className="h-4 w-4" /></Link></header><main className="space-y-5 px-5 pt-3"><div className="flex gap-2"><div className="relative flex-1"><Search className="absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-[#7b887f]" /><input value={searchQuery} onChange={(event) => setSearchQuery(event.target.value)} placeholder="Cari makanan atau minuman..." aria-label="Cari makanan atau minuman" className="h-11 w-full rounded-2xl border border-[#e4eae2] bg-white pl-11 pr-4 text-sm shadow-[0_8px_22px_-18px_rgba(12,62,38,0.6)] outline-none focus:border-[#86bc79] focus:ring-4 focus:ring-[#86bc79]/15" /></div><FoodFilterSheet filters={filters} onFiltersChange={onFiltersChange} activeFilterCount={activeFilterCount} categories={categoryOptions} title="Filter makanan & minuman" description="Pilih menu yang sesuai dengan lokasi dan preferensimu." showHalal resetType="kuliner" /></div>{heroProduct && !searchQuery && <div className="relative h-[7.7rem] overflow-hidden rounded-[1.15rem] bg-[#f6d9a8] shadow-[0_12px_25px_-18px_rgba(74,52,21,0.7)]"><OptimizedImage src={heroProduct.image} alt="Makanan enak dari warung terdekat" className="absolute inset-0 h-full w-full object-cover opacity-80" aspectRatio="auto" lazy /><div className="absolute inset-0 bg-gradient-to-r from-[#fff0ca] via-[#ffe5b4]/80 to-transparent" /><div className="relative z-10 max-w-[58%] px-4 pt-5"><p className="font-serif text-[20px] font-black leading-[1.03] text-[#17261e]">Makan Enak<br />dari Warung<br />Terdekat</p></div></div>}<div className="-mx-5 flex gap-4 overflow-x-auto px-5 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden" aria-label="Kategori makanan">{foodCategoryItems.map(({ key, label, icon: Icon }) => <button key={key} type="button" onClick={() => onCategoryChange(key)} className={cn('flex min-w-[50px] shrink-0 flex-col items-center gap-1.5 text-[10px] font-semibold transition active:scale-95', activeType === key ? 'text-[#0b7549]' : 'text-[#637168]')}><span className={cn('flex h-10 w-10 items-center justify-center rounded-full border', activeType === key ? 'border-[#b8ddad] bg-[#e8f5e3] text-[#0b7549] shadow-sm' : 'border-transparent bg-white text-[#748078] shadow-[0_5px_16px_-12px_rgba(0,0,0,0.5)]')}><Icon className="h-[18px] w-[18px]" /></span>{label}</button>)}</div>{loading ? <div className="grid grid-cols-2 gap-3">{Array.from({ length: 4 }).map((_, index) => <ProductSkeleton key={index} />)}</div> : isError ? <div className="rounded-2xl bg-white px-5 py-10 text-center shadow-sm"><p className="font-semibold">Menu belum dapat dimuat</p><Button variant="outline" size="sm" onClick={() => refetch()} className="mt-3 rounded-full">Coba lagi</Button></div> : <><section><div className="mb-3 flex items-center justify-between"><h2 className="text-[15px] font-extrabold">Rekomendasi untuk kamu</h2><button type="button" onClick={() => onCategoryChange('all')} className="flex items-center gap-1 text-[11px] font-bold text-[#0b7549]">Lihat Semua <ChevronRight className="h-3.5 w-3.5" /></button></div>{recommendations.length ? <div className="-mx-5 flex gap-3 overflow-x-auto px-5 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">{recommendations.map((product, index) => <div key={product.id} className="w-[10.25rem] shrink-0"><FoodProductCard product={product} index={index} /></div>)}</div> : <p className="rounded-2xl bg-white p-6 text-center text-sm text-[#7d887f]">Menu belum ditemukan. Coba kata kunci lain.</p>}</section>{merchants.length > 0 && <section><div className="mb-3 flex items-center justify-between"><h2 className="text-[15px] font-extrabold">Warung Terdekat</h2><button type="button" onClick={() => onCategoryChange('all')} className="flex items-center gap-1 text-[11px] font-bold text-[#0b7549]">Lihat Semua <ChevronRight className="h-3.5 w-3.5" /></button></div><div className="space-y-2.5">{merchants.map((product) => <FoodMerchantRow key={product.merchantId} product={product} userLocation={userLocation} />)}</div></section>}</>}</main><BottomNav /></div>;
}

export default function ProductsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const initialType = (searchParams.get('type') as FoodType | null) || 'all';
  const [searchQuery, setSearchQuery] = useState(searchParams.get('q') || '');
  const [foodFilters, setFoodFilters] = useState<FoodFilters>({ ...defaultFoodFilters, type: initialType });
  const [sortMode, setSortMode] = useState<SortMode>('newest');
  const [viewMode, setViewMode] = useState<ViewMode>('products');
  const [mapRadius, setMapRadius] = useState<MapRadius>('all');
  const deferredSearchQuery = useDeferredValue(searchQuery);
  const { location: userLocation } = useUserLocation();
  const { data: categories = [] } = useAdminCategories();

  const categoryOptions = useMemo(
    () => sortProductCategories(categories as ProductCategory[]).map((category) => ({ slug: category.slug, name: getCategoryDisplayLabel(categories as ProductCategory[], category) })),
    [categories],
  );
  const parentCategories = useMemo(
    () => sortProductCategories((categories as ProductCategory[]).filter((category) => !category.parent_id)),
    [categories],
  );
  const topCategoryOptions = useMemo(() => {
    const options = [
      { slug: 'all', name: 'Semua' },
      { slug: 'kuliner', name: 'Makanan & Minuman' },
      { slug: 'belanja', name: 'Belanja' },
      ...parentCategories.map((category) => ({ slug: category.slug, name: category.name })),
    ];
    return Array.from(new Map(options.map((option) => [option.slug, option])).values());
  }, [parentCategories]);
  const selectedCategory = useMemo(
    () => categories.find((category) => category.slug === foodFilters.type),
    [categories, foodFilters.type],
  );
  const profileCategory = useMemo(
    () => getCategoryParent(categories as ProductCategory[], selectedCategory || null) || selectedCategory,
    [categories, selectedCategory],
  );
  const catalogProfile = useMemo(
    () => getCatalogProfile(profileCategory, foodFilters.type),
    [profileCategory, foodFilters.type],
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
    // Product cards do not render merchant review bodies on this route.
    queryFn: () => fetchProducts({ includeReviews: false, cacheKey: 'catalog-products' }),
    staleTime: 120_000,
  });

  const filteredAndSortedProducts = useMemo(() => {
    let result = products.filter((product) => {
      const query = normalize(deferredSearchQuery);
      const haystack = `${normalize(product.name)} ${normalize(product.description)} ${normalize(product.merchantName)} ${normalize(product.category)}`;
      if (query && !haystack.includes(query)) return false;
      if (!matchesFoodType(product, foodFilters.type, categories as ProductCategory[])) return false;
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
  }, [products, deferredSearchQuery, foodFilters, sortMode, userLocation, categories]);

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
  const selectedParentCategory = getCategoryParent(categories as ProductCategory[], selectedCategory || null) || selectedCategory;
  const subCategoryOptions = selectedParentCategory ? getCategoryChildren(categories as ProductCategory[], selectedParentCategory.id) : [];
  const activeTopCategory = getCategoryParent(categories as ProductCategory[], selectedCategory || null)?.slug || foodFilters.type;

  if (catalogProfile.isFood) {
    return (
      <FoodCatalogView
        products={products}
        filteredProducts={filteredAndSortedProducts}
        searchQuery={searchQuery}
        setSearchQuery={setSearchQuery}
        onCategoryChange={(type) => handleTypeChange(type === 'all' ? 'kuliner' : type)}
        activeType={foodFilters.type === 'kuliner' ? 'all' : foodFilters.type}
        onBack={() => window.history.length > 1 ? window.history.back() : window.location.assign('/')}
        loading={loading}
        isError={isError}
        refetch={() => void refetch()}
        filters={foodFilters}
        onFiltersChange={handleFiltersChange}
        activeFilterCount={activeFilterCount}
        userLocation={userLocation}
        categoryOptions={categoryOptions}
      />
    );
  }

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
          {topCategoryOptions.map(({ slug, name }) => (
            <button key={slug} type="button" onClick={() => handleTypeChange(slug)} className={cn('shrink-0 rounded-full px-3 py-1.5 text-xs font-semibold transition active:scale-95', activeTopCategory === slug ? 'bg-primary text-primary-foreground shadow-sm' : 'bg-secondary text-secondary-foreground hover:bg-secondary/80')}>
              {name}
            </button>
          ))}
        </div>
        {subCategoryOptions.length > 0 && (
          <div className="mt-2 flex gap-2 overflow-x-auto pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden" aria-label={`Subkategori ${selectedParentCategory?.name}`}>
            <button type="button" onClick={() => handleTypeChange(selectedParentCategory?.slug || 'all')} className={cn('shrink-0 rounded-full border px-3 py-1 text-[11px] font-medium transition', foodFilters.type === selectedParentCategory?.slug ? 'border-primary bg-primary/10 text-primary' : 'border-border text-muted-foreground hover:border-primary/40')}>
              Semua {selectedParentCategory?.name}
            </button>
            {subCategoryOptions.map((category) => (
              <button key={category.id} type="button" onClick={() => handleTypeChange(category.slug)} className={cn('shrink-0 rounded-full border px-3 py-1 text-[11px] font-medium transition', foodFilters.type === category.slug ? 'border-primary bg-primary/10 text-primary' : 'border-border text-muted-foreground hover:border-primary/40')}>
                {category.icon ? `${category.icon} ` : ''}{category.name}
              </button>
            ))}
          </div>
        )}

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
            <div className="grid grid-cols-2 gap-3">{filteredAndSortedProducts.map((product, index) => <ProductCard key={product.id} product={product} index={index} showCategoryBadge categoryLabel={getCategoryDisplayLabel(categories as ProductCategory[], getCategoryBySlug(categories as ProductCategory[], product.category) || { id: '', name: product.category, slug: product.category, parent_id: null, icon: null })} />)}</div>
          )}
        </motion.div>
      </div>
      <BottomNav />
    </div>
  );
}
