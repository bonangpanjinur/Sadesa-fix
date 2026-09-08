import { useState, useMemo } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { ChevronRight, Sparkles, Flame, TrendingUp, MapPin, ShoppingBag, Store, Map, MoreHorizontal } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { FloatingCartButton } from '@/components/layout/FloatingCartButton';
import { Button } from '@/components/ui/button';
import { CategoryIcon } from '@/components/CategoryIcon';
import { BottomSheet } from '@/components/ui/BottomSheet';
import { PRIMARY_HOME_CATEGORIES, SECONDARY_HOME_CATEGORIES } from '@/lib/homeCategories';
import { VillageCard } from '@/components/VillageCard';
import { ProductCard } from '@/components/ProductCard';
import { HeroCarousel, type BannerSlide } from '@/components/home/HeroCarousel';
import { TourismCarousel } from '@/components/home/TourismCarousel';
import { 
  fetchProducts, 
  fetchVillages, 
  fetchTourism,
} from '@/lib/api';
import { fetchBannerPromotions } from '@/lib/promotions';
import { useHomepageLayout } from '@/hooks/useHomepageLayout';
import { CarouselSkeleton, ProductGridSkeleton, CategoriesSkeleton, HeroSkeleton } from '@/components/home/HomeSkeletons';
import { SectionError } from '@/components/home/SectionError';
import { logHomeSectionError } from '@/lib/homeErrorLog';
import { useUserLocation, sortByDistance } from '@/hooks/useUserLocation';
import type { Product, Village, Tourism } from '@/types';

const Index = () => {
  const navigate = useNavigate();
  const [visibleProductCount, setVisibleProductCount] = useState(12);
  
  const { 
    isSectionEnabled, 
    getEnabledSections, 
    loading: layoutLoading 
  } = useHomepageLayout();

  const { location: userLocation } = useUserLocation();
  const [categoriesSheetOpen, setCategoriesSheetOpen] = useState(false);

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
    queryKey: ['homepage-products'],
    queryFn: withErrorLog('products', 'homepage-products', { staleTime: 60_000 }, () =>
      fetchProducts()
    ),
    staleTime: 60_000,
  });

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
  });

  const {
    data: bannerSlides = [],
    isLoading: bannersLoading,
    isError: bannersError,
    refetch: refetchBanners,
  } = useQuery<BannerSlide[]>({
    queryKey: ['homepage-banners'],
    queryFn: withErrorLog('hero', 'homepage-banners', { staleTime: 120_000 }, async () => {
      const promotionsData = await fetchBannerPromotions();
      return promotionsData.map(p => ({
        id: p.id,
        title: p.title,
        subtitle: p.subtitle,
        image: p.imageUrl,
        linkUrl: p.linkUrl,
      }));
    }),
    staleTime: 120_000,
  });



  const loading = productsLoading || villagesLoading || tourismLoading;

  // Sort data by proximity to user location
  const sortedProducts = useMemo(() => {
    if (!userLocation) return products;
    return sortByDistance(products, userLocation.lat, userLocation.lng);
  }, [products, userLocation]);

  const sortedVillages = useMemo(() => {
    if (!userLocation) return villages;
    return sortByDistance(villages, userLocation.lat, userLocation.lng);
  }, [villages, userLocation]);

  const sortedTourism = useMemo(() => {
    if (!userLocation) return tourismSpots;
    return sortByDistance(tourismSpots, userLocation.lat, userLocation.lng);
  }, [tourismSpots, userLocation]);

  const promoProducts = sortedProducts.filter(p => p.isPromo);
  // Sort tourism by proximity first, then by view count
  const popularTourism = sortedTourism;
  
  // Primary categories are curated for the homepage; secondary categories stay in Lainnya.
  const visibleCategories = PRIMARY_HOME_CATEGORIES;

  // Build sections in order based on admin settings
  const enabledSections = getEnabledSections();

  const renderSection = (sectionId: string) => {
    switch (sectionId) {
      case 'hero':
        if (bannersLoading && bannerSlides.length === 0) return <HeroSkeleton />;
        if (bannersError && bannerSlides.length === 0)
          return (
            <SectionError
              compact
              title="Banner gagal dimuat"
              message="Promo unggulan tidak dapat ditampilkan saat ini."
              onRetry={() => refetchBanners()}
            />
          );
        return <HeroCarousel slides={bannerSlides} autoPlayInterval={5000} />;
      
      case 'categories':
        if (layoutLoading && visibleCategories.length === 0) return <CategoriesSkeleton />;
        return (
          <>
          <section className="mt-7 px-5">
            {layoutLoading && visibleCategories.length === 0 ? <CategoriesSkeleton /> : (
              <>
                <div className="mb-4 flex items-end justify-between">
                  <div>
                    <p className="text-[9px] font-bold uppercase text-primary">Jelajahi</p>
                    <h2 className="font-heading text-base font-bold text-foreground">Kategori Utama</h2>
                  </div>
                  <button type="button" onClick={() => setCategoriesSheetOpen(true)} className="text-[10px] font-bold text-primary">Lihat Semua</button>
                </div>
                <div className="grid grid-cols-4 gap-x-3 gap-y-5 rounded-lg border border-border/60 bg-card p-4 shadow-sm">
                  {visibleCategories.map((cat) => <CategoryIcon key={cat.id} {...cat} />)}
                  <button
                    type="button"
                    onClick={() => setCategoriesSheetOpen(true)}
                    className="group flex min-w-0 flex-col items-center gap-2"
                    aria-label="Buka kategori lainnya"
                  >
                    <div className="relative flex h-16 w-16 items-center justify-center overflow-hidden rounded-[1.25rem] border-2 border-white/70 bg-secondary text-muted-foreground shadow-[0_6px_16px_-8px_hsl(var(--foreground)/0.35)] transition-all duration-200 group-hover:-translate-y-1 group-hover:shadow-[0_12px_20px_-10px_hsl(var(--foreground)/0.45)] group-active:scale-95">
                      <MoreHorizontal className="h-7 w-7 stroke-[2.25] transition-transform duration-200 group-hover:scale-105" />
                    </div>
                    <span className="text-[11px] font-medium leading-tight text-muted-foreground">Lainnya</span>
                  </button>
                </div>
                <BottomSheet isOpen={categoriesSheetOpen} onClose={() => setCategoriesSheetOpen(false)} title="Kategori lainnya" snapPoints={[0.72, 0.92]}>
                  <div className="grid grid-cols-3 gap-x-3 gap-y-5 p-5">
                    {SECONDARY_HOME_CATEGORIES.map((cat) => <CategoryIcon key={cat.id} {...cat} />)}
                  </div>
                </BottomSheet>
              </>
            )}
          </section>
          </>
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
          <section className="mt-8 px-5">
            <div className="flex justify-between items-center mb-3">
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
        if (productsLoading) return <CarouselSkeleton count={3} />;
        if (productsError)
          return (
            <SectionError
              title="Promo gagal dimuat"
              message="Produk promo tidak dapat diambil saat ini."
              onRetry={() => refetchProducts()}
            />
          );
        return promoProducts.length > 0 ? (
          <section className="mt-8 px-5">
            <div className="flex items-center gap-2 mb-3">
              <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-accent/15 text-accent-foreground">
                <Sparkles className="h-4 w-4" />
              </div>
              <div>
                <h2 className="font-heading text-sm font-bold text-foreground">Promo Spesial</h2>
                <p className="text-[9px] text-muted-foreground">Hemat lebih banyak hari ini</p>
              </div>
            </div>
            <div className="flex gap-3 overflow-x-auto hide-scrollbar pb-2">
              {promoProducts.map((product, idx) => (
                <div key={product.id} className="min-w-[160px]">
                  <ProductCard product={product} index={idx} />
                </div>
              ))}
            </div>
          </section>
        ) : null;
      
      case 'recommendations':
        if (productsLoading) return <ProductGridSkeleton count={6} />;
        if (productsError)
          return (
            <SectionError
              title="Produk gagal dimuat"
              message="Kami tidak dapat mengambil daftar produk terdekat."
              onRetry={() => refetchProducts()}
            />
          );
        return sortedProducts.length > 0 ? (
          <section className="mt-8 px-5">
            <div className="sticky top-[116px] z-20 -mx-5 mb-4 flex items-center gap-2 border-y border-border/60 bg-background/95 px-5 py-3 backdrop-blur">
              <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/10 text-primary">
                <TrendingUp className="h-4 w-4" />
              </div>
              <div>
                <h2 className="font-heading text-sm font-bold text-foreground">Produk Unggulan</h2>
                <p className="text-[9px] text-muted-foreground flex items-center gap-1">
                  <MapPin className="h-2.5 w-2.5" />
                  {userLocation?.source === 'gps' ? 'Berdasarkan lokasi Anda' : 'Sekitar Anda'}
                </p>
              </div>
              <Link 
                to="/products"
                className="text-[10px] text-primary font-bold hover:underline flex items-center gap-0.5 ml-auto"
              >
                Lihat Semua
                <ChevronRight className="h-3 w-3" />
              </Link>
            </div>
            <div className="grid grid-cols-2 gap-3 pb-2">
              {sortedProducts.slice(0, visibleProductCount).map((product, idx) => (
                <ProductCard 
                  key={product.id} 
                  product={product} 
                  index={idx} 
                  showCategoryBadge={true}
                />
              ))}
            </div>
            {sortedProducts.length > visibleProductCount && (
              <div className="flex justify-center pb-4">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setVisibleProductCount(prev => prev + 12)}
                  className="text-xs"
                >
                  <ShoppingBag className="h-3.5 w-3.5 mr-1.5" />
                  Lihat Lebih Banyak ({sortedProducts.length - visibleProductCount} lagi)
                </Button>
              </div>
            )}
          </section>
        ) : null;
      
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
          <section className="mt-8 px-5 pb-8">
            <div className="flex justify-between items-center mb-3">
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
              <Link 
                to="/explore"
                className="text-[10px] text-primary font-bold hover:underline flex items-center gap-0.5"
              >
                Semua
                <ChevronRight className="h-3 w-3" />
              </Link>
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
      <main className="flex-1 overflow-y-auto pb-28">
        <>
          {enabledSections.map((section) => (
            <div key={section.id}>
              {renderSection(section.id)}
            </div>
          ))}
          {/* Empty state when all data is empty */}
          {!loading && products.length === 0 && villages.length === 0 && tourismSpots.length === 0 && (
            <div className="flex flex-col items-center justify-center py-16 px-6 text-center">
              <div className="w-20 h-20 rounded-full bg-primary/10 flex items-center justify-center mb-5">
                <ShoppingBag className="h-10 w-10 text-primary" />
              </div>
              <h3 className="text-lg font-bold text-foreground mb-2">Selamat Datang! 🎉</h3>
              <p className="text-sm text-muted-foreground max-w-[280px] mb-6">
                Platform ini baru diluncurkan. Jelajahi toko dan desa wisata di sekitar Anda.
              </p>
              <div className="flex gap-3">
                <Button variant="outline" onClick={() => navigate('/shops')} className="rounded-full">
                  <Store className="h-4 w-4 mr-2" /> Lihat Toko
                </Button>
                <Button onClick={() => navigate('/tourism')} className="rounded-full">
                  <Map className="h-4 w-4 mr-2" /> Wisata
                </Button>
              </div>
            </div>
          )}
        </>
      </main>


      <FloatingCartButton />
      <BottomNav />
    </div>
  );
};

export default Index;
