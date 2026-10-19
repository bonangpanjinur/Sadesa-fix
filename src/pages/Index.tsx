import { useMemo, useCallback, useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { ChevronRight, Sparkles, Flame, MapPin, ShoppingBag, Store, Receipt, Truck } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Button } from '@/components/ui/button';
import { VillageCard } from '@/components/VillageCard';
import { ProductCard } from '@/components/ProductCard';
import { HeroCarousel, type BannerSlide } from '@/components/home/HeroCarousel';
import { MealTimeReminder } from '@/components/home/MealTimeReminder';
import { TourismCarousel } from '@/components/home/TourismCarousel';
import { HomeServiceCards } from '@/components/home/HomeServiceCards';
import { 
  fetchProducts, 
  fetchVillages, 
  fetchTourism,
} from '@/lib/api';
import { fetchBannerPromotions, incrementPromotionView, incrementPromotionClick } from '@/lib/promotions';
import {
  getHomepageRotationBucket,
  hasEnoughBestSellingHistory,
  selectRotatingProducts,
  selectTopSellingProducts,
} from '@/lib/homepageProducts';
import { getShoppingCategoryQueryFilter, groupNewestProductsByCategory, selectNewestFoodDrinkProducts } from '@/lib/homepageProductCategories';
import { useHomepageLayout } from '@/hooks/useHomepageLayout';
import { useAdminCategories } from '@/hooks/useAdminCategories';
import { CarouselSkeleton, ProductGridSkeleton } from '@/components/home/HomeSkeletons';
import { SectionError } from '@/components/home/SectionError';
import { logHomeSectionError } from '@/lib/homeErrorLog';
import { useUserLocation, sortByDistance, calculateDistance } from '@/hooks/useUserLocation';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import type { ProductFlashSale } from '@/hooks/useFlashSales';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import type { Product, Village, Tourism } from '@/types';

interface HomepageFlashSaleRow {
  product_id: string;
  original_price: number;
  flash_price: number;
  end_time: string;
}

type NewestFoodDrinkFilter = 'all' | 'makanan' | 'minuman';

const newestFoodDrinkFilterOptions: { value: NewestFoodDrinkFilter; label: string }[] = [
  { value: 'all', label: 'Semua' },
  { value: 'makanan', label: 'Makanan' },
  { value: 'minuman', label: 'Minuman' },
];

function MerchantJoinCard({ onRetry }: { onRetry?: () => void }) {
  return (
    <section className="mx-4 mt-6 overflow-hidden rounded-[1.35rem] border border-emerald-100 bg-[linear-gradient(135deg,hsl(152_61%_97%),hsl(43_100%_97%))] px-4 py-4 shadow-[0_18px_40px_-28px_hsl(152_61%_35%_/_0.5)]" aria-label="Ajakan menjadi mitra merchant">
      <div className="flex items-start gap-3">
        <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-emerald-100 text-emerald-700">
          <Store className="h-5 w-5" />
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-[9px] font-bold uppercase tracking-[0.16em] text-emerald-700">Peluang untuk usaha lokal</p>
          <h2 className="mt-1 font-heading text-base font-extrabold tracking-[-0.02em] text-foreground">Yuk gabung jadi Mitra Merchant SaDesa.id</h2>
          <p className="mt-1 text-xs leading-relaxed text-muted-foreground">Tawarkan produkmu ke lebih banyak pelanggan dan dapatkan penghasilan tambahan bersama SaDesa.</p>
          <div className="mt-4 flex flex-wrap items-center gap-2">
            <Button asChild size="sm" className="h-9 rounded-full bg-emerald-600 px-4 text-xs font-bold text-white shadow-sm hover:bg-emerald-700">
              <Link to="/register/merchant">Daftar Jadi Mitra</Link>
            </Button>
            {onRetry && (
              <Button variant="ghost" size="sm" onClick={onRetry} className="h-9 rounded-full px-3 text-xs text-muted-foreground">
                Coba muat produk
              </Button>
            )}
          </div>
        </div>
      </div>
    </section>
  );
}

const Index = () => {
  const navigate = useNavigate();
  const [promoMaxDistance, setPromoMaxDistance] = useState('10');
  const [newestMaxDistance, setNewestMaxDistance] = useState('all');
  const [newestFoodDrinkFilter, setNewestFoodDrinkFilter] = useState<NewestFoodDrinkFilter>('all');
  const [rotationBucket, setRotationBucket] = useState(() => getHomepageRotationBucket());

  useEffect(() => {
    const refreshRotation = () => setRotationBucket(getHomepageRotationBucket());
    const timer = window.setInterval(refreshRotation, 60_000);
    return () => window.clearInterval(timer);
  }, []);
  
  const { getEnabledSections } = useHomepageLayout();
  const { user } = useAuth();
  const {
    data: activeProductCategories = [],
    isLoading: productCategoriesLoading,
    isError: productCategoriesError,
    refetch: refetchProductCategories,
  } = useAdminCategories();
  const enabledSectionIds = new Set(getEnabledSections().map((section) => section.id));
  const promoSectionEnabled = enabledSectionIds.has('promo');
  const recommendationSectionEnabled = enabledSectionIds.has('recommendations');
  const shoppingCategoryQueryFilter = useMemo(
    () => getShoppingCategoryQueryFilter(activeProductCategories),
    [activeProductCategories],
  );
  const handleBannerView = useCallback((id: string) => { void incrementPromotionView(id); }, []);
  const handleBannerClick = useCallback((id: string) => { void incrementPromotionClick(id); }, []);

  const { data: activeOrder } = useQuery<{ id: string; status: string; total: number }>({
    queryKey: ['homepage-active-order', user?.id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('orders')
        .select('id, status, total')
        .eq('buyer_id', user!.id)
        .in('status', ['NEW', 'PENDING_PAYMENT', 'PENDING_CONFIRMATION', 'PROCESSED', 'ASSIGNED', 'PICKED_UP', 'DELIVERING', 'SENT', 'DELIVERED'])
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
    enabled: !!user,
    staleTime: 30_000,
  });

  const { location: userLocation } = useUserLocation();

  // Wraps a section fetch so any failure is logged with section name,
  // fetch params, and timestamp before React Query surfaces the error.
  const withErrorLog = <T,>(
    section: string,
    queryKey: string,
    params: Record<string, unknown>,
    fn: () => Promise<T>,
  ) => async (): Promise<T> => {
    try {
      return await fn();
    } catch (error) {
      logHomeSectionError(section, queryKey, params, error);
      throw error;
    }
  };

  // React Query: parallel data fetching with caching (P3-01)
  const {
    data: products = [],
    isLoading: productsLoading,
    isError: productsError,
    refetch: refetchProducts,
  } = useQuery<Product[]>({
    queryKey: ['homepage-products', rotationBucket],
    queryFn: withErrorLog('products', 'homepage-products', {
      staleTime: 60_000,
      rotationHours: 1,
      newestProductWindowDays: 14,
    }, () =>
      // Fetch a broad pool so each category can fall back independently when it
      // has no product from the last fourteen days.
      fetchProducts({
        limit: 200,
        includeReviews: false,
        cacheKey: 'homepage-products-rotating',
      })
    ),
    staleTime: 60_000,
  });

  const {
    data: shoppingCategoryCandidates = [],
    isLoading: shoppingCategoryCandidatesLoading,
    isError: shoppingCategoryCandidatesError,
    refetch: refetchShoppingCategoryCandidates,
  } = useQuery<Product[]>({
    queryKey: ['homepage-shopping-category-products', shoppingCategoryQueryFilter.categoryIds, shoppingCategoryQueryFilter.categorySlugs],
    queryFn: withErrorLog('shopping_products', 'homepage-shopping-category-products', {
      categoryIds: shoppingCategoryQueryFilter.categoryIds,
      categorySlugs: shoppingCategoryQueryFilter.categorySlugs,
    }, () => fetchProducts({
      limit: 48,
      includeReviews: false,
      cacheKey: 'homepage-shopping-category-products',
      categoryIds: shoppingCategoryQueryFilter.categoryIds,
      categorySlugs: shoppingCategoryQueryFilter.categorySlugs,
      sort: 'newest',
    })),
    enabled: recommendationSectionEnabled
      && (shoppingCategoryQueryFilter.categoryIds.length > 0 || shoppingCategoryQueryFilter.categorySlugs.length > 0),
    staleTime: 60_000,
  });

  const {
    data: bestSellingCandidates = [],
    isError: bestSellingError,
    refetch: refetchBestSelling,
  } = useQuery<Product[]>({
    queryKey: ['homepage-best-selling-products'],
    queryFn: withErrorLog('best_sellers', 'homepage-best-selling-products', {
      limit: 24,
      sort: 'best-selling',
    }, () => fetchProducts({
      limit: 24,
      includeReviews: false,
      cacheKey: 'homepage-best-selling-products',
      sort: 'best-selling',
    })),
    staleTime: 60_000,
    enabled: promoSectionEnabled || recommendationSectionEnabled,
  });

  const homepageProductIds = useMemo(
    () => [...new Set([...products, ...bestSellingCandidates].map((product) => product.id))],
    [products, bestSellingCandidates],
  );
  const { data: homepageFlashSales = [] } = useQuery<HomepageFlashSaleRow[]>({
    queryKey: ['homepage-flash-sales', homepageProductIds],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('flash_sales' as never)
        .select('product_id, original_price, flash_price, end_time')
        .in('product_id', homepageProductIds)
        .eq('status', 'ACTIVE')
        .gt('end_time', new Date().toISOString());
      if (error) throw error;
      return (data || []) as unknown as HomepageFlashSaleRow[];
    },
    enabled: homepageProductIds.length > 0,
    staleTime: 60_000,
  });
  const flashSalesByProduct = useMemo(() => new Map<string, ProductFlashSale>(
    homepageFlashSales.map((sale) => [sale.product_id, {
      productId: sale.product_id,
      originalPrice: Number(sale.original_price),
      flashPrice: Number(sale.flash_price),
      discountPercent: Math.round((1 - Number(sale.flash_price) / Number(sale.original_price)) * 100),
      endTime: sale.end_time,
    }] as const),
  ), [homepageFlashSales]);

  const {
    data: villages = [],
    isLoading: villagesLoading,
    isError: villagesError,
    refetch: refetchVillages,
  } = useQuery<Village[]>({
    queryKey: ['homepage-villages'],
    queryFn: withErrorLog('villages', 'homepage-villages', { staleTime: 60_000 }, () =>
      fetchVillages()
    ),
    staleTime: 60_000,
    enabled: enabledSectionIds.has('villages'),
  });

  const {
    data: tourismSpots = [],
    isLoading: tourismLoading,
    isError: tourismError,
    refetch: refetchTourism,
  } = useQuery<Tourism[]>({
    queryKey: ['homepage-tourism'],
    queryFn: withErrorLog('popular_tourism', 'homepage-tourism', { staleTime: 60_000 }, () =>
      fetchTourism()
    ),
    staleTime: 60_000,
    enabled: enabledSectionIds.has('popular_tourism'),
  });

  const {
    data: bannerSlides = [],
  } = useQuery<BannerSlide[]>({
    queryKey: ['homepage-banners'],
    queryFn: withErrorLog('hero', 'homepage-banners', { staleTime: 120_000 }, async () => {
      const promotionsData = await fetchBannerPromotions();
      return promotionsData
        .filter((promotion) => {
          if (!promotion.imageUrl?.trim()) return false;
          const searchText = `${promotion.title || ''} ${promotion.subtitle || ''} ${promotion.linkUrl || ''}`.toLowerCase();
          return !promotion.linkUrl?.includes('/tourism') && !searchText.includes('wisata');
        })
        .map(p => ({
        id: p.id,
        title: p.title,
        subtitle: p.subtitle,
        image: p.imageUrl,
        linkUrl: p.linkUrl,
        isSponsored: p.advertiserType === 'merchant',
        }));
    }),
    staleTime: 120_000,
  });

  // Only visible homepage data should hold the empty state open.
  const loading = productsLoading;

  // Sort data by proximity to user location
  const sortedVillages = useMemo(() => {
    if (!userLocation) return villages;
    return sortByDistance(villages, userLocation.lat, userLocation.lng);
  }, [villages, userLocation]);

  const sortedTourism = useMemo(() => {
    if (!userLocation) return tourismSpots;
    return sortByDistance(tourismSpots, userLocation.lat, userLocation.lng);
  }, [tourismSpots, userLocation]);

  // Beranda masih tahap validasi awal: tanpa transaksi/rating, gunakan sinyal
  // yang netral dan mudah dipahami pengguna, yaitu produk yang baru ditambahkan.
  const promoProducts = useMemo(() => (
    (() => {
      const availablePromos = products.filter((product) => product.isPromo === true && product.isAvailable === true);
      // Never show distant promotions on the homepage. Require a real GPS or
      // saved-profile location; the generic fallback is not the user's location.
      if (userLocation && userLocation.source !== 'default') {
        const nearbyPromos = availablePromos.filter((product) => (
          calculateDistance(userLocation.lat, userLocation.lng, product.locationLat, product.locationLng) <= Number(promoMaxDistance)
        ));
        return sortByDistance(nearbyPromos, userLocation.lat, userLocation.lng).slice(0, 6);
      }
      return [];
    })()
  ), [products, userLocation, promoMaxDistance]);
  // Keep discovery sections complementary: products already highlighted in
  // the promo block should not appear again immediately in the newest grid.
  const newestProducts = useMemo(() => {
    const highlightedProductIds = promoSectionEnabled
      ? new Set(promoProducts.map((product) => product.id))
      : new Set<string>();
    // Keep closed-merchant products in the pool so a category can fall back to
    // them when no open merchant has a product to show.
    let selectedNewest = selectRotatingProducts(
      products,
      highlightedProductIds,
      { limit: 200, rotationBucket, windowMs: Number.MAX_SAFE_INTEGER },
    );
    // Keep freshness as the candidate pool, then prioritize nearby merchants
    // within that pool when we know the user's actual location.
    if (userLocation && userLocation.source !== 'default') {
      if (newestMaxDistance !== 'all') {
        selectedNewest = selectedNewest.filter((product) => (
          calculateDistance(userLocation.lat, userLocation.lng, product.locationLat, product.locationLng) <= Number(newestMaxDistance)
        ));
      }
      return sortByDistance(selectedNewest, userLocation.lat, userLocation.lng);
    }
    return selectedNewest;
  }, [products, promoProducts, promoSectionEnabled, rotationBucket, userLocation, newestMaxDistance]);
  const shoppingProductsForHomepage = useMemo(() => {
    const sourceProducts = shoppingCategoryCandidatesLoading || shoppingCategoryCandidatesError
      ? newestProducts
      : shoppingCategoryCandidates;
    let candidates = sourceProducts;
    if (promoSectionEnabled) {
      const promotedIds = new Set(promoProducts.map((product) => product.id));
      candidates = candidates.filter((product) => !promotedIds.has(product.id));
    }
    if (userLocation && userLocation.source !== 'default' && newestMaxDistance !== 'all') {
      candidates = candidates.filter((product) => (
        calculateDistance(userLocation.lat, userLocation.lng, product.locationLat, product.locationLng) <= Number(newestMaxDistance)
      ));
    }
    return candidates;
  }, [
    shoppingCategoryCandidates,
    shoppingCategoryCandidatesError,
    shoppingCategoryCandidatesLoading,
    newestProducts,
    newestMaxDistance,
    promoProducts,
    promoSectionEnabled,
    userLocation,
  ]);
  const newestProductRows = useMemo(
    () => groupNewestProductsByCategory(newestProducts, activeProductCategories, 4, shoppingProductsForHomepage, {
      now: Date.now(),
      windowMs: 14 * 24 * 60 * 60 * 1000,
      rotationBucket,
    }),
    [newestProducts, activeProductCategories, shoppingProductsForHomepage, rotationBucket],
  );
  const productsAlreadyHighlighted = useMemo(() => new Set([
    ...(promoSectionEnabled ? promoProducts.map((product) => product.id) : []),
    ...(recommendationSectionEnabled
      ? newestProductRows.flatMap((row) => row.products.map((product) => product.id))
      : []),
  ]), [promoProducts, promoSectionEnabled, recommendationSectionEnabled, newestProductRows]);
  const topSellingProducts = useMemo(
    () => selectTopSellingProducts(bestSellingCandidates, productsAlreadyHighlighted),
    [bestSellingCandidates, productsAlreadyHighlighted],
  );
  const bestSellingThresholdReached = useMemo(
    () => hasEnoughBestSellingHistory(bestSellingCandidates),
    [bestSellingCandidates],
  );
  // Sort tourism by proximity first, then by view count
  const popularTourism = sortedTourism;
  
  // Keep promo discovery ahead of the newest-product section so best sellers
  // can sit between them, while preserving the configured order of other rows.
  const orderedSections = getEnabledSections();
  const promoIndex = orderedSections.findIndex((section) => section.id === 'promo');
  const recommendationsIndex = orderedSections.findIndex((section) => section.id === 'recommendations');
  if (promoIndex > recommendationsIndex && recommendationsIndex >= 0) {
    const [promoSection] = orderedSections.splice(promoIndex, 1);
    const updatedRecommendationsIndex = orderedSections.findIndex((section) => section.id === 'recommendations');
    if (promoSection && updatedRecommendationsIndex >= 0) {
      orderedSections.splice(updatedRecommendationsIndex, 0, promoSection);
    }
  }

  const getProductDistance = (product: Product) => {
    if (!userLocation || userLocation.source === 'default' || product.locationLat == null || product.locationLng == null) return undefined;
    return calculateDistance(userLocation.lat, userLocation.lng, product.locationLat, product.locationLng);
  };

  const getDeliveryEta = (distanceKm?: number) => {
    if (distanceKm == null) return undefined;
    if (distanceKm < 1) return '15–25 menit';
    if (distanceKm < 3) return '20–30 menit';
    return '30–45 menit';
  };

  const renderBestSellingSection = () => {
    if (bestSellingError) {
      return (
        <SectionError
          title="Produk terlaris gagal dimuat"
          message="Daftar produk dengan penjualan terbanyak tidak dapat diambil."
          onRetry={() => void refetchBestSelling()}
        />
      );
    }
    if (!bestSellingThresholdReached || topSellingProducts.length === 0) return null;

    return (
      <section className="mx-4 rounded-[1.35rem] border border-orange-100 bg-white px-4 py-4 shadow-[0_16px_36px_-28px_hsl(4_78%_47%_/_0.35)]" aria-labelledby="best-selling-products-title">
        <div className="mb-3 flex items-center gap-2">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/10 text-primary">
            <Flame className="h-4 w-4" />
          </div>
          <div>
            <h2 id="best-selling-products-title" className="font-heading text-base font-bold text-foreground">Produk terlaris</h2>
            <p className="text-[10px] text-muted-foreground">Paling banyak dibeli</p>
          </div>
        </div>
        <div
          className="flex snap-x snap-mandatory gap-3 overflow-x-auto pb-2 hide-scrollbar"
          aria-label="Produk terlaris"
          data-testid="list-best-selling-products"
        >
          {topSellingProducts.map((product, idx) => (
            <div
              key={product.id}
              className="w-[48%] shrink-0 snap-start sm:w-[32%]"
              data-testid={`best-selling-product-${product.id}`}
            >
              <ProductCard
                product={product}
                index={idx}
                showCategoryBadge
                flashSaleOverride={flashSalesByProduct.get(product.id) ?? null}
                distanceKm={getProductDistance(product)}
                deliveryEta={getDeliveryEta(getProductDistance(product))}
              />
            </div>
          ))}
        </div>
      </section>
    );
  };

  const renderSection = (sectionId: string) => {
    switch (sectionId) {
      case 'categories':
        return <HomeServiceCards />;
      case 'hero':
        return (
          <HeroCarousel
            slides={bannerSlides}
            autoPlayInterval={5000}
            onView={bannerSlides.length > 0 ? handleBannerView : undefined}
            onClick={bannerSlides.length > 0 ? handleBannerClick : undefined}
          />
        );
      
      case 'popular_tourism':
        if (tourismLoading) return <CarouselSkeleton count={3} />;
        if (tourismError)
          return (
            <SectionError
              title="Wisata gagal dimuat"
              message="Daftar wisata terdekat tidak dapat diambil."
              onRetry={() => refetchTourism()}
            />
          );
        return popularTourism.length > 0 ? (
            <section className="px-5">
            <div className="flex items-center justify-between mb-2">
              <div className="flex items-center gap-2">
                <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-accent/15 text-accent-foreground">
                  <Flame className="h-4 w-4" />
                </div>
                <div>
                  <h2 className="font-heading text-sm font-bold text-foreground">Wisata Terdekat</h2>
                  <p className="text-[9px] text-muted-foreground flex items-center gap-1">
                    <MapPin className="h-2.5 w-2.5" />
                    {userLocation?.source === 'gps' ? 'Berdasarkan lokasi Anda' : 'Sekitar Anda'}
                  </p>
                </div>
              </div>
              <Link 
                to="/tourism"
                className="text-[10px] text-primary font-bold hover:underline flex items-center gap-0.5"
              >
                Semua
                <ChevronRight className="h-3 w-3" />
              </Link>
            </div>
            <TourismCarousel tourismSpots={popularTourism} maxSlots={3} />
          </section>
        ) : null;
      
      case 'promo':
        return (
          <div className="space-y-5">
            {promoProducts.length > 0 || !userLocation || userLocation.source === 'default' || promoMaxDistance !== '10' ? (
              <section className="mx-4 rounded-[1.35rem] border border-red-100 bg-red-50/60 px-4 py-3" aria-labelledby="promo-title">
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <h2 id="promo-title" className="font-heading text-base font-bold text-foreground">Promo spesial</h2>
                    <label className="mt-1 flex items-center gap-1.5 text-[10px] text-muted-foreground">
                      <MapPin className="h-3 w-3" />
                      Maks. jarak
                      <select aria-label="Filter jarak maksimum promo" value={promoMaxDistance} onChange={(event) => setPromoMaxDistance(event.target.value)} disabled={!userLocation || userLocation.source === 'default'} className="rounded-md border border-red-200 bg-white px-1.5 py-1 text-[10px] text-foreground disabled:opacity-50">
                        <option value="1">1 km</option><option value="3">3 km</option><option value="5">5 km</option><option value="10">10 km</option>
                      </select>
                    </label>
                  </div>
                  <Button asChild size="sm" variant="outline" className="shrink-0 rounded-full text-xs"><Link to="/products?promoOnly=1">Lihat promo</Link></Button>
                </div>
                <div className="mt-3 grid grid-cols-[repeat(2,minmax(0,1fr))] gap-3">
                  {promoProducts.map((product, idx) => (
                    <ProductCard
                      key={product.id}
                      product={product}
                      index={idx}
                      showCategoryBadge
                      flashSaleOverride={flashSalesByProduct.get(product.id) ?? null}
                      distanceKm={getProductDistance(product)}
                      deliveryEta={getDeliveryEta(getProductDistance(product))}
                    />
                  ))}
                  {promoProducts.length === 0 && <p className="col-span-2 py-3 text-center text-xs text-muted-foreground">{!userLocation || userLocation.source === 'default' ? 'Aktifkan atau izinkan lokasi GPS agar promo terdekat dapat ditampilkan.' : `Belum ada promo dalam jarak ${promoMaxDistance} km.`}</p>}
                </div>
              </section>
            ) : null}
            {renderBestSellingSection()}
          </div>
        );
      
      case 'recommendations':
        if (productsLoading) return <ProductGridSkeleton count={4} />;
        if (productsError) return <MerchantJoinCard onRetry={() => refetchProducts()} />;
        if (productCategoriesLoading) return <ProductGridSkeleton count={4} />;
        if (productCategoriesError) {
          return (
            <SectionError
              title="Kategori produk gagal dimuat"
              message="Kategori terbaru belum dapat ditampilkan."
              onRetry={() => refetchProductCategories()}
            />
          );
        }
        return (
          <div className="space-y-5">
          {!promoSectionEnabled ? renderBestSellingSection() : null}
          <section className="mx-4 rounded-[1.35rem] border border-orange-100 bg-white px-4 py-4 shadow-[0_16px_36px_-28px_hsl(4_78%_47%_/_0.35)]" aria-labelledby="newest-products-title">
              <div className="mb-3 flex items-center gap-2">
                <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-[hsl(43_96%_55%_/_0.2)] text-[hsl(28_84%_36%)]">
                  <Sparkles className="h-4 w-4" />
                </div>
                <div>
                  <h2 id="newest-products-title" className="font-heading text-base font-bold text-foreground">Produk terbaru</h2>
                  <p className="mt-0.5 text-[9px] text-muted-foreground">Pilihan berganti setiap jam · produk baru 14 hari · kategori kosong memakai produk lain</p>
                  <label className="mt-1 flex items-center gap-1.5 text-[10px] text-muted-foreground">
                    <MapPin className="h-3 w-3" />
                    Maks. jarak
                    <select aria-label="Filter jarak maksimum produk terbaru" value={newestMaxDistance} onChange={(event) => setNewestMaxDistance(event.target.value)} disabled={!userLocation || userLocation.source === 'default'} className="rounded-md border border-border bg-white px-1.5 py-1 text-[10px] text-foreground disabled:opacity-50">
                      <option value="all">Semua</option><option value="1">1 km</option><option value="3">3 km</option><option value="5">5 km</option><option value="10">10 km</option>
                    </select>
                  </label>
                </div>
              <Link to="/products" className="ml-auto flex items-center gap-0.5 text-[10px] font-bold text-primary hover:underline">Lihat semua <ChevronRight className="h-3 w-3" /></Link>
            </div>
            {newestProductRows.length > 0 ? (
              <div className="space-y-4">
                {newestProductRows.map((row, rowIndex) => {
                  const visibleProducts = row.id === 'food-and-drinks' && newestFoodDrinkFilter !== 'all'
                    ? selectNewestFoodDrinkProducts(newestProducts, activeProductCategories, newestFoodDrinkFilter)
                    : row.products;
                  const selectedCategorySlug = row.id === 'food-and-drinks' && newestFoodDrinkFilter !== 'all'
                    ? newestFoodDrinkFilter
                    : row.slug;
                  const categoryHref = selectedCategorySlug === 'all'
                    ? '/products'
                    : `/products?type=${encodeURIComponent(selectedCategorySlug)}`;
                  return (
                  <section
                    key={row.id}
                    className={rowIndex > 0 ? 'border-t border-border/60 pt-3' : undefined}
                    aria-labelledby={`newest-category-title-${row.id}`}
                    data-testid={`newest-category-row-${row.id}`}
                  >
                    <div className="mb-2 space-y-2">
                      <h3
                        id={`newest-category-title-${row.id}`}
                        className="min-w-0 truncate text-sm font-bold text-foreground"
                      >
                        {row.label}
                      </h3>
                      {row.id === 'food-and-drinks' && (
                        <div role="group" aria-label="Filter kategori makanan dan minuman" className="flex flex-wrap gap-1.5">
                          {newestFoodDrinkFilterOptions.map((option) => {
                            const selected = newestFoodDrinkFilter === option.value;
                            return (
                              <button
                                key={option.value}
                                type="button"
                                aria-pressed={selected}
                                data-testid={`newest-food-drink-filter-${option.value}`}
                                onClick={() => setNewestFoodDrinkFilter(option.value)}
                                className={`rounded-full border px-3 py-1 text-[10px] font-semibold transition-colors ${selected ? 'border-primary bg-primary text-primary-foreground' : 'border-border bg-white text-muted-foreground hover:bg-muted'}`}
                              >
                                {option.label}
                              </button>
                            );
                          })}
                        </div>
                      )}
                    </div>
                    <div
                      className="flex snap-x snap-mandatory gap-3 overflow-x-auto pb-2 hide-scrollbar"
                      aria-label={`Produk terbaru kategori ${row.label}`}
                      data-testid={`list-newest-products-${row.id}`}
                    >
                      {visibleProducts.length > 0 ? visibleProducts.map((product, idx) => (
                        <div
                          key={product.id}
                          className="w-[48%] shrink-0 snap-start sm:w-[32%]"
                          data-testid={`newest-category-product-${row.id}-${product.id}`}
                        >
                          <ProductCard
                            product={product}
                            index={rowIndex * 4 + idx}
                            showCategoryBadge
                            flashSaleOverride={flashSalesByProduct.get(product.id) ?? null}
                            distanceKm={getProductDistance(product)}
                            deliveryEta={getDeliveryEta(getProductDistance(product))}
                          />
                        </div>
                      )) : row.id === 'food-and-drinks' && newestFoodDrinkFilter !== 'all' ? (
                        <div className="flex min-h-16 w-full items-center justify-center rounded-xl border border-dashed border-border/70 bg-muted/20 px-4 text-center text-xs text-muted-foreground" role="status" aria-live="polite" data-testid={`newest-category-filter-empty-${newestFoodDrinkFilter}`}>
                          Belum ada produk {newestFoodDrinkFilter === 'makanan' ? 'makanan' : 'minuman'} terbaru yang bisa ditampilkan.
                        </div>
                      ) : row.id === 'shopping' && shoppingCategoryCandidatesLoading ? (
                        <div className="flex min-h-16 w-full items-center justify-center rounded-xl border border-dashed border-border/70 bg-muted/20 px-4 text-center text-xs text-muted-foreground" data-testid={`newest-category-loading-${row.id}`}>
                          Memeriksa produk Belanja terbaru...
                        </div>
                      ) : row.id === 'shopping' && shoppingCategoryCandidatesError ? (
                        <div className="flex min-h-16 w-full flex-col items-center justify-center gap-2 rounded-xl border border-dashed border-destructive/30 bg-destructive/5 px-4 py-3 text-center text-xs text-muted-foreground" role="alert" data-testid={`newest-category-error-${row.id}`}>
                          <span>Produk Belanja gagal dimuat. Kategori tetap tersedia.</span>
                          <Button size="sm" variant="outline" onClick={() => void refetchShoppingCategoryCandidates()}>Coba lagi</Button>
                        </div>
                      ) : (
                        <div className="flex min-h-16 w-full items-center justify-center rounded-xl border border-dashed border-border/70 bg-muted/20 px-4 text-center text-xs text-muted-foreground" data-testid={`newest-category-empty-${row.id}`}>
                          Belum ada produk Belanja yang bisa ditampilkan. Kategori tetap tersedia di katalog.
                        </div>
                      )}
                    </div>
                    <div className="mt-1 flex justify-end">
                      <Link
                        to={categoryHref}
                        className="flex shrink-0 items-center gap-0.5 text-[10px] font-bold text-primary hover:underline"
                        data-testid={`link-newest-category-${row.id}`}
                      >
                        Lihat semua <ChevronRight className="h-3 w-3" />
                      </Link>
                    </div>
                  </section>
                  );
                })}
              </div>
            ) : (
              <div className="rounded-2xl border border-dashed border-orange-200 bg-orange-50/70 px-5 py-6 text-center">
                <div className="mx-auto mb-3 flex h-11 w-11 items-center justify-center rounded-2xl bg-orange-100 text-orange-700">
                  <Store className="h-5 w-5" />
                </div>
                <h3 className="font-heading text-sm font-extrabold text-foreground">
                  {newestMaxDistance !== 'all' ? 'Belum ada produk dalam jarak ini' : products.length > 0 ? 'Belum ada produk terbaru lainnya' : 'Belum ada produk baru'}
                </h3>
                <p className="mx-auto mt-1.5 max-w-[260px] text-[11px] leading-relaxed text-muted-foreground">
                  {newestMaxDistance !== 'all'
                    ? 'Perluas batas jarak untuk melihat lebih banyak produk terdekat.'
                    : products.length > 0
                    ? 'Produk yang ada mungkin sudah tampil di bagian promo. Jelajahi katalog untuk melihat semuanya.'
                    : 'Produk dari merchant lokal akan muncul di sini setelah ditambahkan.'}
                </p>
                <Button asChild size="sm" className="mt-4 rounded-full px-5">
                  <Link to={products.length > 0 ? '/products' : '/register/merchant'}>
                    {products.length > 0 ? 'Lihat semua produk' : 'Daftar Jadi Pedagang'}
                  </Link>
                </Button>
              </div>
            )}
          </section>
          </div>
        );
      
      case 'villages':
        if (villagesLoading) return <CarouselSkeleton count={3} />;
        if (villagesError)
          return (
            <SectionError
              title="Desa gagal dimuat"
              message="Daftar desa terdekat tidak dapat diambil."
              onRetry={() => refetchVillages()}
            />
          );
        return sortedVillages.length > 0 ? (
          <section className="px-5 pb-6">
            <div className="mb-2 flex items-center">
              <div className="flex items-center gap-2">
                <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-secondary text-primary">
                  <MapPin className="h-4 w-4" />
                </div>
                <div>
                  <h2 className="font-heading text-sm font-bold text-foreground">Desa Terdekat</h2>
                  <p className="text-[9px] text-muted-foreground flex items-center gap-1">
                    <MapPin className="h-2.5 w-2.5" />
                    {userLocation?.source === 'gps' ? 'Berdasarkan lokasi Anda' : 'Sekitar Anda'}
                  </p>
                </div>
              </div>
            </div>
            <div className="flex gap-3 overflow-x-auto hide-scrollbar pb-2">
              {sortedVillages.map((village) => (
                <VillageCard key={village.id} village={village} />
              ))}
            </div>
          </section>
        ) : null;
      
      default:
        return null;
    }
  };

  return (
    <div className="mobile-shell flex min-h-screen flex-col bg-background font-body">
      <Header />

      {/* Scrollable Content */}
      <main className="flex-1 overflow-y-auto">
        <>
          <h1 className="sr-only">Belanja kuliner dan layanan lokal di SaDesa</h1>
          <div className="pt-3">
            <MealTimeReminder />
          </div>
          <div className="mt-6 space-y-6 pb-6">
          {activeOrder && (
            <Dialog>
              <DialogTrigger asChild>
                <button type="button" className="fixed bottom-[calc(var(--bottom-nav-space)+4.25rem)] right-4 z-20 flex items-center gap-2 rounded-full border border-primary/20 bg-white px-3 py-2 text-left shadow-[0_12px_28px_-12px_hsl(4_78%_47%_/_0.55)] transition hover:-translate-y-0.5 hover:border-primary/40 sm:bottom-40 sm:right-7">
                  <span className="relative flex h-8 w-8 items-center justify-center rounded-full bg-primary text-primary-foreground">
                    {['ASSIGNED', 'PICKED_UP', 'DELIVERING', 'SENT'].includes(activeOrder.status) ? <Truck className="h-4 w-4" /> : <Receipt className="h-4 w-4" />}
                    <span className="absolute -right-0.5 -top-0.5 h-2.5 w-2.5 rounded-full border-2 border-white bg-green-500" />
                  </span>
                  <span>
                    <span className="block text-[9px] font-bold uppercase tracking-[0.12em] text-primary">Pesanan aktif</span>
                    <span className="block max-w-[115px] truncate text-[11px] font-bold text-foreground">#{activeOrder.id.slice(0, 8)} · Ketuk detail</span>
                  </span>
                </button>
              </DialogTrigger>
              <DialogContent className="max-w-[calc(100%-2rem)] rounded-2xl sm:max-w-md">
                <DialogHeader>
                  <DialogTitle className="flex items-center gap-2"><Receipt className="h-5 w-5 text-primary" /> Pesanan aktif</DialogTitle>
                  <DialogDescription>Ringkasan status pesanan yang sedang berjalan.</DialogDescription>
                </DialogHeader>
                <div className="flex items-center gap-3 rounded-xl bg-primary/5 p-4">
                  <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-primary text-primary-foreground">
                    {['ASSIGNED', 'PICKED_UP', 'DELIVERING', 'SENT'].includes(activeOrder.status) ? <Truck className="h-5 w-5" /> : <Receipt className="h-5 w-5" />}
                  </span>
                  <div className="min-w-0">
                    <p className="font-bold text-foreground">Pesanan #{activeOrder.id.slice(0, 8)}</p>
                    <p className="text-xs capitalize text-muted-foreground">Status: {activeOrder.status.replaceAll('_', ' ').toLowerCase()}</p>
                  </div>
                </div>
                <DialogFooter>
                  <Button asChild className="w-full sm:w-auto"><Link to={`/orders/${activeOrder.id}`}>Lihat detail pesanan <ChevronRight className="ml-1 h-4 w-4" /></Link></Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          )}
          {orderedSections.filter((section) => section.id !== 'contextual-recommendation').map((section) => {
            const content = renderSection(section.id);
            return content ? <div key={section.id}>{content}</div> : null;
          })}
          {/* Empty state when all data is empty */}
          {!loading && products.length === 0 && villages.length === 0 && tourismSpots.length === 0 && (
            <div className="flex flex-col items-center justify-center py-16 px-6 text-center">
              <div className="w-20 h-20 rounded-full bg-primary/10 flex items-center justify-center mb-5">
                <ShoppingBag className="h-10 w-10 text-primary" />
              </div>
              <h3 className="mb-2 font-heading text-lg font-bold text-foreground">Kuliner desa menanti Anda</h3>
              <p className="text-sm text-muted-foreground max-w-[280px] mb-6">
                Temukan kuliner, produk UMKM, dan layanan ojek di sekitar Anda.
              </p>
              <Button onClick={() => navigate('/shops')} className="rounded-full">
                <Store className="mr-2 h-4 w-4" /> Jelajahi Kuliner & UMKM
              </Button>
            </div>
          )}
          </div>
        </>
      </main>


      <BottomNav />
    </div>
  );
};

export default Index;
