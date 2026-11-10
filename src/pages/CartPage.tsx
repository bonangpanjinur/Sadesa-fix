import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { safeGoBack } from '@/lib/utils';
import { motion } from 'framer-motion';
import { ArrowLeft, Minus, Plus, Trash2, ShoppingBag, Store, AlertTriangle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { useCart } from '@/contexts/CartContext';
import { useAuth } from '@/contexts/AuthContext';
import { formatPrice } from '@/lib/utils';
import { useTranslation, useFormatters } from '@/lib/i18n';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { useGuestCheckoutEnabled } from '@/hooks/useGuestCheckoutEnabled';
import { getMerchantOperatingStatus, type OperatingDaySchedule } from '@/lib/merchantOperatingHours';
import { getCartStockDemand } from '@/lib/productAvailability';
import { getMerchantSelectionPlan } from '@/lib/cartSelection';
import { getCartItemKey } from '@/lib/cartItemIdentity';

interface StockProductRow {
  id: string;
  stock: number;
  is_active: boolean;
  price: number;
  name: string;
}

export default function CartPage() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { items, selectedItems, selectedItemIds, toggleItemSelection, selectItemKeys, updateQuantity, syncProductStock, removeCartItem, clearCart } = useCart();
  const { enabled: guestCheckoutEnabled, loading: guestCheckoutFlagLoading } = useGuestCheckoutEnabled(Boolean(user));
  const { t } = useTranslation();
  const { formatCurrency } = useFormatters();
  const [showClearConfirm, setShowClearConfirm] = useState(false);
  const [merchantStatuses, setMerchantStatuses] = useState<Record<string, boolean>>({});
  const [stockWarnings, setStockWarnings] = useState<Record<string, string>>({});
  const itemUnitTotal = (item: typeof items[number]) => item.product.price + (item.toppings || []).reduce((sum, topping) => sum + topping.product.price * topping.quantity, 0);
  const selectedTotal = selectedItems.reduce((sum, item) => sum + itemUnitTotal(item) * item.quantity, 0);

  // Fetch merchant open/close statuses
  useEffect(() => {
    const merchantIds = [...new Set(items.map(i => i.product.merchantId).filter(Boolean))];
    
    if (merchantIds.length === 0) return;

    const fetchStatuses = async () => {
      const [{ data: merchants, error: merchantsError }, { data: weeklyHours, error: weeklyHoursError }] = await Promise.all([
        supabase
          .from('merchants')
          .select('id, is_open, open_time, close_time')
          .in('id', merchantIds),
        supabase
          .from('merchant_operating_hours')
          .select('merchant_id, day_of_week, open_time, close_time, is_closed')
          .in('merchant_id', merchantIds),
      ]);

      if (merchantsError || weeklyHoursError) {
        console.error('Unable to refresh cart merchant operating status:', merchantsError || weeklyHoursError);
        return;
      }

      const weeklyHoursByMerchant = new Map<string, OperatingDaySchedule[]>();
      for (const row of weeklyHours || []) {
        const schedule = weeklyHoursByMerchant.get(row.merchant_id) || [];
        schedule.push({
          day_of_week: row.day_of_week,
          open_time: row.open_time,
          close_time: row.close_time,
          is_closed: row.is_closed,
        });
        weeklyHoursByMerchant.set(row.merchant_id, schedule);
      }

      const statuses: Record<string, boolean> = {};
      (merchants || []).forEach((merchant) => {
        statuses[merchant.id] = getMerchantOperatingStatus(
          merchant.is_open,
          merchant.open_time,
          merchant.close_time,
          weeklyHoursByMerchant.get(merchant.id),
        ).isCurrentlyOpen;
      });
      setMerchantStatuses(statuses);
    };

    void fetchStatuses();
  }, [items]);

  // Validate stock in real-time
  useEffect(() => {
    const productIds = items.flatMap(i => [i.product.id, ...(i.toppings || []).map(t => t.product.id)]).filter(Boolean);
    if (productIds.length === 0) return;

    const validateStock = async () => {
      const { data: products } = await supabase
        .from('products')
        .select('id, stock, is_active, price, name')
        .in('id', productIds);

      if (products) {
        syncProductStock(Object.fromEntries(products.map((product) => [product.id, Number(product.stock) || 0])));
        const warnings: Record<string, string> = {};
        const demand = getCartStockDemand(items);
        products.forEach((p: StockProductRow) => {
          const requestedQuantity = demand.get(p.id) || 0;
          const cartItems = items.filter(i => i.product.id === p.id);
          const toppingUses = items.flatMap(i => (i.toppings || []).filter(t => t.product.id === p.id).map(t => t.product));
          const baseItem = cartItems[0];
          if (toppingUses.length > 0 && (p.stock < requestedQuantity || toppingUses.some(t => p.price !== t.price))) {
            warnings[p.id] = p.stock < requestedQuantity ? `Stok ${p.name} hanya ${p.stock} (diminta ${requestedQuantity})` : `Harga topping berubah menjadi Rp ${p.price.toLocaleString('id-ID')}`;
          }
          if (!baseItem) return;
          if (!p.is_active) {
            warnings[p.id] = 'Produk sudah tidak tersedia';
          } else if (p.stock <= 0) {
            warnings[p.id] = 'Stok habis';
          } else if (requestedQuantity > p.stock) {
            warnings[p.id] = `Sisa stok hanya ${p.stock} (diminta ${requestedQuantity})`;
          } else if (p.price !== baseItem.product.price) {
            warnings[p.id] = `Harga berubah menjadi Rp ${p.price.toLocaleString('id-ID')}`;
          }
        });
        setStockWarnings(warnings);
      }
    };

    validateStock();
  }, [items, syncProductStock]);

  const handleCheckout = () => {
    if (selectedItems.length === 0) {
      toast({ title: 'Pilih produk terlebih dahulu', description: 'Centang minimal satu produk untuk checkout.', variant: 'destructive' });
      return;
    }
    const selectedMerchantIds = new Set(selectedItems.map(item => item.product.merchantId || `unknown:${item.product.merchantName || 'Toko'}`));
    if (selectedMerchantIds.size > 1) {
      toast({ title: 'Pilih satu toko untuk checkout', description: 'Gunakan tombol Checkout Toko Ini pada toko yang ingin dipesan.', variant: 'destructive' });
      return;
    }
    const selectedProductIds = new Set(selectedItems.flatMap(item => [item.product.id, ...(item.toppings || []).map(topping => topping.product.id)]));
    if ([...selectedProductIds].some(productId => stockWarnings[productId])) {
      toast({
        title: 'Periksa isi keranjang',
        description: 'Hapus atau sesuaikan produk yang stoknya berubah sebelum checkout.',
        variant: 'destructive',
      });
      return;
    }
    if (!user && !guestCheckoutEnabled) {
      navigate('/auth');
      return;
    }
    navigate('/checkout');
  };

  const handleCheckoutForMerchant = (merchantItems: typeof items) => {
    if (!merchantItems.length) return;
    const merchantIds = new Set(merchantItems.flatMap(item => [item.product.id, ...(item.toppings || []).map(topping => topping.product.id)]));
    if ([...merchantIds].some(productId => stockWarnings[productId])) {
      toast({ title: 'Periksa isi toko', description: 'Sesuaikan atau hapus produk yang stoknya berubah sebelum checkout.', variant: 'destructive' });
      return;
    }
    if (merchantItems[0]?.product.merchantId && merchantStatuses[merchantItems[0].product.merchantId] === false) {
      toast({ title: 'Toko sedang tutup', description: 'Pesanan dari toko ini belum dapat dibuat.', variant: 'destructive' });
      return;
    }
    if (!user && !guestCheckoutEnabled) {
      navigate('/auth');
      return;
    }
    selectItemKeys(merchantItems.map(getCartItemKey));
    navigate('/checkout');
  };

  if (items.length === 0) {
    return (
      <div className="mobile-shell flex min-h-[100dvh] flex-col bg-card">
        {/* Header */}
        <div className="p-4 border-b border-border flex items-center gap-3">
          <button 
            onClick={() => safeGoBack(navigate)}
            className="w-8 h-8 rounded-full hover:bg-secondary flex items-center justify-center"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>
          <h2 className="font-bold text-lg text-foreground">Keranjang Belanja</h2>
        </div>
        
        <div className="flex-1 flex flex-col items-center justify-center p-8">
          <div className="w-24 h-24 bg-secondary rounded-full flex items-center justify-center mb-4">
            <ShoppingBag className="h-12 w-12 text-muted-foreground" />
          </div>
          <p className="text-muted-foreground mb-4 text-center">
            Keranjang belanja Anda masih kosong
          </p>
          <Button onClick={() => navigate('/')}>
            Mulai Belanja
          </Button>
        </div>
      </div>
    );
  }

  // Group by stable merchant ID so same-named merchants never share a checkout group.
  const grouped: Record<string, typeof items> = {};
  items.forEach(item => {
    const key = item.product.merchantId || `unknown:${item.product.merchantName || 'Toko'}`;
    if (!grouped[key]) grouped[key] = [];
    grouped[key].push(item);
  });

  return (
    <div className="mobile-shell flex min-h-[100dvh] flex-col bg-secondary">
      {/* Header */}
      <div className="p-4 border-b border-border bg-card flex items-center justify-between">
        <div className="flex items-center gap-3">
          <button 
            onClick={() => safeGoBack(navigate)}
            className="w-8 h-8 rounded-full hover:bg-secondary flex items-center justify-center"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>
          <h2 className="font-bold text-lg text-foreground">Keranjang Belanja</h2>
        </div>
        <button
          onClick={() => setShowClearConfirm(true)}
          className="text-xs text-destructive font-medium hover:underline"
        >
          Hapus Semua
        </button>
      </div>
      
      {/* Cart Items - Grouped by Merchant */}
      <div className="flex-1 overflow-y-auto p-4 pb-48">
        {Object.entries(grouped).map(([merchantKey, merchantItems]) => {
          const merchantName = merchantItems[0]?.product.merchantName || 'Toko';
          const merchantId = merchantItems[0]?.product.merchantId;
          const isOpen = merchantId ? merchantStatuses[merchantId] : undefined;
          const isClosed = isOpen === false;
          const selectionPlan = getMerchantSelectionPlan(
            merchantItems.map(getCartItemKey),
            selectedItemIds,
          );

          return (
            <div key={merchantKey} className="mb-4">
              {/* Merchant Header */}
              <div className="flex items-center gap-2 mb-2 px-1">
                <Store className="h-4 w-4 text-primary" />
                <span className="font-semibold text-sm text-foreground">{merchantName}</span>
                <span className="text-[10px] text-muted-foreground">({merchantItems.length} item)</span>
                {isOpen !== undefined && (
                  <span className={`inline-flex items-center gap-1 text-[10px] font-medium px-1.5 py-0.5 rounded-full ${isOpen ? 'bg-green-500/10 text-green-600' : 'bg-destructive/10 text-destructive'}`}>
                    <span className={`w-1.5 h-1.5 rounded-full ${isOpen ? 'bg-green-500' : 'bg-destructive'}`} />
                    {isOpen ? 'Buka' : 'Tutup'}
                  </span>
                )}
                <button
                  type="button"
                  onClick={() => selectionPlan.productIdsToToggle.forEach(toggleItemSelection)}
                  aria-label={`${selectionPlan.allSelected ? 'Batal pilih' : 'Pilih semua'} produk dari ${merchantName}`}
                  className="ml-auto text-xs font-medium text-primary hover:underline"
                >
                  {selectionPlan.allSelected ? 'Batal pilih' : 'Pilih semua'}
                </button>
                <Button
                  type="button"
                  size="sm"
                  variant="outline"
                  className="shrink-0 text-xs"
                  onClick={() => handleCheckoutForMerchant(merchantItems)}
                  disabled={guestCheckoutFlagLoading || isClosed || merchantItems.some(item => stockWarnings[item.product.id] || (item.toppings || []).some(topping => stockWarnings[topping.product.id]))}
                >
                  Checkout Toko Ini
                </Button>
              </div>

              {/* Closed warning */}
              {isClosed && (
                <div className="flex items-center gap-2 mb-2 p-2.5 rounded-lg bg-destructive/10 border border-destructive/20 text-destructive text-xs">
                  <AlertTriangle className="h-3.5 w-3.5 flex-shrink-0" />
                  <span>Toko sedang tutup. Produk ini tidak bisa di-checkout saat ini.</span>
                </div>
              )}

              <div className="space-y-3">
                {merchantItems.map((item, index) => (
                  <motion.div
                    key={`${item.product.id}-${(item.toppings || []).map(topping => `${topping.product.id}:${topping.quantity}`).sort().join('|') || 'base'}-${index}`}
                    initial={{ opacity: 0, x: -20 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ delay: index * 0.05 }}
                    className={`bg-card rounded-xl p-3 border border-border shadow-sm ${isClosed ? 'opacity-60' : ''}`}
                  >
                    <div className="flex gap-3">
                      <input
                        type="checkbox"
                        aria-label={`Pilih ${item.product.name}`}
                        checked={selectedItemIds.includes(getCartItemKey(item))}
                        onChange={() => toggleItemSelection(getCartItemKey(item))}
                        className="mt-1 h-5 w-5 accent-primary flex-shrink-0"
                      />
                      <img 
                        src={item.product.image}
                        alt={item.product.name}
                        className="w-20 h-20 rounded-lg object-cover"
                      />
                      <div className="flex-1 min-w-0">
                        <h3 className="font-bold text-sm text-foreground line-clamp-2">
                          {item.product.name}
                        </h3>
                        <p className="text-primary font-bold text-sm mt-1">
                          {formatPrice(itemUnitTotal(item))}
                        </p>
                        {item.toppings?.length ? <p className="text-xs text-muted-foreground mt-1">Topping: {item.toppings.map((topping) => `${topping.product.name} (+${formatPrice(topping.product.price)})`).join(', ')}</p> : null}
                        {item.product.originalPrice && (
                          <p className="text-xs line-through text-muted-foreground">
                            {formatPrice(item.product.originalPrice)}
                          </p>
                        )}
                        {stockWarnings[item.product.id] && (
                          <p className="text-xs text-destructive flex items-center gap-1 mt-0.5">
                            <AlertTriangle className="h-3 w-3" />
                            {stockWarnings[item.product.id]}
                          </p>
                        )}
                      </div>
                    </div>
                    
                    <div className="flex justify-between items-center mt-3 pt-3 border-t border-border">
                      <button
                        onClick={() => removeCartItem(getCartItemKey(item))}
                        aria-label={`Hapus ${item.product.name} dari keranjang`}
                        className="text-destructive hover:bg-destructive/10 p-2 rounded-lg transition"
                      >
                        <Trash2 className="h-4 w-4" />
                      </button>
                      
                      <div className="flex items-center border border-border rounded-lg">
                        <button 
                          onClick={() => updateQuantity(item.product.id, item.quantity - 1, item.toppings)}
                          aria-label={`Kurangi ${item.product.name}`}
                          className="w-8 h-8 text-muted-foreground hover:text-primary transition"
                        >
                          <Minus className="h-4 w-4 mx-auto" />
                        </button>
                        <span className="w-8 text-center font-bold text-sm">
                          {item.quantity}
                        </span>
                        <button 
                          onClick={() => updateQuantity(item.product.id, Math.min(item.product.stock, item.quantity + 1), item.toppings)}
                          aria-label={`Tambah ${item.product.name}`}
                          className="w-8 h-8 text-muted-foreground hover:text-primary transition"
                          disabled={item.quantity >= item.product.stock}
                        >
                          <Plus className="h-4 w-4 mx-auto" />
                        </button>
                      </div>
                    </div>
                  </motion.div>
                ))}
              </div>
            </div>
          );
        })}
      </div>

      {/* Checkout Summary */}
      <div className="mobile-action-safe fixed bottom-0 left-0 right-0 mx-auto max-w-[480px] border-t border-border bg-card p-5 shadow-lg">
        {selectedItems.some(item => stockWarnings[item.product.id] || (item.toppings || []).some(topping => stockWarnings[topping.product.id])) && (
          <div className="mb-3 flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-xs text-destructive" role="alert">
            <AlertTriangle className="mt-0.5 h-4 w-4 flex-shrink-0" />
            <span>Checkout diblokir. Hapus atau sesuaikan produk yang stoknya habis atau berubah.</span>
          </div>
        )}
        <div className="flex justify-between items-center mb-1 text-sm">
          <span className="text-muted-foreground">{t('shipping.feeLong')}</span>
          <span className="text-xs text-muted-foreground italic">{t('shipping.calculatedAtCheckout')}</span>
        </div>
        <div className="flex justify-between items-center mb-4 pt-3 border-t border-border">
          <span className="text-lg font-bold">{t('shipping.total')}</span>
          <span className="text-xl font-bold text-primary">{formatCurrency(selectedTotal)}</span>
        </div>
        <p className="text-xs text-muted-foreground mb-3">{selectedItems.length} produk dipilih dari {items.length}</p>
        <Button
          onClick={handleCheckout}
          className="w-full shadow-brand font-bold"
          size="lg"
          disabled={guestCheckoutFlagLoading || selectedItems.some(item => stockWarnings[item.product.id] || (item.toppings || []).some(topping => stockWarnings[topping.product.id]))}
        >
          {selectedItems.some(item => stockWarnings[item.product.id] || (item.toppings || []).some(topping => stockWarnings[topping.product.id]))
            ? 'Periksa Stok Produk'
            : guestCheckoutFlagLoading
            ? 'Memeriksa Checkout...'
            : user
            ? 'Lanjut ke Checkout'
            : guestCheckoutEnabled
            ? 'Checkout tanpa Login'
            : 'Masuk untuk Checkout'}
        </Button>
      </div>

      {/* Clear Cart Confirmation */}
      <AlertDialog open={showClearConfirm} onOpenChange={setShowClearConfirm}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Hapus Semua Item?</AlertDialogTitle>
            <AlertDialogDescription>
              Semua produk di keranjang akan dihapus. Tindakan ini tidak dapat dibatalkan.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Batal</AlertDialogCancel>
            <AlertDialogAction onClick={clearCart} className="bg-destructive text-destructive-foreground hover:bg-destructive/90">
              Hapus Semua
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
