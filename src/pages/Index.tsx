import { useState, useMemo } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { ChevronRight, Sparkles, Flame, TrendingUp, MapPin, ShoppingBag, Store, Map, MoreHorizontal } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Button } from '@/components/ui/button';
import { CategoryIcon } from '@/components/CategoryIcon';
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
import { useCategories } from '@/hooks/useCategories';
import {
  Drawer,
  DrawerContent,
  DrawerDescription,
  DrawerHeader,
  DrawerTitle,
} from '@/components/ui/drawer';
import type { Product, Village, Tourism } from '@/types';

const Index = () => {
  const navigate = useNavigate();
  const [visibleProductCount, setVisibleProductCount] = useState(12);
  
  const { 
    isSectionEnabled, 
    getEnabledSections, 
    loading: layoutLoading 
  } = useHomepageLayout();
  const {
    loading: categoriesLoading,
    error: categoriesError,
    getHomepageCategories,
    getOtherCategories,
    refetch: refetchCategories,
  } = useCategories();
  const [moreCategoriesOpen, setMoreCategoriesOpen] = useState(false);

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
  
  // Admin-managed active categories are the single source of truth for this menu.
  const visibleCategories = getHomepageCategories();
  const otherCategories = getOtherCategories();

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
        if (categoriesLoading && visibleCategories.length === 0) return <CategoriesSkeleton />;
        if (categoriesError && visibleCategories.length === 0) {
          return (
            <section className="mt-7 px-5">
              <SectionError
                compact
                title="Kategori gagal dimuat"
                message="Admin belum dapat memuat daftar kategori saat ini."
                onRetry={() => void refetchCategories()}
              />
            </section>
          );
        }
        return (
          <>
          <section className="mt-7 px-5">
             {categoriesLoading && visibleCategories.length === 0 ? <CategoriesSkeleton /> : (
              <>
                 <div className="mb-4 flex items-end justify-between">
                   <div>
                     <p className="text-[9px] font-bold uppercase tracking-[0.16em] text-primary">Jelajahi</p>
                     <h2 className="font-heading text-base font-bold text-foreground">Kategori utama</h2>
                     <p className="mt-0.5 text-[11px] text-muted-foreground">Pilihan cepat untuk mulai menjelajah</p>
                   </div>
                 </div>
                  <div
                    className="grid grid-cols-5 gap-0.5 rounded-2xl border border-border/60 bg-card p-2 shadow-sm sm:gap-1.5 sm:p-3"
                   aria-label="Kategori utama"
                 >
                  {visibleCategories.map((cat) => <CategoryIcon key={cat.id} {...cat} />)}
                   {otherCategories.length > 0 && (
                     <button
                       type="button"
                       onClick={() => setMoreCategoriesOpen(true)}
                       className="group flex min-w-0 flex-col items-center gap-1 sm:gap-1.5"
                       aria-label="Lihat kategori lainnya"
                     >
                       <span className="relative flex h-[clamp(2.75rem,12vw,3.25rem)] w-[clamp(2.75rem,12vw,3.25rem)] items-center justify-center overflow-hidden rounded-[1rem] border-2 border-white/70 bg-slate-100 text-slate-600 shadow-[0_6px_16px_-8px_hsl(var(--foreground)/0.35)] transition-all group-hover:-translate-y-1 group-hover:bg-slate-200 group-active:scale-95">
                         <MoreHorizontal className="h-5 w-5 stroke-[2.25] sm:h-6 sm:w-6" />
                       </span>
                       <span className="line-clamp-1 w-full text-center text-[10px] font-medium leading-tight text-muted-foreground sm:text-[11px]">Lainnya</span>
                     </button>
                   )}
                </div>
              </>
            )}
          </section>
           <Drawer open={moreCategoriesOpen} onOpenChange={setMoreCategoriesOpen}>
             <DrawerContent className="mx-auto max-w-[480px]">
               <DrawerHeader className="px-5 pb-3 text-left">
                 <DrawerTitle className="font-heading text-lg">Kategori lainnya</DrawerTitle>
                 <DrawerDescription>Pilih kategori untuk melihat produk yang sesuai.</DrawerDescription>
               </DrawerHeader>
               <div className="max-h-[55vh] overflow-y-auto px-5 pb-8">
                 <div className="grid grid-cols-4 gap-x-3 gap-y-5 rounded-2xl border border-border/60 bg-card p-4">
                   {otherCategories.map((category) => (
                     <CategoryIcon key={category.id} {...category} />
                   ))}
                 </div>
               </div>
             </DrawerContent>
           </Drawer>
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


      <BottomNav />
    </div>
  );
};

export default Index;
