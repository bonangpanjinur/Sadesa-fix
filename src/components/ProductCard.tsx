import { Link } from 'react-router-dom';
import { Plus, Star, Clock, CheckCircle2 } from 'lucide-react';
import { motion } from 'framer-motion';
import { toast } from 'sonner';
import type { Product } from '@/types';
import { useCart } from '@/contexts/CartContext';
import { formatPrice, cn } from '@/lib/utils';
import { WishlistButton } from '@/components/WishlistButton';
import { useProductFlashSale } from '@/hooks/useFlashSales';
import { FlashSaleBadge } from '@/components/FlashSaleTimer';
import { OptimizedImage } from '@/components/ui/OptimizedImage';
import { getProductUnavailableReason } from '@/lib/productAvailability';
import { Button } from '@/components/ui/button';

interface ProductWithSales extends Product {
  sold_count?: number;
}

interface ProductCardProps {
  product: ProductWithSales;
  index?: number;
  showCategoryBadge?: boolean;
}

const categoryLabels: Record<string, { label: string; className: string }> = {
  kuliner: { label: 'Kuliner', className: 'bg-warning/10 text-warning dark:bg-warning/20' },
  sembako: { label: 'Sembako', className: 'bg-warning/10 text-warning dark:bg-warning/20' },
  kriya: { label: 'Produk Desa', className: 'bg-info/10 text-info dark:bg-info/20' },
  wisata: { label: 'Wisata', className: 'bg-success/10 text-success dark:bg-success/20' },
  jasa: { label: 'Jasa', className: 'bg-primary/10 text-primary dark:bg-primary/20' },
  pertanian: { label: 'Pertanian', className: 'bg-success/10 text-success dark:bg-success/20' },
  peternakan: { label: 'Peternakan', className: 'bg-success/10 text-success dark:bg-success/20' },
};

const defaultCategoryStyle = { className: 'bg-muted text-muted-foreground' };

export function ProductCard({ product, index = 0, showCategoryBadge = false }: ProductCardProps) {
  const { addToCart } = useCart();
  const { flashSale } = useProductFlashSale(product.id);

  // Check availability - ensure we use the values from the product object
  // If the API says it's available, it's available. 
  // We only show the "Closed" overlay if isAvailable is explicitly false.
  const isAvailable = product.isAvailable === true;
  const isMerchantOpen = product.isMerchantOpen !== false;
  const hasQuota = product.hasQuota !== false;

  const handleAddToCart = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (!isAvailable) return;
    addToCart(product, 1);
    toast.success(`${product.name} ditambahkan ke keranjang`);
  };

  const categoryInfo = categoryLabels[product.category] || { label: product.category, className: 'bg-muted text-muted-foreground' };

  const displayPrice = flashSale ? flashSale.flashPrice : product.price;
  const originalPrice = flashSale ? flashSale.originalPrice : product.originalPrice || null;

  // Get unavailability reason
  const unavailableReason = product.unavailableReason || getProductUnavailableReason({
    isActive: product.isActive,
    stock: product.stock,
    hasQuota,
    isMerchantOpen,
  }) || 'Tidak Tersedia';

  const CardContent = (
    <div
      className={cn(
        "group relative overflow-hidden rounded-lg border border-border/70 bg-card shadow-sm",
        "cursor-pointer transition duration-300 hover:-translate-y-0.5 hover:shadow-md"
      )}
    >
      {/* Unavailable Overlay */}
      {!isAvailable && (
        <div className="absolute inset-0 z-20 bg-background/70 backdrop-blur-[1px] flex items-center justify-center">
          <div className="bg-muted/90 px-3 py-2 rounded-lg flex items-center gap-2 shadow-lg border border-border">
            <Clock className="h-4 w-4 text-muted-foreground" />
            <span className="text-xs font-semibold text-muted-foreground">
              {unavailableReason}
            </span>
          </div>
        </div>
      )}

      {/* Badges Container */}
      <div className="absolute top-2 left-2 z-10 flex flex-col gap-1">
        {flashSale && isAvailable ? (
          <FlashSaleBadge 
            endTime={flashSale.endTime} 
            discountPercent={flashSale.discountPercent} 
          />
        ) : product.isPromo && isAvailable ? (
          <span className="bg-destructive text-destructive-foreground text-[8px] font-bold px-1.5 py-0.5 rounded">
            PROMO
          </span>
        ) : null}
        {showCategoryBadge && (
          <span className={cn("text-[8px] font-medium px-1.5 py-0.5 rounded", categoryInfo.className)}>
            {categoryInfo.label}
          </span>
        )}
        {product.halal_status === 'VERIFIED' && (
          <span className="bg-green-500 text-white text-[8px] font-bold px-1.5 py-0.5 rounded flex items-center gap-0.5">
            <CheckCircle2 className="h-2 w-2" />
            HALAL
          </span>
        )}
      </div>
      
      {/* Wishlist Button */}
      {isAvailable && (
        <div className="absolute top-2 right-2 z-10">
          <WishlistButton productId={product.id} size="sm" />
        </div>
      )}
      
      <div className={cn(
        "relative aspect-[4/3] overflow-hidden bg-muted",
        !isAvailable && "grayscale"
      )}>
        <OptimizedImage 
          src={product.image} 
          alt={product.name}
          className={cn(
            "w-full h-full transition duration-300",
            isAvailable && "group-hover:scale-105"
          )}
          aspectRatio="auto"
          lazy
        />
      </div>
      
      <div className={cn("p-3", !isAvailable && "opacity-60")}>
        <div
          className="text-[9px] text-muted-foreground mb-0.5 truncate flex items-center gap-1"
        >
          {product.merchantName}
        </div>
        <h3 className="min-h-[2.5em] font-heading text-xs font-semibold leading-snug text-card-foreground line-clamp-2">
          {product.name}
        </h3>
        <div className="flex justify-between items-center mt-1.5">
            <div className="flex flex-col">
              {originalPrice && isAvailable && (
                <span className="text-[9px] text-muted-foreground line-through">
                  {formatPrice(originalPrice)}
                </span>
              )}
              <p className={cn(
                "font-bold text-xs",
                flashSale && isAvailable ? "text-destructive" : "text-primary"
              )}>
                {formatPrice(displayPrice)}
              </p>
              {product.sold_count > 0 && (
                <span className="text-[9px] text-muted-foreground">
                  {product.sold_count >= 100 ? '100+ terjual' : `${product.sold_count} terjual`}
                </span>
              )}
            </div>
          {isAvailable && (
            <Button
              type="button"
              variant="default"
              size="icon"
              onClick={handleAddToCart}
              className="h-7 w-7 rounded-lg shadow-sm"
              aria-label={`Tambahkan ${product.name} ke keranjang`}
            >
              <Plus className="h-3 w-3" />
            </Button>
          )}
        </div>
      </div>
    </div>
  );

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, delay: index * 0.05 }}
    >
      <Link to={`/product/${product.id}`} className="block">
        {CardContent}
      </Link>
    </motion.div>
  );
}
