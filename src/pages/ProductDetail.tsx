import { useState, useEffect } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { motion } from 'framer-motion';
import { useQuery } from '@tanstack/react-query';
import { 
  ArrowLeft, 
  Minus, 
  Plus,
  ShoppingCart,
  Star,
  MapPin,
  BadgeCheck,
  Clock,
  AlertTriangle
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { fetchProduct, checkMerchantHasActiveQuota } from '@/lib/api';
import { useCart } from '@/contexts/CartContext';
import { formatPrice, safeGoBack } from '@/lib/utils';
import { WishlistButton } from '@/components/WishlistButton';
import { ShareProduct } from '@/components/product/ShareProduct';
import { MerchantClosedBanner, MerchantStatusBadge } from '@/components/merchant/MerchantClosedBanner';
import { getMerchantOperatingStatus, formatTime, type OperatingDaySchedule } from '@/lib/merchantOperatingHours';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { trackPageView } from '@/lib/pageViewTracker';
import { addToRecentlyViewed } from '@/lib/recentlyViewed';
import type { CartTopping, Product, ProductTopping } from '@/types';
import { ProductReviews } from '@/components/product/ProductReviews';
import { SimilarProducts } from '@/components/product/SimilarProducts';
import { ProductImageGallery } from '@/components/product/ProductImageGallery';
import { MerchantAvatar } from '@/components/merchant/MerchantAvatar';
import { getProductUnavailableReason } from '@/lib/productAvailability';

interface MerchantInfo {
  id: string;
  name: string;
  phone: string | null;
  address: string | null;
  ratingAvg: number;
  ratingCount: number;
  badge: string | null;
  isOpen: boolean;
  openTime: string | null;
  closeTime: string | null;
  villageName: string | null;
  isVerified: boolean;
  halalStatus: string | null;
  slug: string | null;
  imageUrl: string | null;
}

interface ProductToppingRow {
  products?: {
    id: string;
    name: string;
    price: number | string | null;
    stock: number | null;
    image_url: string | null;
  } | null;
}

export default function ProductDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { addToCart } = useCart();
  const [quantity, setQuantity] = useState(1);
  const [selectedToppings, setSelectedToppings] = useState<CartTopping[]>([]);

  // React Query: product data with caching (P3-01)
  const { data: product = null, isLoading: productLoading } = useQuery<Product | null>({
    queryKey: ['product', id],
    queryFn: async () => {
      if (!id) return null;
      const productData = await fetchProduct(id);
      if (productData) {
        // Side effects on product load
        addToRecentlyViewed({
          id: productData.id,
          name: productData.name,
          price: productData.price,
          image: productData.image,
          merchantName: productData.merchantName,
        });
        Promise.resolve(supabase.rpc('increment_product_view', { product_id: id })).catch(() => {});
        trackPageView({ merchantId: productData.merchantId, productId: id, pageType: 'product' });
      }
      return productData;
    },
    enabled: !!id,
    staleTime: 30_000,
  });

  // React Query: merchant data depends on product
  const { data: merchantResult } = useQuery({
    queryKey: ['product-merchant', product?.merchantId],
    queryFn: async () => {
      if (!product?.merchantId) return { merchant: null, hasActiveQuota: true };
      const { data: merchantData } = await supabase
        .from('merchants')
        .select(`id, name, phone, address, image_url, rating_avg, rating_count, badge, is_open, open_time, close_time, is_verified, halal_status, slug, villages (name)`)
        .eq('id', product.merchantId)
        .maybeSingle();
      if (!merchantData) return { merchant: null, hasActiveQuota: true };
      const merchant: MerchantInfo = {
        id: merchantData.id,
        name: merchantData.name,
        phone: merchantData.phone,
        address: merchantData.address,
        ratingAvg: Number(merchantData.rating_avg) || 0,
        ratingCount: merchantData.rating_count || 0,
        badge: merchantData.badge,
        isOpen: merchantData.is_open,
        openTime: merchantData.open_time,
        closeTime: merchantData.close_time,
        villageName: (merchantData.villages as unknown as { name: string } | null)?.name || null,
        isVerified: merchantData.is_verified || false,
        halalStatus: merchantData.halal_status || null,
        slug: merchantData.slug || null,
        imageUrl: merchantData.image_url || null,
      };
      const hasActiveQuota = await checkMerchantHasActiveQuota(merchantData.id);
      return { merchant, hasActiveQuota };
    },
    enabled: !!product?.merchantId,
    staleTime: 30_000,
  });

  const merchant = merchantResult?.merchant ?? null;
  const hasActiveQuota = merchantResult?.hasActiveQuota ?? true;
  const loading = productLoading;

  const { data: weeklySchedule = [] } = useQuery<OperatingDaySchedule[]>({
    queryKey: ['merchant-operating-hours', product?.merchantId],
    queryFn: async () => {
      if (!product?.merchantId) return [];
      const { data, error } = await supabase
        .from('merchant_operating_hours')
        .select('day_of_week, open_time, close_time, is_closed')
        .eq('merchant_id', product.merchantId)
        .order('day_of_week', { ascending: true });
      if (error) throw error;
      return (data || []) as OperatingDaySchedule[];
    },
    enabled: !!product?.merchantId,
    staleTime: 30_000,
  });

  const { data: toppingOptions = [] } = useQuery<ProductTopping[]>({
    queryKey: ['product-toppings', product?.id],
    queryFn: async () => {
      if (!product?.id) return [];
      const { data, error } = await supabase
        .from('product_toppings')
        .select('topping_product_id, products:topping_product_id(id, name, price, stock, image_url)')
        .eq('product_id', product.id)
        .order('sort_order');
      if (error) throw error;
      const rows = (data || []) as unknown as ProductToppingRow[];
      return rows
        .map((row) => row.products)
        .filter((item): item is NonNullable<ProductToppingRow['products']> => Boolean(item?.id))
        .map((item) => ({
          id: item.id,
          name: item.name,
          price: Number(item.price) || 0,
          stock: Number(item.stock) || 0,
          image: item.image_url || undefined,
        }));
    },
    enabled: !!product?.id,
    staleTime: 30_000,
  });

  // Get merchant operating status
  const merchantStatus = merchant 
    ? getMerchantOperatingStatus(merchant.isOpen, merchant.openTime, merchant.closeTime, weeklySchedule)
    : null;
  
  if (loading) {
    return (
      <div className="mobile-shell flex items-center justify-center min-h-screen">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
      </div>
    );
  }

  if (!product) {
    return (
      <div className="mobile-shell flex items-center justify-center min-h-screen">
        <div className="text-center">
          <p className="text-muted-foreground mb-4">Produk tidak ditemukan</p>
          <Button onClick={() => navigate('/')}>Kembali</Button>
        </div>
      </div>
    );
  }

  const handleAddToCart = () => {
    const unavailableReason = getProductUnavailableReason({
      isActive: product.isActive,
      stock: product.stock,
      hasQuota: hasActiveQuota,
      isMerchantOpen: merchantStatus?.isCurrentlyOpen !== false,
    });
    if (unavailableReason) {
      toast({
        title: 'Produk tidak tersedia',
        description: unavailableReason,
        variant: 'destructive',
      });
      return;
    }
    addToCart(product, quantity, selectedToppings);
    toast({
      title: '✅ Ditambahkan ke keranjang',
      description: `${quantity}x ${product.name}`,
      action: (
        <Button size="sm" variant="outline" onClick={() => navigate('/cart')}>
          Lihat Keranjang
        </Button>
      ),
    });
  };

  const handleBuyNow = () => {
    const unavailableReason = getProductUnavailableReason({
      isActive: product.isActive,
      stock: product.stock,
      hasQuota: hasActiveQuota,
      isMerchantOpen: merchantStatus?.isCurrentlyOpen !== false,
    });
    if (unavailableReason) {
      toast({ title: 'Produk tidak tersedia', description: unavailableReason, variant: 'destructive' });
      return;
    }
    addToCart(product, quantity, selectedToppings);
    navigate('/checkout');
  };

  const unavailableReason = getProductUnavailableReason({
    isActive: product.isActive,
    stock: product.stock,
    hasQuota: hasActiveQuota,
    isMerchantOpen: merchantStatus?.isCurrentlyOpen !== false,
  });
  const canOrder = !unavailableReason;
  const selectedToppingTotal = selectedToppings.reduce((sum, item) => sum + item.product.price * item.quantity, 0);

  return (
    <div className="mobile-shell bg-card flex flex-col min-h-screen relative">
      {/* Scrollable Content */}
      <div className="flex-1 overflow-y-auto pb-36">
        {/* Product Image */}
        <ProductImageGallery productId={product.id} mainImage={product.image} productName={product.name} />
          
        {/* Top Navigation - now outside gallery */}
        <div className="absolute top-0 left-0 w-full p-4 flex justify-between items-center z-20">
          <button 
            onClick={() => safeGoBack(navigate)}
            className="w-10 h-10 bg-foreground/20 backdrop-blur rounded-full flex items-center justify-center text-primary-foreground hover:bg-foreground/40 transition border border-primary-foreground/20"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>
          <div className="flex items-center gap-2">
            <WishlistButton productId={id || ''} size="md" />
            <div className="w-10 h-10 bg-foreground/20 backdrop-blur rounded-full flex items-center justify-center text-primary-foreground hover:bg-foreground/40 transition border border-primary-foreground/20">
              <ShareProduct 
                productId={id || ''} 
                productName={product?.name || ''} 
                productImage={product?.image}
              />
            </div>
          </div>
        </div>
        
        {/* Content */}
        <motion.div 
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="px-6 pt-4"
        >
          <div className="flex justify-between items-start mb-2">
            <h2 className="text-xl font-bold text-foreground leading-tight flex-1">
              {product.name}
            </h2>
            <span className="bg-brand-light text-primary text-xs font-bold px-2 py-1 rounded-lg ml-2">
              Stok: {product.stock}
            </span>
          </div>
          
          <div className="flex items-center gap-2 mb-4">
            {product.originalPrice ? (
              <>
                <p className="text-sm line-through text-muted-foreground">
                  {formatPrice(product.originalPrice)}
                </p>
                <p className="text-2xl font-bold text-primary">
                  {formatPrice(product.price)}
                </p>
                <span className="bg-destructive text-destructive-foreground text-xs font-bold px-2 py-0.5 rounded">
                  -{product.discountPercent}%
                </span>
              </>
            ) : (
              <p className="text-2xl font-bold text-primary">
                {formatPrice(product.price)}
              </p>
            )}
            {merchant && merchant.ratingCount > 0 && (
              <div className="flex items-center gap-0.5 text-gold ml-2">
                <Star className="h-4 w-4 fill-current" />
                <span className="text-xs font-medium text-foreground">
                  {merchant.ratingAvg.toFixed(1)}
                </span>
                <span className="text-[10px] text-muted-foreground">({merchant.ratingCount})</span>
              </div>
            )}
            {merchant?.halalStatus === 'VERIFIED' && (
              <div className="ml-auto flex items-center gap-1 bg-green-50 text-green-600 px-2 py-1 rounded-lg border border-green-100">
                <BadgeCheck className="h-3.5 w-3.5" />
                <span className="text-[10px] font-bold">TERVERIFIKASI HALAL</span>
              </div>
            )}
          </div>

          {/* Merchant No Quota Banner */}
          {merchant && unavailableReason && (
            <div className="mb-4 p-4 bg-destructive/10 border border-destructive/20 rounded-xl">
              <div className="flex items-start gap-3">
                <AlertTriangle className="h-5 w-5 text-destructive flex-shrink-0 mt-0.5" />
                <div>
                  <p className="font-bold text-destructive text-sm">Produk Tidak Dapat Dipesan</p>
                  <p className="text-xs text-destructive/80 mt-1">
                    {unavailableReason}. Silakan cari produk serupa dari toko lain.
                  </p>
                </div>
              </div>
            </div>
          )}

          {/* Merchant Closed Banner */}
          {merchant && hasActiveQuota && !merchantStatus?.isCurrentlyOpen && (
            <div className="mb-4">
              <MerchantClosedBanner
                isManuallyOpen={merchant.isOpen}
                openTime={merchant.openTime}
                closeTime={merchant.closeTime}
                merchantName={merchant.name}
                weeklySchedule={weeklySchedule}
              />
            </div>
          )}
          
          {/* Merchant Info - Clickable to Store */}
          {merchant && (
            <Link 
              to={`/merchant/${merchant.slug || merchant.id}`}
              className="block mb-6 p-3 bg-secondary rounded-xl border border-border hover:border-primary/30 transition group"
            >
              <div className="flex items-center gap-3">
                <MerchantAvatar
                  imageUrl={merchant.imageUrl}
                  merchantName={merchant.name}
                  className="h-10 w-10 rounded-full"
                  iconClassName="h-5 w-5"
                />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-1.5 flex-wrap">
                    <p className="font-bold text-sm text-foreground truncate group-hover:text-primary transition">
                      {merchant.name}
                    </p>
                    {(merchant.badge === 'VERIFIED' || merchant.isVerified) && (
                      <BadgeCheck className="h-4 w-4 text-primary flex-shrink-0" />
                    )}
                    <MerchantStatusBadge
                      isManuallyOpen={merchant.isOpen}
                      openTime={merchant.openTime}
                      closeTime={merchant.closeTime}
                      hasQuota={hasActiveQuota}
                      weeklySchedule={weeklySchedule}
                    />
                  </div>
                  <div className="flex items-center gap-2 text-[10px] text-muted-foreground mt-0.5">
                    {merchant.villageName && (
                      <>
                        <span className="flex items-center gap-0.5">
                          <MapPin className="h-2.5 w-2.5" />
                          {merchant.villageName}
                        </span>
                        <span>•</span>
                      </>
                    )}
                    <span className="flex items-center gap-0.5">
                      <Star className="h-2.5 w-2.5 fill-gold text-gold" />
                      {merchant.ratingAvg.toFixed(1)}
                    </span>
                    <span>•</span>
                    <span className="flex items-center gap-0.5">
                      <Clock className="h-2.5 w-2.5" />
                      {formatTime(merchant.openTime || '08:00')} - {formatTime(merchant.closeTime || '17:00')}
                    </span>
                  </div>
                </div>
                <div className="text-xs text-muted-foreground group-hover:text-primary transition">
                  Lihat Toko →
                </div>
              </div>
            </Link>
          )}

          <h3 className="font-bold text-sm text-foreground mb-2">Deskripsi</h3>
          <p className="text-sm text-muted-foreground leading-relaxed mb-6">
            {product.description}
          </p>

          {toppingOptions.length > 0 && (
            <div className="mb-6 rounded-2xl border border-border bg-secondary/40 p-4">
              <div className="mb-3">
                <h3 className="font-bold text-sm text-foreground">Tambahkan topping</h3>
                <p className="text-xs text-muted-foreground">Pilih dari produk yang tersedia di toko ini.</p>
              </div>
              <div className="space-y-2">
                {toppingOptions.map((topping) => {
                  const selected = selectedToppings.find((item) => item.product.id === topping.id);
                  const unavailable = topping.stock <= 0;
                  return (
                    <button
                      type="button"
                      key={topping.id}
                      disabled={unavailable}
                      onClick={() => setSelectedToppings((current) => selected
                        ? current.filter((item) => item.product.id !== topping.id)
                        : [...current, { product: topping, quantity: 1 }])}
                      className={`w-full flex items-center justify-between rounded-xl border p-3 text-left transition ${selected ? 'border-primary bg-primary/5' : 'border-border bg-card'} ${unavailable ? 'opacity-50 cursor-not-allowed' : 'hover:border-primary/60'}`}
                    >
                      <span>
                        <span className="block text-sm font-medium">{topping.name}</span>
                        <span className="text-xs text-muted-foreground">{unavailable ? 'Stok habis' : `Stok ${topping.stock}`}</span>
                      </span>
                      <span className="text-sm font-semibold text-primary">+{formatPrice(topping.price)}</span>
                    </button>
                  );
                })}
              </div>
            </div>
          )}

          {/* Reviews Section */}
          <ProductReviews merchantId={product.merchantId} />

          {/* Similar Products */}
          <SimilarProducts currentProductId={product.id} category={product.category} merchantId={product.merchantId} />
        </motion.div>
      </div>

      {/* Sticky Bottom Actions */}
      <div className="fixed bottom-0 left-0 right-0 max-w-[480px] mx-auto bg-card border-t border-border p-4 shadow-lg z-20">
        <div className="flex items-center gap-4 mb-3">
          {/* Quantity Selector */}
          <div className="flex items-center border border-border rounded-xl h-10 px-2">
            <button 
              onClick={() => setQuantity(Math.max(1, quantity - 1))}
              className="w-8 h-full text-muted-foreground hover:text-primary transition"
              disabled={!canOrder}
            >
              <Minus className="h-4 w-4 mx-auto" />
            </button>
            <span className="w-10 text-center font-bold text-foreground">
              {quantity}
            </span>
            <button 
              onClick={() => setQuantity(Math.min(product.stock, quantity + 1))}
              className="w-8 h-full text-muted-foreground hover:text-primary transition"
              disabled={!canOrder}
            >
              <Plus className="h-4 w-4 mx-auto" />
            </button>
          </div>
          
          <div className="flex-1 text-right">
            <p className="text-xs text-muted-foreground">Total</p>
            {product.originalPrice ? (
              <div>
                <p className="text-xs line-through text-muted-foreground">
                  {formatPrice((product.originalPrice + selectedToppingTotal) * quantity)}
                </p>
                <p className="text-lg font-bold text-primary">
                  {formatPrice((product.price + selectedToppingTotal) * quantity)}
                </p>
              </div>
            ) : (
              <p className="text-lg font-bold text-primary">
                {formatPrice((product.price + selectedToppingTotal) * quantity)}
              </p>
            )}
          </div>
        </div>
        
        {canOrder ? (
          <div className="flex gap-2">
            <Button
              onClick={handleAddToCart}
              variant="outline"
              className="flex-1"
              size="lg"
            >
              <ShoppingCart className="h-4 w-4 mr-2" />
              Keranjang
            </Button>
            <Button
              onClick={handleBuyNow}
              className="flex-1 shadow-brand"
              size="lg"
            >
              Beli Langsung
            </Button>
          </div>
        ) : (
          <Button
            disabled
            className="w-full"
            size="lg"
          >
            <><AlertTriangle className="h-4 w-4 mr-2" />{unavailableReason || 'Tidak Dapat Memesan'}</>
          </Button>
        )}
      </div>
    </div>
  );
}
