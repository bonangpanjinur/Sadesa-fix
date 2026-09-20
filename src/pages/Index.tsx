import { useState, useMemo, useCallback } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { ChevronRight, Sparkles, Flame, MapPin, ShoppingBag, Store, UtensilsCrossed, Receipt, Truck } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Button } from '@/components/ui/button';
import { CategoryIcon } from '@/components/CategoryIcon';
import { VillageCard } from '@/components/VillageCard';
import { ProductCard } from '@/components/ProductCard';
import { HeroCarousel, type BannerSlide } from '@/components/home/HeroCarousel';
import { TourismCarousel } from '@/components/home/TourismCarousel';
import { ContextualRecommendation } from '@/components/home/ContextualRecommendation';
import { 
  fetchProducts, 
  fetchVillages, 
  fetchTourism,
} from '@/lib/api';
import { fetchActiveHomepageAds, fetchBannerPromotions, incrementPromotionView, incrementPromotionClick, type MerchantAd } from '@/lib/promotions';
import { useHomepageLayout } from '@/hooks/useHomepageLayout';
import { CarouselSkeleton, ProductGridSkeleton, HeroSkeleton } from '@/components/home/HomeSkeletons';
import { SectionError } from '@/components/home/SectionError';
import { logHomeSectionError } from '@/lib/homeErrorLog';
import { useUserLocation, sortByDistance, calculateDistance } from '@/hooks/useUserLocation';
import { useCategories } from '@/hooks/useCategories';
import { PRIMARY_HOME_CATEGORIES } from '@/lib/homeCategories';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
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

const Index = () => {
  // Sementara fokus publik diarahkan ke kuliner dan ojek. Data, route, dan
  // pengaturan desa wisata tetap dipertahankan agar bisa diaktifkan kembali.
  const HIDDEN_VILLAGE_FEATURES = new Set(['popular_tourism', 'villages']);
  const navigate = useNavigate();
  const [visibleProductCount, setVisibleProductCount] = useState(12);
  const [promoFilter, setPromoFilter] = useState<'semua' | 'makanan' | 'minuman' | 'produk'>('semua');
  const [showContextualRecommendation, setShowContextualRecommendation] = useState(true);
  
  const { getEnabledSections } = useHomepageLayout();
  const { getHomepageCategories } = useCategories();
  const { user } = useAuth();
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
      return promotionsData
        .filter((promotion) => {
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

  const { data: sponsoredAds = [] } = useQuery<MerchantAd[]>({
    queryKey: ['homepage-sponsored-ads'],
    queryFn: fetchActiveHomepageAds,
    staleTime: 60_000,
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
  const filteredPromoProducts = useMemo(() => {
    if (promoFilter === 'semua') return promoProducts;
    return promoProducts.filter((product) => {
      const haystack = `${product.name} ${product.description} ${product.category}`.toLowerCase();
      const isKuliner = product.category.toLowerCase() === 'kuliner';
      const isDrink = /minum|kopi|teh|jus|susu|es |cokelat|cafe|cappuccino|latte/.test(haystack);
      if (promoFilter === 'makanan') return isKuliner && !isDrink;
      if (promoFilter === 'minuman') return isKuliner && isDrink;
      return !isKuliner;
    });
  }, [promoFilter, promoProducts]);
  const culinaryProductCategories = new Set(['kuliner', 'makanan', 'minuman', 'camilan']);
  const nearbyFoodProducts = sortedProducts.filter((product) =>
    culinaryProductCategories.has(product.category.trim().toLowerCase()),
  );
  // Sort tourism by proximity first, then by view count
  const popularTourism = sortedTourism;
  
  // Pesan Makanan dan Ojek adalah layanan inti dan harus selalu tersedia di tampilan awal.
  // Data admin tetap dipakai untuk label/style, tetapi tidak boleh menghilangkan dua layanan utama
  // jika konfigurasi kategori belum termuat atau salah satu kategori dinonaktifkan.
  const configuredCategories = getHomepageCategories();
  const visibleCategories = ['kuliner', 'ojek'].map((categoryId) =>
    configuredCategories.find((category) => category.id === categoryId)
      || PRIMARY_HOME_CATEGORIES.find((category) => category.id === categoryId),
  ).filter(Boolean);

  // Build sections in order based on admin settings
  const enabledSections = getEnabledSections();
  const sectionPriority: Record<string, number> = {
    // Banner menjadi discovery/promo lanjutan, bukan konten pertama yang menghalangi tugas utama.
    hero: 6,
    categories: 1,
    promo: 3,
    recommendations: 4,
    popular_tourism: 5,
    villages: 7,
  };
  const orderedSections = [...enabledSections].sort(
    (a, b) => (sectionPriority[a.id] ?? 99) - (sectionPriority[b.id] ?? 99),
  );

  const getProductDistance = (product: Product) => {
    if (!userLocation || product.locationLat == null || product.locationLng == null) return undefined;
    return calculateDistance(userLocation.lat, userLocation.lng, product.locationLat, product.locationLng);
  };

  const getDeliveryEta = (distanceKm?: number) => {
    if (distanceKm == null) return undefined;
    if (distanceKm < 1) return '15–25 menit';
    if (distanceKm < 3) return '20–30 menit';
    return '30–45 menit';
  };

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
        return <HeroCarousel slides={bannerSlides} autoPlayInterval={5000} onView={handleBannerView} onClick={handleBannerClick} />;
      
      case 'categories':
        return (
          <section className="relative mx-4 mt-5 overflow-hidden rounded-[1.65rem] border border-orange-100 bg-[linear-gradient(135deg,hsl(42_100%_98%),hsl(12_100%_96%))] px-5 py-5 shadow-[0_18px_42px_-28px_hsl(4_78%_47%_/_0.55)]" aria-label="Layanan utama">
            <div className="pointer-events-none absolute -right-8 -top-10 h-32 w-32 rounded-full bg-[hsl(43_96%_55%_/_0.18)]" />
            <div className="pointer-events-none absolute -bottom-16 -left-10 h-32 w-32 rounded-full bg-[hsl(4_78%_47%_/_0.08)]" />
            <div className="relative mb-3">
              <p className="text-[9px] font-bold uppercase tracking-[0.16em] text-primary">Layanan utama</p>
              <h2 className="mt-1 font-heading text-[1.08rem] font-extrabold tracking-[-0.02em] text-foreground">Mau makan apa hari ini?</h2>
            </div>
            <div className="relative grid grid-cols-2 gap-3">
              {visibleCategories.map((category) => (
                <CategoryIcon key={category.id} {...category} />
              ))}
            </div>
          </section>
        );

      case 'contextual-recommendation':
        return showContextualRecommendation ? (
          <ContextualRecommendation onDismiss={() => setShowContextualRecommendation(false)} />
        ) : null;
      
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
          <section className="mt-9 px-5">
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
          <section className="mx-4 mt-8 rounded-[1.65rem] border border-orange-100 bg-[linear-gradient(135deg,hsl(8_100%_98%),hsl(42_100%_97%))] px-5 py-5 shadow-[0_16px_36px_-28px_hsl(4_78%_47%_/_0.45)]">
            <div className="flex items-center gap-2 mb-3">
              <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-[hsl(4_78%_47%_/_0.1)] text-primary">
                <Sparkles className="h-4 w-4" />
              </div>
              <div>
                <h2 className="font-heading text-base font-bold text-foreground">Promo Kuliner & Produk</h2>
                <p className="text-[10px] text-muted-foreground">Pilihan lokal dengan harga spesial</p>
              </div>
            </div>
            <div className="mb-4 flex gap-2 overflow-x-auto hide-scrollbar pb-1">
              {([
                ['semua', 'Semua'],
                ['makanan', 'Makanan'],
                ['minuman', 'Minuman'],
                ['produk', 'Produk'],
              ] as const).map(([value, label]) => (
                <button
                  key={value}
                  type="button"
                  onClick={() => setPromoFilter(value)}
                  className={`shrink-0 rounded-full px-3.5 py-2 text-[10px] font-bold transition active:scale-95 ${promoFilter === value ? 'bg-primary text-primary-foreground shadow-sm' : 'bg-white text-muted-foreground ring-1 ring-orange-100 hover:text-primary'}`}
                >
                  {label}
                </button>
              ))}
            </div>
            {filteredPromoProducts.length > 0 ? <div className="flex gap-3 overflow-x-auto hide-scrollbar pb-2">
              {filteredPromoProducts.map((product, idx) => (
                <div key={product.id} className="min-w-[160px]">
                  <ProductCard product={product} index={idx} distanceKm={getProductDistance(product)} deliveryEta={getDeliveryEta(getProductDistance(product))} />
                </div>
              ))}
            </div> : <p className="rounded-xl bg-white/70 px-3 py-4 text-center text-[11px] text-muted-foreground">Belum ada promo di kategori ini.</p>}
          </section>
        ) : null;
      
      case 'recommendations':
        if (productsLoading) return <ProductGridSkeleton count={6} />;
        if (productsError)
          return (
            <section className="mx-4 mt-8 overflow-hidden rounded-[1.65rem] border border-emerald-100 bg-[linear-gradient(135deg,hsl(152_61%_97%),hsl(43_100%_97%))] px-5 py-5 shadow-[0_18px_40px_-28px_hsl(152_61%_35%_/_0.5)]" aria-label="Ajakan menjadi mitra merchant">
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
                    <Button variant="ghost" size="sm" onClick={() => refetchProducts()} className="h-9 rounded-full px-3 text-xs text-muted-foreground">
                      Coba muat produk
                    </Button>
                  </div>
                </div>
              </div>
            </section>
          );
        return (
          <section className="mx-4 mt-8 rounded-[1.65rem] border border-orange-100 bg-white px-5 py-5 shadow-[0_16px_36px_-28px_hsl(4_78%_47%_/_0.35)]">
            <div className="mb-4 flex items-center gap-2">
                <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-[hsl(43_96%_55%_/_0.2)] text-[hsl(28_84%_36%)]">
                <UtensilsCrossed className="h-4 w-4" />
              </div>
              <div>
                <h2 className="font-heading text-base font-bold text-foreground">Kuliner di Sekitar Kamu</h2>
                <p className="text-[10px] text-muted-foreground flex items-center gap-1">
                  <MapPin className="h-2.5 w-2.5" />
                  {userLocation?.source === 'gps' ? 'Berdasarkan lokasi Anda' : 'Sekitar Anda'}
                </p>
              </div>
              {nearbyFoodProducts.length > 0 && (
                <Link
                  to="/products?category=kuliner"
                  className="ml-auto flex items-center gap-0.5 text-[10px] font-bold text-primary hover:underline"
                >
                  Lihat Semua
                  <ChevronRight className="h-3 w-3" />
                </Link>
              )}
            </div>
            {nearbyFoodProducts.length > 0 ? (
              <>
                <div className="grid grid-cols-2 gap-3.5 pb-2">
                  {nearbyFoodProducts.slice(0, visibleProductCount).map((product, idx) => (
                    <ProductCard
                      key={product.id}
                      product={product}
                      index={idx}
                      showCategoryBadge={true}
                      distanceKm={getProductDistance(product)}
                      deliveryEta={getDeliveryEta(getProductDistance(product))}
                    />
                  ))}
                </div>
                {nearbyFoodProducts.length > visibleProductCount && (
                  <div className="flex justify-center pb-4">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => setVisibleProductCount(prev => prev + 12)}
                      className="text-xs"
                    >
                      <ShoppingBag className="h-3.5 w-3.5 mr-1.5" />
                      Lihat Lebih Banyak ({nearbyFoodProducts.length - visibleProductCount} lagi)
                    </Button>
                  </div>
                )}
              </>
            ) : (
              <div className="rounded-2xl border border-dashed border-orange-200 bg-orange-50/70 px-5 py-6 text-center">
                <div className="mx-auto mb-3 flex h-11 w-11 items-center justify-center rounded-2xl bg-orange-100 text-orange-700">
                  <Store className="h-5 w-5" />
                </div>
                <h3 className="font-heading text-sm font-extrabold text-foreground">
                  Yuk daftar jadi pedagang sekarang
                </h3>
                <p className="mx-auto mt-1.5 max-w-[260px] text-[11px] leading-relaxed text-muted-foreground">
                  Jadilah merchant kuliner pertama di sekitar sini dan mulai jual makananmu.
                </p>
                <Button asChild size="sm" className="mt-4 rounded-full px-5">
                  <Link to="/register/merchant">Daftar Jadi Pedagang</Link>
                </Button>
              </div>
            )}
          </section>
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
      <main className="flex-1 overflow-y-auto pb-32">
        <>
          {showContextualRecommendation && (
            <ContextualRecommendation
              products={products}
              sponsoredAds={sponsoredAds}
              userLocation={userLocation}
              onDismiss={() => setShowContextualRecommendation(false)}
            />
          )}
          {enabledSections.some((section) => section.id === 'categories') && renderSection('categories')}
          {activeOrder && (
            <Dialog>
              <DialogTrigger asChild>
                <button type="button" className="fixed bottom-24 right-4 z-20 flex items-center gap-2 rounded-full border border-primary/20 bg-white px-3 py-2 text-left shadow-[0_12px_28px_-12px_hsl(4_78%_47%_/_0.55)] transition hover:-translate-y-0.5 hover:border-primary/40 sm:right-7">
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
          {orderedSections.filter((section) => !HIDDEN_VILLAGE_FEATURES.has(section.id) && section.id !== 'categories' && section.id !== 'contextual-recommendation').map((section) => (
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
              <h3 className="mb-2 font-heading text-lg font-bold text-foreground">Kuliner desa menanti Anda</h3>
              <p className="text-sm text-muted-foreground max-w-[280px] mb-6">
                Temukan kuliner, produk UMKM, dan layanan ojek di sekitar Anda.
              </p>
              <div className="flex gap-3">
                <Button variant="outline" onClick={() => navigate('/shops')} className="rounded-full">
                  <Store className="h-4 w-4 mr-2" /> Lihat Toko
                </Button>
                <Button onClick={() => navigate('/shops')} className="rounded-full">
                  <Store className="h-4 w-4 mr-2" /> Kuliner & UMKM
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
