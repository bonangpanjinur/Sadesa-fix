import { lazy, Suspense, useState, useMemo, useEffect, useDeferredValue, useCallback, type ComponentProps } from 'react';
import { useInfiniteQuery, useQuery } from '@tanstack/react-query';
import { Link, useSearchParams } from 'react-router-dom';
import { motion } from 'framer-motion';
import { Map as MapIcon, MapPin, ArrowUpDown, PackageOpen, ShoppingCart, Search, SlidersHorizontal, ArrowLeft, ChevronRight, Grid2X2, Zap, X } from 'lucide-react';
import { Header } from '../components/layout/Header';
import { BottomNav } from '../components/layout/BottomNav';
import { ProductCard } from '../components/ProductCard';
import { Skeleton } from '../components/ui/skeleton';
import { Button } from '../components/ui/button';
import { fetchProductCategoryCounts, fetchProductPage } from '../lib/api';
import { calculateDistance, useUserLocation, sortByDistance } from '../hooks/useUserLocation';
import { cn } from '../lib/utils';
import { FoodFilterSheet } from '../components/product/FoodFilterSheet';
import { defaultFoodFilters, getCatalogTypeFromSearchParams, type FoodFilters, type FoodType } from '../components/product/foodFilters';
import { useAdminCategories } from '../hooks/useAdminCategories';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '../components/ui/select';
import type { Product } from '../types';
import { getCategoryAncestors, getCategoryBySlug, getCategoryDescendantSlugs, getCategoryDisplayLabel, getCategoryParent, getCategoryChildren, getCategoryFilterIds, getFoodCategoryNavigationCategories, getShoppingCategorySlugs, hideRedundantFoodRootCategories, isCombinedFoodCategory, sortProductCategories, type ProductCategory } from '../lib/productCategories';
import { OptimizedImage } from '../components/ui/OptimizedImage';
import { WishlistButton } from '../components/WishlistButton';
import { useCart } from '../contexts/CartContext';
import { useFlashSales, type FlashSale } from '../hooks/useFlashSales';
import { FlashSaleTimer } from '../components/FlashSaleTimer';
import { formatPrice } from '../lib/utils';
import { fetchBannerPromotions, fetchCategoryBannerPromotions, incrementPromotionClick, incrementPromotionView, type Promotion } from '../lib/promotions';
import { HeroCarousel, type BannerSlide } from '../components/home/HeroCarousel';
import { isCompleteProduct } from '../lib/homepageProducts';

const LazyProductMerchantMap = lazy(() =>
  import('../components/product/ProductMerchantMap').then(({ ProductMerchantMap: Component }) => ({ default: Component })),
);

function ProductMapLoading() {
  return (
    <div role="status" aria-label="Memuat peta toko" className="h-[390px] w-full animate-pulse rounded-2xl border border-border bg-muted/50" />
  );
}

function ProductMerchantMap(props: ComponentProps<typeof LazyProductMerchantMap>) {
  return (
    <Suspense fallback={<ProductMapLoading />}>
      <LazyProductMerchantMap {...props} />
    </Suspense>
  );
}

type SortMode = 'nearest' | 'cheapest' | 'expensive' | 'newest';
type ViewMode = 'products' | 'map';
type MapRadius = 'all' | '1' | '3' | '5' | '10';
type FoodRadius = 'all' | '1' | '3' | '5' | '10';

interface CatalogProfile {
  title: string;
  description: string;
  placeholder: string;
  filterTitle: string;
  isFood: boolean;
  isShopping: boolean;
  isAgriculture: boolean;
}

function getCatalogProfile(category?: { slug: string; name: string }, requestedSlug?: string): CatalogProfile {
  const slug = normalize(requestedSlug || category?.slug);
  const name = normalize(category?.name);
  const isFood = ['makanan', 'minuman', 'kuliner'].includes(slug) || /makanan|minuman|kuliner/.test(name);

  if (slug === 'belanja' || slug === 'kelontongan') {
    return {
      title: 'Belanja',
      description: 'Temukan kebutuhan harian dan produk lokal dari toko sekitar.',
      placeholder: 'Cari kebutuhan harian, produk, atau toko',
      filterTitle: 'Filter belanja',
      isFood: false,
      isShopping: true,
      isAgriculture: false,
    };
  }
  if (slug === 'pertanian' || /pertanian|agri/.test(name)) {
    return {
      title: 'Pertanian',
      description: 'Temukan bibit, pupuk, pakan, alat tani, dan hasil pertanian dari penjual sekitar.',
      placeholder: 'Cari bibit, pupuk, pakan, alat tani, atau toko',
      filterTitle: 'Filter pertanian',
      isFood: false,
      isShopping: false,
      isAgriculture: true,
    };
  }
  if (isFood) {
    return {
      title: 'Makanan & Minuman',
      description: 'Temukan menu favorit dari warung dan merchant sekitar.',
      placeholder: 'Cari makanan, minuman, atau toko',
      filterTitle: 'Filter makanan & minuman',
      isFood: true,
      isShopping: false,
      isAgriculture: false,
    };
  }
  if (slug === 'sembako') {
    return {
      title: category?.name || 'Sembako',
      description: 'Belanja kebutuhan harian dari toko terdekat.',
      placeholder: 'Cari beras, minyak, telur, atau toko',
      filterTitle: 'Filter sembako',
      isFood: false,
      isShopping: true,
      isAgriculture: false,
    };
  }
  if (category) {
    return {
      title: category.name,
      description: `Temukan ${category.name.toLowerCase()} dari merchant sekitar.`,
      placeholder: `Cari ${category.name.toLowerCase()} atau toko`,
      filterTitle: `Filter ${category.name.toLowerCase()}`,
      isFood: false,
      isShopping: false,
      isAgriculture: false,
    };
  }
  return {
    title: 'Katalog produk',
    description: 'Temukan produk lokal dari merchant sekitar.',
    placeholder: 'Cari produk atau toko',
    filterTitle: 'Filter katalog',
    isFood: false,
    isShopping: false,
    isAgriculture: false,
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

const SORT_MODES: SortMode[] = ['nearest', 'cheapest', 'expensive', 'newest'];
const VIEW_MODES: ViewMode[] = ['products', 'map'];
const RADII: MapRadius[] = ['all', '1', '3', '5', '10'];
const asAllowed = <T extends string>(value: string | null, allowed: readonly T[], fallback: T): T => (
  value && (allowed as readonly string[]).includes(value) ? value as T : fallback
);

function getCategoryFilterSlugs(type: FoodType, categories: ProductCategory[]) {
  if (type === 'all') return null;
  if (normalize(type) === 'belanja') {
    return getShoppingCategorySlugs(categories);
  }
  const selected = getCategoryBySlug(categories, type);
  if (selected) return [selected.slug, ...getCategoryDescendantSlugs(categories, selected.id)];
  if (normalize(type) === 'kuliner') return ['makanan', 'minuman', 'kuliner'];
  if (normalize(type) === 'pertanian') return ['pertanian', 'bibit', 'benih', 'pupuk', 'pestisida', 'pakan', 'alat-tani', 'hasil-tani'];
  return [normalize(type)];
}

function matchesFoodType(product: Product, type: FoodType, categories: ProductCategory[]) {
  if (type === 'all') return true;
  return getCategoryFilterSlugs(type, categories)?.includes(normalize(product.category)) ?? false;
}

function getDeliveryEta(distanceKm?: number) {
  if (distanceKm == null) return undefined;
  if (distanceKm < 1) return '15–25 menit';
  if (distanceKm < 3) return '20–30 menit';
  return '30–45 menit';
}

function FoodMerchantRow({ product, userLocation, catalogType }: { product: Product; userLocation: { lat: number; lng: number } | null; catalogType: 'kuliner' | 'belanja' | 'pertanian' }) {
  const distanceKm = userLocation && product.locationLat != null && product.locationLng != null
    ? calculateDistance(userLocation.lat, userLocation.lng, product.locationLat, product.locationLng)
    : undefined;
  const distance = distanceKm == null ? 'Jarak belum tersedia' : distanceKm < 1 ? `${Math.round(distanceKm * 1000)} m` : `${distanceKm.toFixed(1)} km`;
  const rating = product.merchantRatingAvg != null && product.merchantRatingAvg > 0 ? `★ ${product.merchantRatingAvg.toFixed(1)}` : 'Belum ada ulasan';
  const availability = product.isMerchantOpen === false ? 'Toko tutup' : 'Buka sekarang';
  const reviewCount = product.merchantRatingCount != null && product.merchantRatingCount > 0 ? ` (${product.merchantRatingCount}+)` : '';
  return <Link to={`/products?type=${catalogType}&merchant=${product.merchantId}`} className="flex items-center gap-3 rounded-2xl border border-[#edf0eb] bg-white p-2.5 shadow-[0_7px_20px_-18px_rgba(12,62,38,0.5)] transition hover:border-[#b9d9b9]">
    <div className="h-14 w-14 shrink-0 overflow-hidden rounded-xl bg-[#eef4e9]"><OptimizedImage src={product.merchantImageUrl || product.image} alt={product.merchantName} className="h-full w-full object-cover" aspectRatio="auto" lazy /></div>
    <div className="min-w-0 flex-1"><p className="truncate text-[13px] font-bold text-[#18372a]">{product.merchantName}</p><p className="mt-0.5 text-[11px] text-[#7d887f]">{rating}{reviewCount}</p><p className="mt-0.5 truncate text-[10px] text-[#8a938d]">{availability} · {distance} · {getDeliveryEta(distanceKm) || 'Estimasi belum tersedia'}</p></div>
    <WishlistButton productId={product.id} size="sm" className="mr-1 shrink-0 bg-transparent text-[#e35a5a] hover:bg-[#fff1f1] hover:text-[#d43f3f]" />
  </Link>;
}

function FoodBanner({ banners, categoryName }: { banners: Promotion[]; categoryName: string }) {
  const slides: BannerSlide[] = banners.map((banner) => ({
    id: banner.id,
    title: banner.title,
    subtitle: banner.subtitle,
    image: banner.imageUrl,
    linkUrl: banner.linkUrl,
    isSponsored: true,
  }));
  const handleView = useCallback((slideId: string) => {
    void incrementPromotionView(slideId);
  }, []);
  const handleClick = useCallback((slideId: string) => {
    void incrementPromotionClick(slideId);
  }, []);

  if (slides.length === 0) return null;
  return (
    <HeroCarousel
      slides={slides}
      autoPlayInterval={5000}
      ariaLabel={`Iklan ${categoryName}`}
      className="mx-0"
      onView={handleView}
      onClick={handleClick}
    />
  );
}

function FlashSaleReminder({ sale }: { sale: FlashSale }) {
  return <Link to={`/product/${sale.productId}`} className="group relative block overflow-hidden rounded-[1.35rem] bg-gradient-to-r from-[#8f1718] via-[#d52b1f] to-[#f06428] p-4 text-white shadow-[0_15px_32px_-18px_rgba(170,31,27,0.75)] transition hover:-translate-y-0.5">
    <div className="absolute -right-8 -top-10 h-32 w-32 rounded-full bg-white/10 blur-2xl" />
    <div className="relative z-10 flex items-center gap-3">
      {sale.productImage && <OptimizedImage src={sale.productImage} alt={sale.productName} className="h-16 w-16 shrink-0 rounded-2xl object-cover ring-2 ring-white/30" aspectRatio="square" lazy />}
      <div className="min-w-0 flex-1"><div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.1em]"><Zap className="h-3.5 w-3.5 fill-current" />Flash Sale</div><p className="mt-0.5 truncate text-sm font-extrabold">{sale.productName}</p><div className="mt-1 flex items-center gap-2"><span className="text-[11px] font-bold text-white/75 line-through">{formatPrice(sale.originalPrice)}</span><span className="text-base font-black">{formatPrice(sale.flashPrice)}</span><span className="rounded-full bg-white px-1.5 py-0.5 text-[9px] font-black text-[#d52b1f]">-{sale.discountPercent}%</span></div></div>
      <div className="shrink-0 text-right"><p className="mb-1 text-[9px] font-semibold text-white/80">Berakhir dalam</p><FlashSaleTimer endTime={sale.endTime} size="sm" showIcon={false} className="text-white [&_div]:bg-white/20 [&_div]:text-white" /></div>
    </div>
  </Link>;
}

function FoodCatalogView({ products, filteredProducts, searchQuery, setSearchQuery, onCategoryChange, activeType, onBack, loading, isError, refetch, filters, onFiltersChange, activeFilterCount, userLocation, locationLoading, onRefreshLocation, categoryOptions, foodCategories, foodBanners, nearbyRadius, onNearbyRadiusChange, sortMode, onSortChange, viewMode, onViewModeChange, mapRadius, onMapRadiusChange, mapProducts, onResetFilters, flashSales, catalogType, catalogTitle, catalogDescription, searchPlaceholder, filterTitle, filterDescription, showHalal, filterFoodOnly, filterRoot, hasNextPage, isFetchingNextPage, onLoadMore }: { products: Product[]; filteredProducts: Product[]; searchQuery: string; setSearchQuery: (value: string) => void; onCategoryChange: (type: FoodType) => void; activeType: FoodType; onBack: () => void; loading: boolean; isError: boolean; refetch: () => void; filters: FoodFilters; onFiltersChange: (filters: FoodFilters) => void; activeFilterCount: number; userLocation: { lat: number; lng: number; source?: string } | null; locationLoading: boolean; onRefreshLocation: () => void; categoryOptions: { slug: string; name: string }[]; foodCategories: ProductCategory[]; foodBanners: Promotion[]; nearbyRadius: FoodRadius; onNearbyRadiusChange: (radius: FoodRadius) => void; sortMode: SortMode; onSortChange: (mode: SortMode) => void; viewMode: ViewMode; onViewModeChange: (mode: ViewMode) => void; mapRadius: MapRadius; onMapRadiusChange: (radius: MapRadius) => void; mapProducts: Product[]; onResetFilters: () => void; flashSales: FlashSale[]; catalogType: 'kuliner' | 'belanja' | 'pertanian'; catalogTitle: string; catalogDescription: string; searchPlaceholder: string; filterTitle: string; filterDescription: string; showHalal: boolean; filterFoodOnly: boolean; filterRoot: FoodType; hasNextPage: boolean; isFetchingNextPage: boolean; onLoadMore: () => void; }) {
  const flashSalesByProduct = useMemo(() => new Map(flashSales.map((sale) => [sale.productId, sale])), [flashSales]);
  const { getItemCount } = useCart();
  const cartCount = getItemCount();
  const hasActiveDiscoveryFilters = Boolean(searchQuery.trim() || activeFilterCount || nearbyRadius !== 'all' || sortMode !== 'newest');
  const showDiscoverySections = !hasActiveDiscoveryFilters;
  const itemLabel = catalogType === 'kuliner' ? 'menu' : 'produk';
  const locationLabel = catalogType === 'kuliner' ? 'warung' : 'toko';
  const merchants = Array.from(new Map(filteredProducts.map((product) => [product.merchantId, product])).values())
    .map((product) => ({
      product,
      distanceKm: userLocation && product.locationLat != null && product.locationLng != null
        ? calculateDistance(userLocation.lat, userLocation.lng, product.locationLat, product.locationLng)
        : undefined,
    }))
    .filter(({ distanceKm }) => nearbyRadius === 'all' || (distanceKm != null && distanceKm <= Number(nearbyRadius)))
    .sort((a, b) => (a.distanceKm ?? Number.POSITIVE_INFINITY) - (b.distanceKm ?? Number.POSITIVE_INFINITY))
    .sort((a, b) => Number(b.product.isMerchantOpen !== false) - Number(a.product.isMerchantOpen !== false))
    .map(({ product }) => product)
    .slice(0, 4);
  const promotions = filteredProducts.filter((product) => product.isPromo).sort((a, b) => Number(b.isAvailable) - Number(a.isAvailable)).slice(0, 6);
  const recommendations = filteredProducts.filter((product) => !product.isPromo).sort((a, b) => Number(b.isAvailable) - Number(a.isAvailable)).slice(0, 6);
  const closestMerchantDistanceKm = merchants.reduce<number | undefined>((closest, product) => {
    if (!userLocation || product.locationLat == null || product.locationLng == null) return closest;
    const distance = calculateDistance(userLocation.lat, userLocation.lng, product.locationLat, product.locationLng);
    return closest == null ? distance : Math.min(closest, distance);
  }, undefined);
  const merchantSectionTitle = catalogType === 'kuliner'
    ? (closestMerchantDistanceKm != null && closestMerchantDistanceKm <= 10 ? 'Warung di sekitar' : 'Warung pilihan')
    : (closestMerchantDistanceKm != null && closestMerchantDistanceKm <= 10 ? 'Toko di sekitar' : 'Toko pilihan');
  const scrollToCatalog = () => {
    document.getElementById('catalog-list')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };
  return <div className="mobile-shell min-h-screen bg-[#f8fbf7] pb-28 text-[#18372a]">
    <header className="sticky top-0 z-40 flex items-center gap-3 border-b border-[#edf1eb] bg-white/95 px-5 py-3 backdrop-blur-xl"><button type="button" onClick={onBack} aria-label="Kembali" className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-[#18372a] transition hover:bg-[#eef6e9] active:scale-90"><ArrowLeft className="h-5 w-5" /></button><div className="min-w-0"><h1 className="truncate text-[17px] font-extrabold">{catalogTitle}</h1><p className="truncate text-[10px] text-[#718077]">{catalogDescription}</p></div><Link to="/cart" aria-label="Keranjang" className="relative ml-auto flex h-10 w-10 items-center justify-center rounded-full border border-[#d2e9c3] bg-[#edf7e6] text-[#015730] transition hover:bg-[#dff1d4]"><ShoppingCart className="h-[19px] w-[19px]" />{cartCount > 0 && <span className="absolute -right-0.5 -top-0.5 flex h-5 min-w-5 items-center justify-center rounded-full bg-[#E31019] px-1 text-[10px] font-bold text-white ring-2 ring-white">{cartCount > 9 ? '9+' : cartCount}</span>}</Link></header>
    <motion.main initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.3, ease: 'easeOut' }} className="space-y-4 px-5 pt-3">
      <div className="flex gap-2">
        <div className="relative min-w-0 flex-1">
          <Search className="absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-[#7b887f]" />
          <input value={searchQuery} onChange={(event) => setSearchQuery(event.target.value)} placeholder={searchPlaceholder} aria-label={searchPlaceholder} className="h-11 w-full rounded-2xl border border-[#e4eae2] bg-white pl-11 pr-10 text-sm shadow-[0_8px_22px_-18px_rgba(12,62,38,0.6)] outline-none focus:border-[#86bc79] focus:ring-4 focus:ring-[#86bc79]/15" />
          {searchQuery && <button type="button" onClick={() => setSearchQuery('')} aria-label="Hapus pencarian" className="absolute right-2 top-1/2 flex h-7 w-7 -translate-y-1/2 items-center justify-center rounded-full text-[#718077] hover:bg-[#eef6e9] hover:text-[#18372a]"><X className="h-4 w-4" /></button>}
        </div>
        <FoodFilterSheet filters={filters} onFiltersChange={onFiltersChange} activeFilterCount={activeFilterCount} categories={categoryOptions} title={filterTitle} description={filterDescription} showHalal={showHalal} foodOnly={filterFoodOnly} primaryCategory={{ slug: filterRoot, name: catalogTitle }} resetType={filterRoot} />
      </div>
      <div className="flex flex-wrap items-center gap-2 rounded-xl border border-[#e4eae2] bg-white px-3 py-2 text-xs text-[#637168]">
        <MapPin className="h-3.5 w-3.5 text-[#0b7549]" />
        <span>{locationLabel} dalam</span>
        <Select value={nearbyRadius} onValueChange={(value) => onNearbyRadiusChange(value as FoodRadius)} disabled={!userLocation}><SelectTrigger className="h-7 w-[112px] border-0 bg-transparent p-0 text-xs shadow-none focus:ring-0"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="all">Semua jarak</SelectItem><SelectItem value="1">1 km</SelectItem><SelectItem value="3">3 km</SelectItem><SelectItem value="5">5 km</SelectItem><SelectItem value="10">10 km</SelectItem></SelectContent></Select>
        <button type="button" onClick={onRefreshLocation} disabled={locationLoading} className="ml-auto rounded-full px-2 py-1 font-semibold text-[#0b7549] hover:bg-[#eef6e9]">{locationLoading ? 'Memuat...' : userLocation?.source === 'gps' ? 'Lokasi GPS aktif' : 'Gunakan lokasi saya'}</button>
      </div>
      <section className="space-y-2">
        <div className="flex items-center justify-between gap-2">
          <h2 className="text-xs font-bold text-[#18372a]">Jelajahi kategori</h2>
          <span className="text-[10px] text-[#718077]">Geser untuk melihat</span>
        </div>
        <nav className="-mx-5 flex gap-2 overflow-x-auto px-5 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden" aria-label={`Kategori ${catalogTitle.toLowerCase()}`}>
          <button type="button" aria-pressed={activeType === filterRoot} onClick={() => onCategoryChange(filterRoot)} className={cn('flex h-10 shrink-0 items-center gap-2 rounded-full border px-3 text-xs font-semibold transition active:scale-[.98] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#86bc79]', activeType === filterRoot ? 'border-[#0b7549] bg-[#0b7549] text-white shadow-sm' : 'border-[#e4eae2] bg-white text-[#637168] hover:border-[#b8ddad] hover:bg-[#f4fbf2]')}>
            <Grid2X2 className="h-4 w-4" /><span>{catalogTitle}</span>
          </button>
          {foodCategories.map((category) => (
            <button key={category.id} type="button" aria-pressed={activeType === category.slug} onClick={() => onCategoryChange(category.slug)} className={cn('flex h-10 shrink-0 items-center gap-2 rounded-full border px-3 text-xs font-semibold transition active:scale-[.98] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#86bc79]', activeType === category.slug ? 'border-[#0b7549] bg-[#0b7549] text-white shadow-sm' : 'border-[#e4eae2] bg-white text-[#637168] hover:border-[#b8ddad] hover:bg-[#f4fbf2]')}>
              {category.icon && <span aria-hidden="true" className="text-sm">{category.icon}</span>}<span>{category.name}</span>
            </button>
          ))}
        </nav>
      </section>
      {foodBanners.length > 0 && <FoodBanner banners={foodBanners} categoryName={catalogTitle} />}
      {flashSales[0] && <FlashSaleReminder sale={flashSales[0]} />}
      <div className="space-y-2">
        <div className="flex items-center justify-between gap-3" aria-live="polite">
          <div className="min-w-0">
            <p className="text-xs font-bold text-[#18372a]">{loading ? 'Memuat pilihan...' : `${filteredProducts.length} ${itemLabel} ditemukan`}</p>
            <p className="truncate text-[10px] text-[#718077]">{categoryOptions.find((category) => category.slug === activeType)?.name || catalogTitle}</p>
          </div>
          <span className="shrink-0 text-[10px] text-[#718077]">Urutkan & tampilan</span>
        </div>
        <div className="grid grid-cols-2 gap-2">
          <Select value={sortMode} onValueChange={(value) => onSortChange(value as SortMode)}><SelectTrigger className="h-10 rounded-xl text-xs"><ArrowUpDown className="mr-1.5 h-3.5 w-3.5" /><SelectValue /></SelectTrigger><SelectContent><SelectItem value="newest">Terbaru</SelectItem>{userLocation && <SelectItem value="nearest">Terdekat dari saya</SelectItem>}<SelectItem value="cheapest">Harga terendah</SelectItem><SelectItem value="expensive">Harga tertinggi</SelectItem></SelectContent></Select>
          <div className="grid grid-cols-2 rounded-xl bg-[#e9f2e5] p-1" role="tablist" aria-label={`Tampilan katalog ${catalogTitle.toLowerCase()}`}><button type="button" role="tab" aria-selected={viewMode === 'products'} onClick={() => onViewModeChange('products')} className={cn('rounded-lg text-xs font-semibold', viewMode === 'products' ? 'bg-white py-1.5 text-[#0b7549] shadow-sm' : 'text-[#637168]')}>{catalogType === 'kuliner' ? 'Menu' : 'Produk'}</button><button type="button" role="tab" aria-selected={viewMode === 'map'} onClick={() => onViewModeChange('map')} className={cn('rounded-lg text-xs font-semibold', viewMode === 'map' ? 'bg-white py-1.5 text-[#0b7549] shadow-sm' : 'text-[#637168]')}>Peta</button></div>
        </div>
      </div>
      {viewMode === 'map' && <div className="flex items-center gap-2 rounded-xl border border-[#e4eae2] bg-white px-3 py-2 text-xs"><MapPin className="h-3.5 w-3.5 text-[#0b7549]" /><span>Radius peta</span><Select value={mapRadius} onValueChange={(value) => onMapRadiusChange(value as MapRadius)}><SelectTrigger className="ml-auto h-7 w-[150px] border-0 p-0 text-xs shadow-none"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="all">Semua jarak</SelectItem><SelectItem value="1">Maks. 1 km</SelectItem><SelectItem value="3">Maks. 3 km</SelectItem><SelectItem value="5">Maks. 5 km</SelectItem><SelectItem value="10">Maks. 10 km</SelectItem></SelectContent></Select></div>}
      {viewMode === 'map' && !loading && !isError ? <ProductMerchantMap products={mapProducts} center={userLocation || { lat: -7.3274, lng: 108.2207 }} userLocation={userLocation} /> : loading ? <div className="grid grid-cols-2 gap-3">{Array.from({ length: 4 }).map((_, index) => <ProductSkeleton key={index} />)}</div> : isError ? <div className="rounded-2xl bg-white px-5 py-10 text-center shadow-sm"><p className="font-semibold">{itemLabel[0].toUpperCase() + itemLabel.slice(1)} belum dapat dimuat</p><Button variant="outline" size="sm" onClick={() => refetch()} className="mt-3 rounded-full">Coba lagi</Button></div> : <>
        {showDiscoverySections && promotions.length > 0 && <section className="-mx-1 overflow-hidden rounded-[1.35rem] border border-[#ffd3c5] bg-gradient-to-br from-[#fff4ed] via-[#fffaf5] to-white p-3 shadow-[0_12px_28px_-20px_rgba(205,71,27,0.65)]"><div className="mb-3 flex items-start justify-between gap-3"><div><div className="mb-1 inline-flex items-center gap-1 rounded-full bg-[#e94724] px-2 py-1 text-[9px] font-extrabold uppercase tracking-[0.08em] text-white"><span className="h-1.5 w-1.5 rounded-full bg-white" />Promo spesial</div><h2 className="text-[16px] font-extrabold text-[#7c2417]">Hemat lebih banyak hari ini</h2><p className="mt-0.5 text-[10px] text-[#9b6358]">{itemLabel[0].toUpperCase() + itemLabel.slice(1)} pilihan dengan harga spesial untukmu</p></div><button type="button" onClick={() => { onFiltersChange({ ...filters, promoOnly: true }); requestAnimationFrame(scrollToCatalog); }} className="mt-1 flex shrink-0 items-center gap-1 text-[11px] font-bold text-[#d43f23]">Lihat semua <ChevronRight className="h-3.5 w-3.5" /></button></div><div className="-mx-3 flex gap-3 overflow-x-auto px-3 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">{promotions.map((product, index) => { const distanceKm = userLocation && product.locationLat != null && product.locationLng != null ? calculateDistance(userLocation.lat, userLocation.lng, product.locationLat, product.locationLng) : undefined; return <div key={product.id} className="w-[10.25rem] shrink-0"><ProductCard product={product} index={index} distanceKm={distanceKm} deliveryEta={getDeliveryEta(distanceKm)} flashSaleOverride={flashSalesByProduct.get(product.id) ?? null} /></div>; })}</div></section>}
{showDiscoverySections && <section><div className="mb-3 flex items-center justify-between"><h2 className="text-[15px] font-extrabold">Rekomendasi untuk kamu</h2><button type="button" onClick={scrollToCatalog} className="flex items-center gap-1 text-[11px] font-bold text-[#0b7549]">Lihat semua {itemLabel} <ChevronRight className="h-3.5 w-3.5" /></button></div>{recommendations.length ? <div className="-mx-5 flex gap-3 overflow-x-auto px-5 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">{recommendations.map((product, index) => { const distanceKm = userLocation && product.locationLat != null && product.locationLng != null ? calculateDistance(userLocation.lat, userLocation.lng, product.locationLat, product.locationLng) : undefined; return <div key={product.id} className="w-[10.25rem] shrink-0"><ProductCard product={product} index={index} distanceKm={distanceKm} deliveryEta={getDeliveryEta(distanceKm)} flashSaleOverride={flashSalesByProduct.get(product.id) ?? null} /></div>; })}</div> : <div className="rounded-2xl bg-white p-6 text-center text-sm text-[#7d887f]"><p>{searchQuery ? `Tidak ada ${itemLabel} untuk “${searchQuery}”${filters.openNow ? ' yang sedang buka' : ''}.` : filters.openNow ? `Tidak ada ${itemLabel} yang sedang buka.` : `Belum ada ${itemLabel} yang cocok dengan filter ini.`}</p>{hasActiveDiscoveryFilters && <button type="button" onClick={onResetFilters} className="mt-3 rounded-full bg-[#e8f5e3] px-4 py-2 text-xs font-bold text-[#0b7549]">Reset pencarian & filter</button>}</div>}</section>}
        {showDiscoverySections && merchants.length > 0 && <section><div className="mb-3 flex items-center justify-between"><h2 className="text-[15px] font-extrabold">{merchantSectionTitle}</h2><button type="button" onClick={scrollToCatalog} className="flex items-center gap-1 text-[11px] font-bold text-[#0b7549]">Lihat Semua <ChevronRight className="h-3.5 w-3.5" /></button></div><div className="space-y-2.5">{merchants.map((product) => <FoodMerchantRow key={product.merchantId} product={product} userLocation={userLocation} catalogType={catalogType} />)}</div></section>}
        <section id="catalog-list" className="scroll-mt-24"><div className="mb-3 flex items-end justify-between gap-3"><div><h2 className="text-[15px] font-extrabold">Semua {itemLabel}</h2><p className="mt-0.5 text-[11px] text-[#718077]">{filteredProducts.length} pilihan sesuai pencarian dan filter</p></div>{hasActiveDiscoveryFilters && <button type="button" onClick={onResetFilters} className="shrink-0 text-[11px] font-bold text-[#0b7549]">Reset filter</button>}</div>{filteredProducts.length ? <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">{filteredProducts.map((product, index) => { const distanceKm = userLocation && product.locationLat != null && product.locationLng != null ? calculateDistance(userLocation.lat, userLocation.lng, product.locationLat, product.locationLng) : undefined; return <ProductCard key={product.id} product={product} index={index} distanceKm={distanceKm} deliveryEta={getDeliveryEta(distanceKm)} flashSaleOverride={flashSalesByProduct.get(product.id) ?? null} />; })}</div> : <div className="rounded-2xl border border-dashed border-[#cfe3c8] bg-white p-7 text-center text-sm text-[#7d887f]"><PackageOpen className="mx-auto mb-2 h-7 w-7 text-[#8bb77c]" /><p>Tidak ada {itemLabel} yang sesuai.</p><button type="button" onClick={onResetFilters} className="mt-3 rounded-full bg-[#e8f5e3] px-4 py-2 text-xs font-bold text-[#0b7549]">Tampilkan semua</button></div>}</section>
        {hasNextPage && <button type="button" onClick={onLoadMore} disabled={isFetchingNextPage} className="w-full rounded-xl border border-[#b8ddad] bg-white py-3 text-xs font-bold text-[#0b7549] disabled:opacity-60">{isFetchingNextPage ? 'Memuat produk...' : 'Muat lebih banyak produk'}</button>}
      </>}
    </motion.main><BottomNav />
  </div>;
}

interface HubCategory {
  slug: string;
  name: string;
  icon: string;
  count: number;
}

function CategoryHubView({ categories, products, searchQuery, setSearchQuery, loading, flashSalesByProduct }: { categories: HubCategory[]; products: Product[]; searchQuery: string; setSearchQuery: (value: string) => void; loading: boolean; flashSalesByProduct: ReadonlyMap<string, FlashSale> }) {
  const results = searchQuery.trim() ? products.filter((product) => `${product.name} ${product.description} ${product.merchantName} ${product.category}`.toLowerCase().includes(searchQuery.trim().toLowerCase())).slice(0, 6) : [];
  return <div className="mobile-shell min-h-screen bg-[#f8fbf7] pb-28 text-[#18372a]">
    <header className="sticky top-0 z-40 border-b border-[#edf1eb] bg-white/95 px-5 py-4 backdrop-blur-xl"><h1 className="text-[20px] font-extrabold">Jelajah Produk</h1><p className="mt-1 text-xs text-[#718077]">Pilih kategori untuk menemukan produk dan toko di sekitarmu.</p></header>
    <main className="space-y-5 px-5 pt-4">
      <div className="relative"><Search className="absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-[#7b887f]" /><input value={searchQuery} onChange={(event) => setSearchQuery(event.target.value)} placeholder="Cari produk, toko, atau kategori" aria-label="Cari produk, toko, atau kategori" className="h-12 w-full rounded-2xl border border-[#e4eae2] bg-white pl-11 pr-4 text-sm shadow-[0_8px_22px_-18px_rgba(12,62,38,0.6)] outline-none focus:border-[#86bc79] focus:ring-4 focus:ring-[#86bc79]/15" /></div>
      {searchQuery.trim() ? <section><div className="mb-3 flex items-center justify-between"><h2 className="text-[15px] font-extrabold">Hasil pencarian</h2><span className="text-xs text-[#718077]">{results.length} produk</span></div>{loading ? <div className="rounded-2xl bg-white p-6 text-center text-sm text-[#718077]">Memuat produk...</div> : results.length ? <div className="grid grid-cols-2 gap-3">{results.map((product, index) => <div key={product.id} className="relative"><ProductCard product={product} index={index} flashSaleOverride={flashSalesByProduct.get(product.id) ?? null} /><span className="absolute left-2 top-2 rounded-full bg-white/90 px-2 py-1 text-[9px] font-bold text-[#0b7549] shadow-sm">{product.category || 'Produk'}</span></div>)}</div> : <div className="rounded-2xl bg-white p-6 text-center text-sm text-[#718077]">Produk atau toko belum ditemukan.</div>}</section> : <>
        <section><div className="mb-3 flex items-center justify-between"><h2 className="text-[16px] font-extrabold">Pilih kategori</h2><span className="text-xs text-[#718077]">{categories.length} kategori</span></div><div className="grid grid-cols-2 gap-3">{categories.map((category) => <Link key={category.slug} to={`/products?type=${category.slug === 'belanja' ? 'kelontongan' : category.slug}`} className="group rounded-2xl border border-[#e4eae2] bg-white p-4 shadow-[0_8px_20px_-18px_rgba(12,62,38,0.7)] transition hover:-translate-y-0.5 hover:border-[#b8dcae]"><div className="flex items-center justify-between"><span className="flex h-11 w-11 items-center justify-center rounded-2xl bg-[#e8f5e3] text-2xl">{category.icon}</span><ChevronRight className="h-4 w-4 text-[#9aaa9f] transition group-hover:translate-x-0.5 group-hover:text-[#0b7549]" /></div><p className="mt-3 text-sm font-extrabold">{category.name}</p><p className="mt-1 text-[11px] text-[#718077]">{category.count} produk tersedia</p></Link>)}</div></section>
        <section className="rounded-2xl border border-[#dcebd7] bg-gradient-to-br from-[#eff8eb] to-white p-4"><p className="text-[10px] font-extrabold uppercase tracking-[0.12em] text-[#0b7549]">Tips menjelajah</p><p className="mt-1 text-sm font-bold text-[#18372a]">Masuk ke kategori agar filter dan pencarian lebih relevan.</p><p className="mt-1 text-xs leading-relaxed text-[#718077]">Setiap kategori memiliki pilihan produk, toko, jarak, harga, promo, dan stok yang disesuaikan.</p></section>
      </>}
    </main><BottomNav />
  </div>;
}

export default function ProductsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const promoOnly = searchParams.get('promoOnly') === '1';
  const initialType = getCatalogTypeFromSearchParams(searchParams);
  const [searchQuery, setSearchQuery] = useState(searchParams.get('q') || '');
  const [foodFilters, setFoodFilters] = useState<FoodFilters>({ type: initialType, openNow: searchParams.get('openNow') === '1', inStockOnly: searchParams.get('inStock') === '1', promoOnly: searchParams.get('promoOnly') === '1', halalOnly: searchParams.get('halalOnly') === '1', maxPrice: Number(searchParams.get('maxPrice')) || defaultFoodFilters.maxPrice });
  const [sortMode, setSortMode] = useState<SortMode>(asAllowed(searchParams.get('sort'), SORT_MODES, 'newest'));
  const [viewMode, setViewMode] = useState<ViewMode>(asAllowed(searchParams.get('view'), VIEW_MODES, 'products'));
  const [mapRadius, setMapRadius] = useState<MapRadius>(asAllowed(searchParams.get('mapRadius'), RADII, 'all'));
  const [nearbyRadius, setNearbyRadius] = useState<FoodRadius>(asAllowed(searchParams.get('radius'), RADII, 'all'));
  const merchantId = searchParams.get('merchant');
  const deferredSearchQuery = useDeferredValue(searchQuery);
  const { location: userLocation, loading: locationLoading, refreshLocation } = useUserLocation();
  const { data: categories = [], isError: categoriesError } = useAdminCategories();
  const selectedCategory = useMemo(
    () => categories.find((category) => category.slug === foodFilters.type),
    [categories, foodFilters.type],
  );
  const profileCategory = useMemo(
    () => getCategoryParent(categories as ProductCategory[], selectedCategory || null) || selectedCategory,
    [categories, selectedCategory],
  );
  const { data: foodBanners = [] } = useQuery<Promotion[]>({
    queryKey: ['food-catalog-banners'],
    queryFn: fetchBannerPromotions,
    staleTime: 120_000,
  });
  const { data: categoryBanners = [] } = useQuery<Promotion[]>({
    queryKey: ['category-banners', profileCategory?.id],
    queryFn: () => profileCategory ? fetchCategoryBannerPromotions(profileCategory.id) : Promise.resolve([]),
    enabled: Boolean(profileCategory?.id),
    staleTime: 120_000,
  });
  const { flashSales } = useFlashSales({ limit: 6 });
  const flashSalesByProduct = useMemo(() => new Map(flashSales.map((sale) => [sale.productId, sale])), [flashSales]);
  useEffect(() => {
    const requestedType = searchParams.get('type');
    const nextType = getCatalogTypeFromSearchParams(searchParams);
    setFoodFilters((previous) => previous.type === nextType ? previous : { ...previous, type: nextType });

    if (requestedType === 'belanja') {
      const nextParams = new URLSearchParams(searchParams);
      nextParams.set('type', 'kelontongan');
      setSearchParams(nextParams, { replace: true });
    }
  }, [searchParams, setSearchParams]);

  const categoryOptions = useMemo(
    () => sortProductCategories(categories as ProductCategory[]).map((category) => ({ slug: category.slug, name: getCategoryDisplayLabel(categories as ProductCategory[], category) })),
    [categories],
  );
  const shoppingRootCategory = useMemo(
    () => (categories as ProductCategory[]).find((category) => ['kelontongan', 'sembako', 'belanja'].includes(category.slug) && !category.parent_id)
      || (categories as ProductCategory[]).find((category) => /belanja|sembako|kelontongan/i.test(`${category.slug} ${category.name}`) && !category.parent_id),
    [categories],
  );
  const agricultureRootCategory = useMemo(
    () => (categories as ProductCategory[]).find((category) => ['pertanian', 'agri'].includes(category.slug) && !category.parent_id)
      || (categories as ProductCategory[]).find((category) => /pertanian|agri/i.test(`${category.slug} ${category.name}`) && !category.parent_id),
    [categories],
  );
  const agricultureCategories = useMemo(() => {
    const all = categories as ProductCategory[];
    const children = agricultureRootCategory ? getCategoryChildren(all, agricultureRootCategory.id) : [];
    if (children.length) return children;
    const agriculturePattern = /bibit|benih|pupuk|pestisida|pakan|ternak|ikan|alat[- ]tani|pertanian|perkebunan|hasil[- ]tani/i;
    return sortProductCategories(all.filter((category) => !category.parent_id && agriculturePattern.test(`${category.slug} ${category.name}`))).slice(0, 8);
  }, [categories, agricultureRootCategory]);
  const shoppingCategories = useMemo(() => {
    const all = categories as ProductCategory[];
    const children = shoppingRootCategory ? getCategoryChildren(all, shoppingRootCategory.id) : [];
    if (children.length) return children;
    const shoppingPattern = /sembako|kelontongan|sayur|buah|rumah[- ]tangga|elektronik|pakaian|kerajinan|pertanian|kebutuhan/i;
    return sortProductCategories(all.filter((category) => !category.parent_id && shoppingPattern.test(`${category.slug} ${category.name}`))).slice(0, 8);
  }, [categories, shoppingRootCategory]);
  const catalogBanners = categoryBanners.length > 0 ? categoryBanners : foodBanners;

  const parentCategories = useMemo(
    () => sortProductCategories((categories as ProductCategory[]).filter((category) => !category.parent_id)),
    [categories],
  );
  const topCategoryOptions = useMemo(() => {
    const options = [
      { slug: 'all', name: 'Semua' },
      { slug: 'kuliner', name: 'Makanan & Minuman' },
      { slug: 'belanja', name: 'Belanja' },
      { slug: 'pertanian', name: 'Pertanian' },
      ...hideRedundantFoodRootCategories(parentCategories, true).filter((category) => category.slug !== 'kelontongan').map((category) => ({ slug: category.slug, name: category.name })),
    ];
    return Array.from(new Map(options.map((option) => [option.slug, option])).values());
  }, [parentCategories]);
  const foodCategories = useMemo(() => {
    const all = categories as ProductCategory[];
    const currentPath = selectedCategory
      ? getCategoryAncestors(all, selectedCategory).filter((category) => !isCombinedFoodCategory(category))
      : [];
    return [
      ...currentPath,
      ...getFoodCategoryNavigationCategories(all, selectedCategory || null),
    ];
  }, [categories, selectedCategory]);
  const catalogProfile = useMemo(
    () => getCatalogProfile(profileCategory, foodFilters.type),
    [profileCategory, foodFilters.type],
  );
  const catalogCategories = catalogProfile.isFood ? foodCategories : catalogProfile.isAgriculture ? agricultureCategories : shoppingCategories;
  const catalogCategoryOptions = useMemo(
    () => catalogCategories.map((category) => ({ slug: category.slug, name: getCategoryDisplayLabel(categories as ProductCategory[], category) })),
    [catalogCategories, categories],
  );

  useEffect(() => {
    if (!catalogProfile.isFood && foodFilters.halalOnly) {
      setFoodFilters((previous) => ({ ...previous, halalOnly: false }));
    }
  }, [catalogProfile.isFood, foodFilters.halalOnly]);

  useEffect(() => {
    const nextParams = new URLSearchParams(searchParams);
    const setOrDelete = (key: string, value: string | null) => value ? nextParams.set(key, value) : nextParams.delete(key);
    setOrDelete('q', searchQuery.trim() || null);
    setOrDelete('openNow', foodFilters.openNow ? '1' : null);
    setOrDelete('inStock', foodFilters.inStockOnly ? '1' : null);
    setOrDelete('promoOnly', foodFilters.promoOnly ? '1' : null);
    setOrDelete('halalOnly', foodFilters.halalOnly ? '1' : null);
    setOrDelete('maxPrice', foodFilters.maxPrice < 100000 ? String(foodFilters.maxPrice) : null);
    setOrDelete('radius', nearbyRadius !== 'all' ? nearbyRadius : null);
    setOrDelete('sort', sortMode !== 'newest' ? sortMode : null);
    setOrDelete('view', viewMode !== 'products' ? viewMode : null);
    setOrDelete('mapRadius', mapRadius !== 'all' ? mapRadius : null);
    if (nextParams.toString() !== searchParams.toString()) setSearchParams(nextParams, { replace: true });
  }, [searchQuery, foodFilters, nearbyRadius, sortMode, viewMode, mapRadius, searchParams, setSearchParams]);

  // A removed/deactivated category must not remain selected from an old URL.
  useEffect(() => {
    const isVirtualCategory = ['kuliner', 'belanja', 'pertanian'].includes(foodFilters.type);
    if (foodFilters.type !== 'all' && !isVirtualCategory && categories.length > 0 && !categories.some((category) => category.slug === foodFilters.type)) {
      setFoodFilters((previous) => ({ ...previous, type: 'all' }));
      const nextParams = new URLSearchParams(searchParams);
      nextParams.delete('type');
      setSearchParams(nextParams, { replace: true });
    }
  }, [categories, foodFilters.type, searchParams, setSearchParams]);

  const categoryIds = useMemo(() => getCategoryFilterIds(categories as ProductCategory[], foodFilters.type), [categories, foodFilters.type]);
  const catalogQuery = useInfiniteQuery({
    queryKey: ['catalog-products', deferredSearchQuery.trim(), categoryIds, merchantId, foodFilters.promoOnly, foodFilters.inStockOnly, foodFilters.maxPrice, sortMode],
    initialPageParam: 0,
    queryFn: ({ pageParam }) => fetchProductPage({
      offset: pageParam,
      search: deferredSearchQuery,
      categoryIds,
      merchantId,
      promoOnly: foodFilters.promoOnly,
      inStockOnly: foodFilters.inStockOnly,
      maxPrice: foodFilters.maxPrice,
      sort: sortMode,
      cacheKey: 'catalog-products',
    }),
    getNextPageParam: (lastPage, allPages) => lastPage.hasMore ? allPages.reduce((total, page) => total + page.products.length, 0) : undefined,
    staleTime: 120_000,
  });
  const products = useMemo(() => catalogQuery.data?.pages.flatMap((page) => page.products) || [], [catalogQuery.data]);
  const loading = catalogQuery.isLoading;
  const isError = catalogQuery.isError;
  const refetch = catalogQuery.refetch;

  const filteredAndSortedProducts = useMemo(() => {
    let result = products.filter((product) => {
      if (categoryIds && product.categoryId && !categoryIds.includes(product.categoryId)) return false;
      if (foodFilters.openNow && product.isMerchantOpen === false) return false;
      if (foodFilters.inStockOnly && (product.stock <= 0 || product.isAvailable === false)) return false;
      if (foodFilters.promoOnly && !product.isPromo) return false;
      if (foodFilters.halalOnly && product.halal_status !== 'VERIFIED') return false;
      return true;
    });

    switch (sortMode) {
      case 'nearest':
        if (userLocation) result = sortByDistance(result, userLocation.lat, userLocation.lng);
        break;
      case 'cheapest': break;
      case 'expensive': break;
      case 'newest': result = result.filter(isCompleteProduct).sort((a, b) => (Date.parse(b.createdAt || '') || 0) - (Date.parse(a.createdAt || '') || 0)); break;
    }
    return result;
  }, [products, foodFilters, sortMode, userLocation, categoryIds]);

  const activeFilterCount = useMemo(() => (
    (foodFilters.type !== 'all' ? 1 : 0) +
    (foodFilters.openNow ? 1 : 0) +
    (foodFilters.inStockOnly ? 1 : 0) +
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

  const { data: categoryCounts = {}, isError: categoryCountsError } = useQuery({
    queryKey: ['product-category-counts'],
    queryFn: fetchProductCategoryCounts,
    staleTime: 120_000,
  });
  const hubCategories = useMemo<HubCategory[]>(() => {
    const iconBySlug: Record<string, string> = { kuliner: '🍲', belanja: '🛒', pertanian: '🌱', sembako: '🛍️', kelontongan: '📦', sayuran: '🥬', buah: '🍎', elektronik: '🔌' };
    return topCategoryOptions.filter((category) => category.slug !== 'all').map((category) => ({
      slug: category.slug,
      name: category.name,
      icon: iconBySlug[category.slug] || '🧺',
      count: (getCategoryFilterIds(categories as ProductCategory[], category.slug) || []).reduce((total, id) => total + (categoryCounts[id] || 0), 0),
    }));
  }, [topCategoryOptions, categories, categoryCounts]);

  if (categoriesError || categoryCountsError) {
    return <div className="mobile-shell min-h-screen bg-background"><Header /><main className="px-5 py-12 text-center"><PackageOpen className="mx-auto h-10 w-10 text-destructive" /><h1 className="mt-4 font-semibold">Kategori belum dapat dimuat</h1><p className="mx-auto mt-2 max-w-sm text-sm text-muted-foreground">Terjadi gangguan saat memuat kategori produk. Coba lagi tanpa menganggap katalog kosong.</p><Button className="mt-4 rounded-full" onClick={() => window.location.reload()}>Coba lagi</Button></main><BottomNav /></div>;
  }

  if (!promoOnly && (!searchParams.get('type') || searchParams.get('type') === 'all')) {
    return <CategoryHubView categories={hubCategories} products={products} searchQuery={searchQuery} setSearchQuery={setSearchQuery} loading={loading} flashSalesByProduct={flashSalesByProduct} />;
  }

  const handleTypeChange = (type: FoodType) => {
    setFoodFilters((previous) => ({ ...previous, type }));
    const nextParams = new URLSearchParams(searchParams);
    if (type === 'all') nextParams.delete('type');
    else nextParams.set('type', type);
    setSearchParams(nextParams, { replace: true });
  };

  const handleFiltersChange = (nextFilters: FoodFilters) => {
    setFoodFilters(nextFilters);
    const nextParams = new URLSearchParams(searchParams);
    if (nextFilters.type === 'all') nextParams.delete('type');
    else nextParams.set('type', nextFilters.type);
    setSearchParams(nextParams, { replace: true });
  };
  const resetDiscoveryFilters = () => {
    setSearchQuery('');
    setFoodFilters({ ...defaultFoodFilters, type: catalogProfile.isFood ? 'kuliner' : catalogProfile.isAgriculture ? 'pertanian' : 'belanja' });
    setNearbyRadius('all');
    setSortMode('newest');
    setViewMode('products');
    setMapRadius('all');
  };

  const selectedParentCategory = getCategoryParent(categories as ProductCategory[], selectedCategory || null) || selectedCategory;
  const subCategoryOptions = selectedParentCategory ? getCategoryChildren(categories as ProductCategory[], selectedParentCategory.id) : [];
  const activeTopCategory = getCategoryParent(categories as ProductCategory[], selectedCategory || null)?.slug || foodFilters.type;

  if (catalogProfile.isFood || catalogProfile.isShopping || catalogProfile.isAgriculture) {
    return (
      <FoodCatalogView
        products={products}
        filteredProducts={filteredAndSortedProducts}
        searchQuery={searchQuery}
        setSearchQuery={setSearchQuery}
        onCategoryChange={(type) => handleTypeChange(type === 'all' ? (catalogProfile.isFood ? 'kuliner' : catalogProfile.isAgriculture ? 'pertanian' : 'belanja') : type)}
        activeType={catalogProfile.isFood
          ? selectedCategory && !selectedCategory.parent_id && isCombinedFoodCategory(selectedCategory) ? 'kuliner' : foodFilters.type
          : selectedCategory && !selectedCategory.parent_id ? (catalogProfile.isAgriculture ? 'pertanian' : 'belanja') : foodFilters.type}
        onBack={() => window.history.length > 1 ? window.history.back() : window.location.assign('/')}
        loading={loading}
        isError={isError}
        refetch={() => void refetch()}
        filters={foodFilters}
        onFiltersChange={handleFiltersChange}
        activeFilterCount={activeFilterCount}
        userLocation={userLocation}
        locationLoading={locationLoading}
        onRefreshLocation={() => void refreshLocation()}
        categoryOptions={catalogCategoryOptions}
        foodCategories={catalogCategories}
        foodBanners={catalogBanners}
        nearbyRadius={nearbyRadius}
        onNearbyRadiusChange={setNearbyRadius}
        sortMode={sortMode}
        onSortChange={setSortMode}
        viewMode={viewMode}
        onViewModeChange={setViewMode}
        mapRadius={mapRadius}
        onMapRadiusChange={setMapRadius}
        mapProducts={mapProducts}
        onResetFilters={resetDiscoveryFilters}
        flashSales={flashSales}
        catalogType={catalogProfile.isFood ? 'kuliner' : catalogProfile.isAgriculture ? 'pertanian' : 'belanja'}
        catalogTitle={catalogProfile.title}
        catalogDescription={catalogProfile.description}
        searchPlaceholder={catalogProfile.placeholder}
        filterTitle={catalogProfile.filterTitle}
        filterDescription={catalogProfile.description}
        showHalal={catalogProfile.isFood}
        filterFoodOnly
        filterRoot={catalogProfile.isFood ? 'kuliner' : catalogProfile.isAgriculture ? 'pertanian' : 'belanja'}
        hasNextPage={Boolean(catalogQuery.hasNextPage)}
        isFetchingNextPage={catalogQuery.isFetchingNextPage}
        onLoadMore={() => void catalogQuery.fetchNextPage()}
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
            <h1 className="font-heading text-lg font-extrabold text-foreground">{promoOnly ? 'Kumpulan promo' : catalogProfile.title}</h1>
            <p className="text-xs text-muted-foreground">{promoOnly ? 'Temukan semua produk yang sedang menawarkan harga spesial.' : catalogProfile.description}</p>
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
          <div className="mb-3 flex items-center justify-between text-sm"><span className="font-semibold text-foreground">{loading ? 'Memuat katalog...' : viewMode === 'map' ? 'Lokasi toko merchant' : promoOnly ? `${filteredAndSortedProducts.length} promo tersedia` : `${filteredAndSortedProducts.length} produk ditemukan`}</span><span className="text-xs text-muted-foreground">{viewMode === 'map' ? `${mapProducts.length} produk sesuai filter` : promoOnly ? 'Promo terbaru' : 'Produk terbaru'}</span></div>
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
            <div className="py-12 text-center"><div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-muted"><PackageOpen className="h-8 w-8 text-muted-foreground" /></div><p className="font-semibold text-foreground">{promoOnly ? 'Belum ada promo aktif' : 'Produk belum ditemukan'}</p><p className="mx-auto mt-1 max-w-[260px] text-sm text-muted-foreground">{promoOnly ? 'Coba cek lagi nanti untuk menemukan penawaran spesial dari merchant sekitar.' : 'Coba ganti kata kunci atau kurangi filter katalog.'}</p></div>
          ) : (
            <div className="grid grid-cols-2 gap-3">{filteredAndSortedProducts.map((product, index) => <ProductCard key={product.id} product={product} index={index} flashSaleOverride={flashSalesByProduct.get(product.id) ?? null} showCategoryBadge categoryLabel={getCategoryDisplayLabel(categories as ProductCategory[], getCategoryBySlug(categories as ProductCategory[], product.category) || { id: '', name: product.category, slug: product.category, parent_id: null, icon: null })} />)}</div>
          )}
        </motion.div>
      </div>
      <BottomNav />
    </div>
  );
}
