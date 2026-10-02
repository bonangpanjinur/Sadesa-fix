import { lazy, Suspense, useState, useEffect, useRef, useCallback } from 'react';
import DOMPurify from 'dompurify';
import { usePOS } from '@/contexts/POSContext';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { getPrinterSettings } from '@/lib/thermalPrinter';
import { createPrintJobId } from '@/lib/receiptDomain';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { toast } from 'sonner';
import { useNavigate } from 'react-router-dom';
import { Search, Package, ChevronLeft, Barcode, CheckCircle2, Star, Ticket, Percent, Printer, Gift, MessageCircle, FileDown, QrCode } from 'lucide-react';
import { Badge } from '@/components/ui/badge';

import { POSLayout } from '@/components/pos/POSLayout';

import { cn } from '@/lib/utils';
import { processAtomicPOSSale } from '@/lib/posCheckout';
import { calculatePOSPricing } from '@/lib/posPricing';
import { getEffectivePaymentAmount, validatePOSPayment } from '@/lib/posPaymentValidation';
import { usePOSOfflineSync } from '@/hooks/usePOSOfflineSync';
import { usePOSCart } from '@/hooks/usePOSCart';
import { usePOSPayment } from '@/hooks/usePOSPayment';
import { usePOSHeldBills } from '@/hooks/usePOSHeldBills';
import { usePOSReceipt } from '@/hooks/usePOSReceipt';
import { clearCheckoutCheckpoint, markSaleSynced, saveCheckoutTransaction, type PendingSale } from '@/lib/posOfflineDB';
import type {
  CartItem, HeldBill, Customer, LastSale, ReceiptStore, LoyaltyProgram,
  Promotion, Voucher, Product, Variant,
} from '@/components/pos/kasir/types';

const POSCart = lazy(() => import('@/components/pos/kasir/POSCart').then(({ POSCart: Component }) => ({ default: Component })));
const BarcodeScanner = lazy(() => import('@/components/pos/BarcodeScanner').then(({ BarcodeScanner: Component }) => ({ default: Component })));
const POSPaymentDialog = lazy(() => import('@/components/pos/kasir/POSPaymentDialog').then(({ POSPaymentDialog: Component }) => ({ default: Component })));
const POSHeldBills = lazy(() => import('@/components/pos/kasir/POSHeldBills').then(({ POSHeldBills: Component }) => ({ default: Component })));

export default function POSKasirPage() {
  const { tenant, activeOutlet, formatCurrency } = usePOS();
  const { user } = useAuth();
  const navigate = useNavigate();
  const {
    isOnline, isSyncing, pendingCount, queueSummary, triggerSync, saveOfflineSale, refreshProductCache,
    cachedProducts, cacheAgeMs, isCacheStale,
  } = usePOSOfflineSync({ tenantId: tenant?.id ?? null, outletId: activeOutlet?.id ?? null });

  // UI
  const [products, setProducts] = useState<Product[]>([]);
  const [categories, setCategories] = useState<{ id: string; name: string }[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [filterCat, setFilterCat] = useState('all');
  const [scannerOpen, setScannerOpen] = useState(false);
  const searchRef = useRef<HTMLInputElement>(null);

  // Cart
  const {
    cart,
    setCart,
    addItem: addCartItem,
    updateQty,
    removeItem,
    updateDiscount: updateItemDiscount,
  } = usePOSCart();
  const [discount, setDiscount] = useState(0);
  const [notes, setNotes] = useState('');

  // Customer
  const [selectedCustomer, setSelectedCustomer] = useState<Customer | null>(null);
  const [customerName, setCustomerName] = useState('');
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [customerDialog, setCustomerDialog] = useState(false);
  const [customerSearch, setCustomerSearch] = useState('');

  // Loyalty
  const [loyaltyProgram, setLoyaltyProgram] = useState<LoyaltyProgram | null>(null);
  const [customerPoints, setCustomerPoints] = useState(0);
  const [customerTier, setCustomerTier] = useState('Bronze');
  const [usePoints, setUsePoints] = useState(false);
  const [pointsToRedeem, setPointsToRedeem] = useState(0);

  // Promo & Voucher
  const [activePromos, setActivePromos] = useState<Promotion[]>([]);
  const [appliedPromo, setAppliedPromo] = useState<Promotion | null>(null);
  const [promoDiscount, setPromoDiscount] = useState(0);
  const [voucherCode, setVoucherCode] = useState('');
  const [appliedVoucher, setAppliedVoucher] = useState<Voucher | null>(null);
  const [voucherDiscount, setVoucherDiscount] = useState(0);
  const [voucherError, setVoucherError] = useState('');

  const paymentRequestKeyRef = useRef<string | null>(null);
  const [lastSale, setLastSale] = useState<LastSale | null>(null);
  const [lastSaleWasOffline, setLastSaleWasOffline] = useState(false);

  // Printer
  const {
    thermalConnected,
    thermalConnecting,
    connectThermalPrinter,
    printReceipt,
  } = usePOSReceipt({
    tenant: tenant as unknown as ReceiptStore | null,
    outletReady: Boolean(activeOutlet),
    lastSale,
    userEmail: user?.email,
  });

  // Hold Bill
  const [heldBillsDialog, setHeldBillsDialog] = useState(false);
  const {
    heldBills,
    fetchHeldBills,
    holdBill: persistHeldBill,
    resumeBill: deleteHeldBill,
  } = usePOSHeldBills({
    tenantId: tenant?.id ?? null,
    outletId: activeOutlet?.id ?? null,
    cashierId: user?.id ?? null,
  });

  // Variant
  const [variantDialog, setVariantDialog] = useState(false);
  const [selectedProduct, setSelectedProduct] = useState<Product | null>(null);
  const [variants, setVariants] = useState<Variant[]>([]);

  // ── Kalkulasi ────────────────────────────────────────────
  const pricing = calculatePOSPricing({
    cart,
    orderDiscount: discount,
    promo: appliedPromo,
    voucher: appliedVoucher,
    usePoints: usePoints && Boolean(selectedCustomer),
    pointsToRedeem,
    customerPoints: selectedCustomer ? customerPoints : 0,
    loyaltyProgram,
    paymentAmount: 0,
    paymentMethod: 'cash',
  });
  const {
    subtotal, taxAmount, promoDiscount: calculatedPromoDiscount,
    voucherDiscount: calculatedVoucherDiscount, pointsDiscount,
    total, pointsEarned,
  } = pricing;

  // Payment state is initialized from the current total; change is derived after the hook is available.
  const {
    paymentMethod,
    paymentAmount, setPaymentAmount,
    isSplitPayment,
    splitMethod2,
    splitAmount1,
    splitAmount2,
    paymentDialog, setPaymentDialog,
    successDialog, setSuccessDialog,
    openPayment: openPaymentState, resetPayment,
    handlePaymentChange,
  } = usePOSPayment(total, cart.length);
  const change = paymentMethod === 'cash'
    ? Math.max(0, (Number(paymentAmount) || 0) - total)
    : 0;

  const fetchProducts = useCallback(async () => {
    if (!tenant || !activeOutlet) return;
    const { data, error } = await supabase.from('pos_products' as never)
      .select('*, pos_categories(name), pos_stock(quantity, outlet_id), pos_product_variants(id, product_id, name, sku, barcode, price, cost_price, is_active, pos_stock(quantity, outlet_id))')
      .eq('tenant_id', tenant.id).eq('is_active', true).order('name');
    if (!error && data) {
      const outletProducts = (data as unknown as Product[]).map((product) => ({
        ...product,
        pos_stock: (product.pos_stock || []).filter((stock) => !stock.outlet_id || stock.outlet_id === activeOutlet.id),
        variants: (product as Product & { pos_product_variants?: Variant[] }).pos_product_variants
          ?.filter((variant) => variant.is_active)
          .map((variant) => ({
            ...variant,
            stock_qty: (variant as Variant & { pos_stock?: { quantity: number; outlet_id?: string }[] }).pos_stock
              ?.filter((stock) => !stock.outlet_id || stock.outlet_id === activeOutlet.id)
              .reduce((total, stock) => total + stock.quantity, 0),
          })),
      }));
      setProducts(outletProducts);
    } else if (cachedProducts.length > 0) {
      setProducts(cachedProducts.map((product) => ({
        ...product,
        category_id: null,
        pos_categories: product.category_name ? { name: product.category_name } : null,
        pos_stock: product.stock_qty === undefined ? [] : [{ quantity: product.stock_qty }],
        has_variants: product.has_variants ?? Boolean(product.variants?.length),
        variants: product.variants,
        barcode: product.barcode,
      })) as Product[]);
    }
    setLoading(false);
  }, [tenant, activeOutlet, cachedProducts]);

  const fetchCategories = useCallback(async () => {
    if (!tenant) return;
    const { data } = await supabase.from('pos_categories' as never).select('id, name')
      .eq('tenant_id', tenant.id).order('name');
    setCategories((data || []) as unknown as { id: string; name: string }[]);
  }, [tenant]);


  const fetchLoyaltyProgram = useCallback(async () => {
    if (!tenant) return;
    const { data } = await supabase.from('pos_loyalty_programs' as never).select('*')
      .eq('tenant_id', tenant.id).eq('is_active', true).maybeSingle();
    setLoyaltyProgram(data as unknown as LoyaltyProgram | null);
  }, [tenant]);

  const fetchActivePromos = useCallback(async () => {
    if (!tenant) return;
    const now = new Date().toISOString();
    const { data } = await supabase.from('pos_promotions' as never).select('*')
      .eq('tenant_id', tenant.id).eq('is_active', true)
      .or(`start_date.is.null,start_date.lte.${now}`)
      .or(`end_date.is.null,end_date.gte.${now}`);
    setActivePromos((data || []) as unknown as Promotion[]);
  }, [tenant]);

  const fetchCustomerPoints = useCallback(async (customerId: string) => {
    if (!tenant) return;
    const { data } = await supabase.from('pos_customers' as never)
      .select('loyalty_points, loyalty_tier').eq('id', customerId).eq('tenant_id', tenant.id).maybeSingle();
    if (data) { setCustomerPoints((data as unknown as { loyalty_points?: number }).loyalty_points || 0); setCustomerTier((data as unknown as { loyalty_tier?: string }).loyalty_tier || 'Bronze'); }
  }, [tenant]);

  // ── Promosi ──────────────────────────────────────────────
  const calcPromoDiscount = useCallback((promo: Promotion): number => {
    if (subtotal < promo.min_purchase) return 0;
    const now = new Date();
    if (promo.type === 'happy_hour') {
      if (!promo.happy_hour_start || !promo.happy_hour_end) return 0;
      const day = now.getDay();
      if (!(promo.happy_hour_days || []).includes(day)) return 0;
      const [sh, sm] = promo.happy_hour_start.split(':').map(Number);
      const [eh, em] = promo.happy_hour_end.split(':').map(Number);
      const nowMin = now.getHours() * 60 + now.getMinutes();
      if (nowMin < sh * 60 + sm || nowMin > eh * 60 + em) return 0;
      const disc = subtotal * promo.discount_percent / 100;
      return promo.max_discount ? Math.min(disc, promo.max_discount) : disc;
    }
    if (promo.type === 'discount_percent') {
      const disc = subtotal * promo.discount_percent / 100;
      return promo.max_discount ? Math.min(disc, promo.max_discount) : disc;
    }
    if (promo.type === 'discount_amount') return Math.min(promo.discount_amount, subtotal);
    if (promo.type === 'bundle' && promo.bundle_price !== null) return Math.max(0, subtotal - promo.bundle_price);
    return 0;
  }, [subtotal]);

  const autoApplyBestPromo = useCallback(() => {
    if (activePromos.length === 0 || subtotal === 0) { setPromoDiscount(0); setAppliedPromo(null); return; }
    let best: Promotion | null = null; let bestDisc = 0;
    for (const p of activePromos) { const d = calcPromoDiscount(p); if (d > bestDisc) { bestDisc = d; best = p; } }
    setAppliedPromo(best); setPromoDiscount(bestDisc);
  }, [activePromos, subtotal, calcPromoDiscount]);

  // ── Voucher ──────────────────────────────────────────────
  const applyVoucher = async () => {
    const code = voucherCode.trim().toUpperCase();
    if (!code || !tenant) return;
    setVoucherError('');
    const { data } = await supabase.from('pos_vouchers' as never).select('*')
      .eq('tenant_id', tenant.id).eq('code', code).eq('is_active', true).maybeSingle();
    if (!data) { setVoucherError('Kode voucher tidak valid atau tidak aktif'); return; }
    const v = data as unknown as Voucher;
    const now = new Date();
    if (v.start_date && now < new Date(v.start_date)) { setVoucherError('Voucher belum berlaku'); return; }
    if (v.end_date && now > new Date(v.end_date)) { setVoucherError('Voucher sudah kedaluwarsa'); return; }
    if (v.usage_limit && v.used_count >= v.usage_limit) { setVoucherError('Voucher sudah habis'); return; }
    if (subtotal < v.min_purchase) { setVoucherError(`Min. pembelian ${formatCurrency(v.min_purchase)}`); return; }
    const disc = v.type === 'discount_percent'
      ? Math.min(subtotal * v.discount_percent / 100, v.max_discount || Infinity)
      : Math.min(v.discount_amount, subtotal);
    setAppliedVoucher(v); setVoucherDiscount(disc);
    toast.success(`Voucher "${v.name}" berhasil diterapkan! Diskon ${formatCurrency(disc)}`);
  };

  const removeVoucher = () => { setAppliedVoucher(null); setVoucherDiscount(0); setVoucherCode(''); setVoucherError(''); };

  // ── Cart actions ─────────────────────────────────────────
  const addToCart = useCallback(async (product: Product, variantId?: string, variantName?: string, variantPrice?: number) => {
    if (product.has_variants && !variantId) {
      if (product.variants?.length) {
        setVariants(product.variants);
      } else {
        const { data } = await supabase.from('pos_product_variants' as never).select('*, pos_stock(quantity, outlet_id)').eq('product_id', product.id).eq('is_active', true);
        setVariants((data || []) as unknown as Variant[]);
      }
      setSelectedProduct(product); setVariantDialog(true); return;
    }
    const price = variantPrice ?? product.price;
    addCartItem({
      productId: product.id,
      variantId,
      name: product.name,
      variantName,
      price,
      costPrice: product.cost_price,
      unit: product.unit,
      qty: 1,
      discount: 0,
      taxRate: product.tax_rate,
      notes: '',
    });
    setSearch('');
  }, [addCartItem]);
  const clearCart = useCallback(() => {
    setCart([]); setDiscount(0); setAppliedPromo(null); setPromoDiscount(0);
    setAppliedVoucher(null); setVoucherDiscount(0); setVoucherCode(''); setUsePoints(false); setPointsToRedeem(0);
  }, [setCart]);

  // ── Loyalty ──────────────────────────────────────────────
  const handleTogglePoints = (checked: boolean) => {
    setUsePoints(checked);
    if (checked && loyaltyProgram) {
      const maxPtsUsable = Math.min(customerPoints, loyaltyProgram.min_redeem_points <= customerPoints ? customerPoints : 0);
      setPointsToRedeem(maxPtsUsable);
    } else setPointsToRedeem(0);
  };
  const handlePointsInput = (val: string) => {
    if (!loyaltyProgram) return;
    let pts = parseInt(val) || 0;
    pts = Math.max(loyaltyProgram.min_redeem_points, Math.min(pts, customerPoints));
    setPointsToRedeem(pts);
  };

  // ── Customer search ──────────────────────────────────────
  const searchCustomers = async (q: string) => {
    if (!tenant || !q) { setCustomers([]); return; }
    const { data } = await supabase.from('pos_customers' as never)
      .select('id, name, phone, is_member, loyalty_points, loyalty_tier')
      .eq('tenant_id', tenant.id).ilike('name', `%${q}%`).limit(6);
    setCustomers((data || []) as unknown as Customer[]);
  };

  // ── Payment ──────────────────────────────────────────────
  const openPayment = useCallback(() => {
    if (!openPaymentState()) toast.error('Keranjang kosong');
  }, [openPaymentState]);

  const processPayment = async (paymentMethodOverride?: string): Promise<boolean> => {
    if (!tenant || !activeOutlet || !user) return false;
    const effectiveMethod = paymentMethodOverride || paymentMethod;
    const effectiveIsSplitPayment = isSplitPayment && !paymentMethodOverride;
    const storedPaymentMethod = effectiveIsSplitPayment ? 'split' : effectiveMethod;
    const validationError = validatePOSPayment({
      total,
      paymentMethod: storedPaymentMethod,
      paymentAmount: Number(paymentAmount) || total,
      isSplitPayment: effectiveIsSplitPayment,
      splitAmount1: Number(splitAmount1),
      splitAmount2: Number(splitAmount2),
      isOnline,
      usePoints: usePoints && Boolean(loyaltyProgram),
      pointsToRedeem,
      minimumRedeemPoints: loyaltyProgram?.min_redeem_points ?? 0,
    });
    if (validationError && !paymentMethodOverride) {
      toast.error(validationError);
      return false;
    }
    const requestKey = paymentRequestKeyRef.current ?? crypto.randomUUID();
    paymentRequestKeyRef.current = requestKey;
    const saleNumber = `TRX-${Date.now()}`;
    const createdAt = new Date().toISOString();
    const paymentAmountValue = getEffectivePaymentAmount({
      total,
      paymentAmount: Number(paymentAmount) || total,
      isSplitPayment: effectiveIsSplitPayment,
      splitAmount1: Number(splitAmount1),
      splitAmount2: Number(splitAmount2),
    });
    const offlineSale: Omit<PendingSale, 'synced'> = {
      id: requestKey,
      sale_number: `OFF-${requestKey.slice(0, 8).toUpperCase()}`,
      outlet_id: activeOutlet.id,
      tenant_id: tenant.id,
      cashier_id: user.id,
      items: cart.map(item => ({
        product_id: item.productId,
        variant_id: item.variantId || null,
        name: item.name,
        variant_name: item.variantName || null,
        qty: item.qty,
        price: item.price,
        cost_price: item.costPrice,
        discount: item.discount,
        tax_rate: item.taxRate,
      })),
      subtotal,
      discount_amount: discount + calculatedPromoDiscount + calculatedVoucherDiscount + pointsDiscount,
      tax_amount: taxAmount,
      total,
      payment_method: storedPaymentMethod,
      payment_amount: paymentAmountValue,
      change_amount: effectiveMethod === 'cash' && !effectiveIsSplitPayment
        ? Math.max(0, paymentAmountValue - total)
        : 0,
      promotion_id: appliedPromo?.id || null,
      promotion_discount: calculatedPromoDiscount,
      voucher_id: appliedVoucher?.id || null,
      voucher_code: appliedVoucher?.code || null,
      voucher_discount: calculatedVoucherDiscount,
      loyalty_points_earned: pointsEarned,
      loyalty_points_redeemed: usePoints && selectedCustomer ? pointsToRedeem : 0,
      loyalty_discount: pointsDiscount,
      customer_segment: selectedCustomer?.is_member ? 'member' : 'retail',
      customer_id: selectedCustomer?.id || null,
      customer_name: selectedCustomer?.name || customerName || null,
      notes: notes || undefined,
      created_at: createdAt,
      request_key: requestKey,
      created_at_client: createdAt,
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      stock_unverified_until_sync: !isOnline,
      print_status: 'not_requested',
    };

    try {
      // Durable and atomic before the RPC: a refresh, tab close, or power loss
      // can recover this exact request key without creating a second sale.
      await saveCheckoutTransaction({
        id: requestKey,
        tenant_id: tenant.id,
        outlet_id: activeOutlet.id,
        created_at: createdAt,
        sale: offlineSale,
      });
      const result = await processAtomicPOSSale(
        requestKey,
        tenant.id,
        activeOutlet.id,
        user.id,
        {
          sale_number: saleNumber,
          cashier_name: user.email,
          customer_id: selectedCustomer?.id || null,
          customer_name: selectedCustomer?.name || customerName || null,
          customer_segment: selectedCustomer?.is_member ? 'member' : 'retail',
          subtotal,
          discount_amount: discount + calculatedPromoDiscount + calculatedVoucherDiscount + pointsDiscount,
          tax_amount: taxAmount,
          total,
          payment_method: storedPaymentMethod,
          payment_amount: paymentAmountValue,
          change_amount: effectiveMethod === 'cash' && !effectiveIsSplitPayment
            ? Math.max(0, paymentAmountValue - total)
            : 0,
          notes: effectiveIsSplitPayment ? `${notes ? `${notes} | ` : ''}Split: ${effectiveMethod}+${splitMethod2}` : (notes || null),
          promotion_id: appliedPromo?.id || null,
          promotion_discount: calculatedPromoDiscount,
          voucher_id: appliedVoucher?.id || null,
          voucher_code: appliedVoucher?.code || null,
          voucher_discount: calculatedVoucherDiscount,
          loyalty_points_earned: pointsEarned,
          loyalty_points_redeemed: usePoints && selectedCustomer ? pointsToRedeem : 0,
          loyalty_discount: pointsDiscount,
        },
        cart.map(item => ({
          product_id: item.productId,
          variant_id: item.variantId || null,
          name: item.name,
          variant_name: item.variantName || null,
          price: item.price,
          cost_price: item.costPrice,
          qty: item.qty,
          discount: item.discount,
          tax_amount: (item.price * item.qty - item.discount) * item.taxRate / 100,
          subtotal: item.price * item.qty - item.discount,
          notes: item.notes || null,
        })),
      );

      await markSaleSynced(requestKey, result);
      setLastSaleWasOffline(false);
      setLastSale({
        saleId: result.sale_id,
        saleNumber: result.sale_number,
        createdAt,
        outletId: activeOutlet.id,
        printJobId: createPrintJobId(result.sale_id, result.sale_number),
        total: result.total,
        change: effectiveMethod === 'cash' && !effectiveIsSplitPayment
          ? Math.max(0, paymentAmountValue - total)
          : 0,
        paymentMethod: effectiveMethod,
        customerName: selectedCustomer?.name || customerName || 'Umum',
        customerPhone: selectedCustomer?.phone || null,
        items: [...cart],
        subtotal,
        taxAmount,
        paidAmount: paymentAmountValue,
        pointsEarned,
        pointsRedeemed: usePoints ? pointsToRedeem : 0,
        pointsDiscount,
        promoDiscount: calculatedPromoDiscount,
        voucherDiscount: calculatedVoucherDiscount,
        appliedPromoName: appliedPromo?.name || null,
        appliedVoucherCode: appliedVoucher?.code || null,
        newPointsBalance: selectedCustomer ? Math.max(0, customerPoints - (usePoints ? pointsToRedeem : 0) + pointsEarned) : null,
      });

      void clearCheckoutCheckpoint(requestKey).catch((checkpointError) => {
        console.warn('[pos-offline] failed to clear completed checkout checkpoint:', checkpointError);
      });
      paymentRequestKeyRef.current = null;
      clearCart(); setNotes(''); setSelectedCustomer(null); setCustomerName('');
      resetPayment(); setSuccessDialog(true); fetchProducts();
      return true;
    } catch (err: unknown) {
      // Keep the request key so a retry after a timeout cannot create a second sale.
      const browserOffline = typeof navigator !== 'undefined' && !navigator.onLine;
      if ((browserOffline || !isOnline) && storedPaymentMethod === 'cash') {
        try {
          const queuedSale = { ...offlineSale, payment_method: 'cash' };
          await saveOfflineSale({ ...queuedSale, print_status: 'queued', stock_unverified_until_sync: true });
          await clearCheckoutCheckpoint(requestKey);
          const offlineSaleNumber = queuedSale.sale_number || `OFF-${requestKey.slice(0, 8).toUpperCase()}`;
          setLastSaleWasOffline(true);
          setLastSale({
            saleId: requestKey,
            saleNumber: offlineSaleNumber,
            createdAt,
            outletId: activeOutlet.id,
            printJobId: createPrintJobId(requestKey, offlineSaleNumber),
            total,
            change: Math.max(0, paymentAmountValue - total),
            paymentMethod: 'cash',
            customerName: selectedCustomer?.name || customerName || 'Umum',
            customerPhone: selectedCustomer?.phone || null,
            items: [...cart],
            pointsEarned,
            pointsRedeemed: usePoints ? pointsToRedeem : 0,
            pointsDiscount,
            promoDiscount: calculatedPromoDiscount,
            voucherDiscount: calculatedVoucherDiscount,
            appliedPromoName: appliedPromo?.name || null,
            appliedVoucherCode: appliedVoucher?.code || null,
            newPointsBalance: null,
            subtotal,
            taxAmount,
            paidAmount: paymentAmountValue,
          });
          paymentRequestKeyRef.current = null;
          clearCart(); setNotes(''); setSelectedCustomer(null); setCustomerName('');
          resetPayment(); setSuccessDialog(true);
          toast.success('Transaksi disimpan offline dan akan disinkronkan saat online');
          void triggerSync();
          return true;
        } catch (queueError: unknown) {
          toast.error('Gagal menyimpan transaksi offline: ' + (queueError instanceof Error ? queueError.message : 'Kesalahan tidak diketahui'));
        }
      }
      toast.error('Gagal memproses transaksi: ' + (err instanceof Error ? err.message : 'Kesalahan tidak diketahui'));
      return false;
    }
  };

  // ── Hold Bill ────────────────────────────────────────────
  const holdBill = useCallback(async () => {
    if (cart.length === 0) return;
    try {
      await persistHeldBill({
        items: cart,
        discountAmount: discount,
        notes,
        customerName: selectedCustomer?.name || customerName || null,
        customerId: selectedCustomer?.id || null,
      });
      clearCart(); setNotes(''); setSelectedCustomer(null); setCustomerName('');
      toast.success('Transaksi ditahan');
    } catch (error: unknown) {
      toast.error('Gagal menahan transaksi: ' + (error instanceof Error ? error.message : 'Kesalahan tidak diketahui'));
    }
  }, [cart, persistHeldBill, discount, notes, selectedCustomer, customerName, clearCart]);

  // ── Fetch and keyboard effects ───────────────────────────
  useEffect(() => {
    if (tenant && activeOutlet) {
      fetchProducts(); fetchCategories(); fetchHeldBills();
      void refreshProductCache();
    }
  }, [tenant, activeOutlet, fetchProducts, fetchCategories, fetchHeldBills, refreshProductCache]);

  useEffect(() => {
    if (tenant) { fetchLoyaltyProgram(); fetchActivePromos(); }
  }, [tenant, fetchLoyaltyProgram, fetchActivePromos]);

  useEffect(() => {
    if (selectedCustomer && tenant) fetchCustomerPoints(selectedCustomer.id);
    else { setCustomerPoints(0); setCustomerTier('Bronze'); setUsePoints(false); setPointsToRedeem(0); }
    setAppliedVoucher(null); setVoucherDiscount(0); setVoucherCode(''); setVoucherError('');
  }, [selectedCustomer, tenant, fetchCustomerPoints]);

  useEffect(() => {
    if (appliedPromo) setPromoDiscount(calcPromoDiscount(appliedPromo));
    else autoApplyBestPromo();
  }, [cart, appliedPromo, autoApplyBestPromo, calcPromoDiscount]);

  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
      if (e.key === 'F2') { e.preventDefault(); openPayment(); }
      if (e.key === 'F3') { e.preventDefault(); holdBill(); }
      if (e.key === 'F8') { e.preventDefault(); searchRef.current?.focus(); }
      if (e.key === 'Escape') { setSearch(''); searchRef.current?.blur(); }
    };
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, [openPayment, holdBill]);

  const resumeBill = async (bill: HeldBill) => {
    try {
      await deleteHeldBill(bill);
      setCart(bill.items); setDiscount(bill.discount_amount); setNotes(bill.notes); setCustomerName(bill.customer_name || '');
      setHeldBillsDialog(false); toast.success('Transaksi dilanjutkan');
    } catch (error: unknown) {
      toast.error('Gagal melanjutkan transaksi: ' + (error instanceof Error ? error.message : 'Kesalahan tidak diketahui'));
    }
  };

  // ── Product filter + barcode ─────────────────────────────
  const filteredProducts = products.filter(p => {
    const matchSearch = p.name.toLowerCase().includes(search.toLowerCase()) ||
      (p.sku && p.sku.toLowerCase().includes(search.toLowerCase())) ||
      (p.barcode && p.barcode.includes(search));
    const matchCat = filterCat === 'all' || p.category_id === filterCat;
    return matchSearch && matchCat;
  });

  const onBarcodeDetect = useCallback((barcode: string) => {
    const match = products.find(p => p.barcode === barcode || p.sku === barcode);
    if (match) { addToCart(match); toast.success(`✓ ${match.name} ditambahkan`); }
    else { setSearch(barcode); setScannerOpen(false); toast.info(`Barcode "${barcode}" — pilih produk secara manual`); }
  }, [products, addToCart]);


  const autoPrintedJobRef = useRef<string | null>(null);
  useEffect(() => {
    const settings = getPrinterSettings();
    if (!successDialog || !lastSale || !settings.autoPrint || autoPrintedJobRef.current === lastSale.printJobId) return;
    autoPrintedJobRef.current = lastSale.printJobId;
    void printReceipt();
  }, [successDialog, lastSale, printReceipt]);

  const sendReceiptViaWhatsApp = () => {
    if (!lastSale) return;
    const storeName = (tenant as unknown as ReceiptStore)?.name || 'Toko';
    const storePhone = (tenant as unknown as ReceiptStore)?.phone || '';
    const receiptDate = lastSale.createdAt ? new Date(lastSale.createdAt) : new Date();
    const tgl = receiptDate.toLocaleDateString('id-ID', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
    const payLabel: Record<string, string> = { cash: 'Tunai', qris: 'QRIS', transfer: 'Transfer', debit: 'Debit', qr_pay: 'QR Pay' };
    const methodLabel = payLabel[lastSale.paymentMethod] || lastSale.paymentMethod;

    const lines: string[] = [];
    lines.push(`🧾 *STRUK PEMBAYARAN*`);
    lines.push(`*${storeName}*`);
    if (storePhone) lines.push(`📞 ${storePhone}`);
    lines.push(`─────────────────────`);
    lines.push(`No : ${lastSale.saleNumber}`);
    lines.push(`Tgl: ${tgl}`);
    if (lastSale.customerName && lastSale.customerName !== 'Umum') lines.push(`Plg: ${lastSale.customerName}`);
    lines.push(`─────────────────────`);
    for (const item of lastSale.items) {
      const name = item.variantName ? `${item.name} (${item.variantName})` : item.name;
      lines.push(`${name}`);
      const sub = item.price * item.qty - (item.discount || 0);
      lines.push(`  ${item.qty}x ${formatCurrency(item.price)}  =  ${formatCurrency(sub)}`);
      if ((item.discount || 0) > 0) lines.push(`  Diskon: -${formatCurrency(item.discount)}`);
    }
    lines.push(`─────────────────────`);
    if ((lastSale.promoDiscount || 0) > 0) lines.push(`Diskon Promo : -${formatCurrency(lastSale.promoDiscount)}`);
    if ((lastSale.voucherDiscount || 0) > 0) lines.push(`Voucher : -${formatCurrency(lastSale.voucherDiscount)}`);
    if ((lastSale.pointsDiscount || 0) > 0) lines.push(`Tukar Poin : -${formatCurrency(lastSale.pointsDiscount)}`);
    lines.push(`*TOTAL : ${formatCurrency(lastSale.total)}*`);
    lines.push(`Metode : ${methodLabel}`);
    if (lastSale.paymentMethod === 'cash' && (lastSale.change || 0) > 0) {
      lines.push(`Kembalian : ${formatCurrency(lastSale.change)}`);
    }
    if ((lastSale.pointsEarned || 0) > 0) {
      lines.push(`─────────────────────`);
      lines.push(`⭐ Poin diperoleh: +${lastSale.pointsEarned.toLocaleString('id-ID')} poin`);
      if (lastSale.newPointsBalance !== null) lines.push(`   Saldo poin: ${lastSale.newPointsBalance.toLocaleString('id-ID')} poin`);
    }
    lines.push(`─────────────────────`);
    lines.push(`Terima kasih telah berbelanja! 🙏`);

    const message = encodeURIComponent(lines.join('\n'));
    const customerPhone = lastSale.customerPhone?.replace(/\D/g, '').replace(/^0/, '62') || '';
    const url = customerPhone
      ? `https://wa.me/${customerPhone}?text=${message}`
      : `https://wa.me/?text=${message}`;
    window.open(url, '_blank');
  };

  const exportReceiptPDF = () => {
    if (!lastSale) return;
    const storeName = (tenant as unknown as ReceiptStore)?.name || 'Toko';
    const storeAddress = (tenant as unknown as ReceiptStore)?.address || '';
    const storePhone = (tenant as unknown as ReceiptStore)?.phone || '';
    const receiptHeader = (tenant as unknown as ReceiptStore)?.receipt_header || '';
    const receiptFooter = (tenant as unknown as ReceiptStore)?.receipt_footer || 'Terima kasih telah berbelanja!';
    const receiptDate = lastSale.createdAt ? new Date(lastSale.createdAt) : new Date();
    const tgl = receiptDate.toLocaleDateString('id-ID', { day: '2-digit', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit' });
    const payLabel: Record<string, string> = { cash: 'Tunai', qris: 'QRIS', transfer: 'Transfer', debit: 'Debit', qr_pay: 'QR Pay' };
    const methodLabel = payLabel[lastSale.paymentMethod] || lastSale.paymentMethod;

    const itemRows = lastSale.items.map((item: CartItem) => {
      const name = item.variantName ? `${item.name} (${item.variantName})` : item.name;
      const sub = item.price * item.qty - (item.discount || 0);
      const discRow = (item.discount || 0) > 0
        ? `<tr><td colspan="3" style="color:#ef4444;font-size:10px;padding:0 0 2px 4px">Diskon: -${formatCurrency(item.discount)}</td></tr>`
        : '';
      return `<tr>
        <td style="padding:3px 0;vertical-align:top">${name}</td>
        <td style="text-align:center;white-space:nowrap">${item.qty}x</td>
        <td style="text-align:right;white-space:nowrap">${formatCurrency(sub)}</td>
      </tr>${discRow}`;
    }).join('');

    const discountRows = [
      (lastSale.promoDiscount || 0) > 0 ? `<tr><td colspan="2" style="color:#f97316">Diskon Promo</td><td style="text-align:right;color:#f97316">-${formatCurrency(lastSale.promoDiscount)}</td></tr>` : '',
      (lastSale.voucherDiscount || 0) > 0 ? `<tr><td colspan="2" style="color:#a855f7">Voucher (${lastSale.appliedVoucherCode})</td><td style="text-align:right;color:#a855f7">-${formatCurrency(lastSale.voucherDiscount)}</td></tr>` : '',
      (lastSale.pointsDiscount || 0) > 0 ? `<tr><td colspan="2" style="color:#10b981">Tukar Poin</td><td style="text-align:right;color:#10b981">-${formatCurrency(lastSale.pointsDiscount)}</td></tr>` : '',
    ].join('');

    const pointsSection = (lastSale.pointsEarned || 0) > 0 ? `
      <div style="background:#ecfdf5;border:1px solid #a7f3d0;border-radius:6px;padding:8px;margin-top:8px;font-size:11px">
        <div style="color:#065f46;font-weight:bold;margin-bottom:4px">⭐ Ringkasan Poin</div>
        ${(lastSale.pointsRedeemed || 0) > 0 ? `<div style="display:flex;justify-content:space-between;color:#dc2626"><span>Ditukar</span><span>-${lastSale.pointsRedeemed.toLocaleString('id-ID')} poin</span></div>` : ''}
        <div style="display:flex;justify-content:space-between;color:#059669"><span>Diperoleh</span><span>+${lastSale.pointsEarned.toLocaleString('id-ID')} poin</span></div>
        ${lastSale.newPointsBalance !== null ? `<div style="display:flex;justify-content:space-between;font-weight:bold;color:#065f46;border-top:1px solid #a7f3d0;margin-top:4px;padding-top:4px"><span>Saldo Poin</span><span>${lastSale.newPointsBalance.toLocaleString('id-ID')} poin</span></div>` : ''}
      </div>` : '';

    const changeRow = lastSale.paymentMethod === 'cash' && (lastSale.change || 0) > 0
      ? `<tr><td colspan="2">Kembalian</td><td style="text-align:right">${formatCurrency(lastSale.change)}</td></tr>` : '';

    const html = `<!DOCTYPE html><html><head><meta charset="utf-8">
    <title>Struk - ${lastSale.saleNumber}</title>
    <style>
      @page { size: 80mm auto; margin: 4mm; }
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body { font-family: 'Courier New', Courier, monospace; font-size: 12px; color: #111; width: 72mm; }
      .center { text-align: center; }
      .bold { font-weight: bold; }
      .divider { border-top: 1px dashed #999; margin: 6px 0; }
      table { width: 100%; border-collapse: collapse; font-size: 11px; }
      .total-row td { font-weight: bold; font-size: 13px; border-top: 1px solid #111; padding-top: 4px; }
      @media print {
        body { margin: 0; }
        button { display: none; }
      }
    </style>
    </head><body>
    <div class="center bold" style="font-size:14px;margin-bottom:2px">${storeName}</div>
    ${storeAddress ? `<div class="center" style="font-size:10px">${storeAddress}</div>` : ''}
    ${storePhone ? `<div class="center" style="font-size:10px">${storePhone}</div>` : ''}
    ${receiptHeader ? `<div class="center" style="font-size:10px;margin-top:2px">${receiptHeader}</div>` : ''}
    <div class="divider"></div>
    <table><tbody>
      <tr><td>No</td><td colspan="2">: ${lastSale.saleNumber}</td></tr>
      <tr><td>Tgl</td><td colspan="2">: ${tgl}</td></tr>
      ${lastSale.customerName && lastSale.customerName !== 'Umum' ? `<tr><td>Plg</td><td colspan="2">: ${lastSale.customerName}</td></tr>` : ''}
    </tbody></table>
    <div class="divider"></div>
    <table><tbody>${itemRows}</tbody></table>
    <div class="divider"></div>
    <table><tbody>
      ${discountRows}
      <tr class="total-row"><td colspan="2">TOTAL</td><td style="text-align:right">${formatCurrency(lastSale.total)}</td></tr>
      <tr><td colspan="2">Metode</td><td style="text-align:right">${methodLabel}</td></tr>
      ${changeRow}
    </tbody></table>
    ${pointsSection}
    <div class="divider"></div>
    <div class="center" style="font-size:10px;margin-top:4px">${receiptFooter}</div>
    <div style="height:8px"></div>
    </body></html>`;

    const win = window.open('', '_blank', 'width=400,height=600');
    if (!win) { toast.error('Popup diblokir. Izinkan popup untuk export PDF.'); return; }
    win.document.write(DOMPurify.sanitize(html, { USE_PROFILES: { html: true } }));
    win.document.close();
    win.focus();
    setTimeout(() => { win.print(); }, 300);
  };

  if (!tenant) return (
    <div className="flex items-center justify-center h-screen">
      <div className="text-center">
        <p className="font-medium">Aktifkan POS terlebih dahulu</p>
        <p className="mt-1 text-sm text-muted-foreground">Pilih paket POS sebelum membuat workspace dan outlet.</p>
        <Button onClick={() => navigate('/merchant/pos/subscribe')} className="mt-4 bg-emerald-600 hover:bg-emerald-700">Lihat Paket POS</Button>
      </div>
    </div>
  );

  return (

    <POSLayout
      title="Kasir"
      subtitle={activeOutlet?.name ? `Outlet: ${activeOutlet.name}` : 'Checkout POS'}
      fullWidth
    >
      <div className="flex h-full min-h-0 flex-1 flex-col lg:flex-row overflow-hidden">

        {/* Panel Produk */}
        <div className="flex-1 min-h-0 flex flex-col min-w-0 border-b lg:border-b-0 lg:border-r">
          <div className="p-3 border-b bg-background space-y-2">
            <div className="flex items-center gap-2">
              <div className="relative flex-1">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input ref={searchRef} className="pl-9 pr-9 h-9" placeholder="Cari produk / scan barcode... (F8)"
                  value={search} onChange={e => setSearch(e.target.value)} autoFocus />
              </div>
               <div className={cn('hidden sm:flex items-center gap-1 text-[10px] whitespace-nowrap', isOnline ? 'text-emerald-600' : 'text-amber-600')}>
                <span className={cn('h-2 w-2 rounded-full', isOnline ? 'bg-emerald-500' : 'bg-amber-500')} />
                {isOnline ? (isSyncing ? 'Sync...' : pendingCount > 0 ? `${pendingCount} antrean` : 'Online') : 'Offline'}
                {pendingCount > 0 && isOnline && <button type="button" className="underline" onClick={() => void triggerSync()}>sync</button>}
              </div>
               <div className={cn('hidden md:block text-[10px] whitespace-nowrap', isCacheStale ? 'text-amber-600' : 'text-muted-foreground')}>
                 {cacheAgeMs === null ? 'Cache belum ada' : `Cache ${Math.max(1, Math.round(cacheAgeMs / 60_000))}m`}
               </div>
               {(queueSummary.failed > 0 || queueSummary.conflict > 0) && (
                 <button type="button" className="hidden md:block text-[10px] text-destructive underline whitespace-nowrap" onClick={() => navigate('/merchant/pos/offline-conflicts')}>
                   {queueSummary.conflict + queueSummary.failed} perlu ditinjau
                 </button>
               )}
              <Button variant="outline" size="icon" className="h-9 w-9 flex-shrink-0" onClick={() => setScannerOpen(true)} title="Scan Barcode Kamera">
                <Barcode className="h-4 w-4 text-emerald-600" />
              </Button>
            </div>
            <div className="flex gap-1.5 overflow-x-auto pb-1">
              <Button size="sm" variant={filterCat === 'all' ? 'default' : 'outline'}
                className={cn('h-7 text-xs flex-shrink-0', filterCat === 'all' ? 'bg-emerald-600 hover:bg-emerald-700' : '')}
                onClick={() => setFilterCat('all')}>Semua</Button>
              {categories.map(c => (
                <Button key={c.id} size="sm" variant={filterCat === c.id ? 'default' : 'outline'}
                  className={cn('h-7 text-xs flex-shrink-0', filterCat === c.id ? 'bg-emerald-600 hover:bg-emerald-700' : '')}
                  onClick={() => setFilterCat(c.id)}>{c.name}</Button>
              ))}
            </div>
          </div>

          <div className="flex-1 overflow-y-auto p-3">
            {loading ? (
              <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2">
                {[...Array(12)].map((_, i) => <div key={i} className="h-24 bg-muted animate-pulse rounded-xl" />)}
              </div>
            ) : filteredProducts.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-40">
                <Package className="h-10 w-10 text-muted-foreground mb-2" />
                <p className="text-sm font-medium">{search ? 'Produk tidak ditemukan' : 'Belum ada produk di kasir'}</p>
                {!search && (
                  <>
                    <p className="mt-1 max-w-sm text-center text-xs leading-5 text-muted-foreground">
                      Produk kasir mengikuti Katalog Merchant. Tambahkan atau aktifkan produk dari sana agar muncul di outlet ini.
                    </p>
                    <Button variant="outline" size="sm" className="mt-3" onClick={() => navigate('/merchant/products')}>
                      Buka Katalog Merchant
                    </Button>
                  </>
                )}
              </div>
            ) : (
              <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-2">
                {filteredProducts.map(p => {
                  const stock = p.pos_stock?.[0]?.quantity ?? 0;
                  const isLowStock = p.is_stock_tracked && stock <= 5;
                  const outOfStock = p.is_stock_tracked && stock <= 0;
                  return (
                    <button key={p.id} onClick={() => !outOfStock && addToCart(p)} disabled={outOfStock}
                      className={cn('text-left p-3 rounded-xl border transition-all hover:shadow-md active:scale-[0.97]', outOfStock ? 'opacity-40 cursor-not-allowed' : 'cursor-pointer hover:border-emerald-400')}>
                      <div className="w-full aspect-square bg-muted rounded-lg flex items-center justify-center mb-2">
                        {p.image_url ? <img src={p.image_url} className="w-full h-full object-cover rounded-lg" /> : <Package className="h-6 w-6 text-muted-foreground" />}
                      </div>
                      <p className="text-xs font-medium line-clamp-2 mb-1">{p.name}</p>
                      <p className="text-sm font-bold text-emerald-600">{formatCurrency(p.price)}</p>
                      {p.is_stock_tracked && (
                        <p className={cn('text-xs mt-0.5', isLowStock ? 'text-amber-500' : 'text-muted-foreground')}>
                          {outOfStock ? 'Habis' : `Stok: ${stock}`}
                        </p>
                      )}
                    </button>
                  );
                })}
              </div>
            )}
          </div>
        </div>

        {/* Panel Cart — lazy-loaded agar katalog awal lebih ringan */}
        <Suspense fallback={<div className="flex h-full items-center justify-center text-sm text-muted-foreground">Memuat keranjang...</div>}>
        <POSCart
          cart={cart} discount={discount} notes={notes}
          selectedCustomer={selectedCustomer} customerName={customerName} customerTier={customerTier}
          loyaltyProgram={loyaltyProgram} customerPoints={customerPoints}
          usePoints={usePoints} pointsToRedeem={pointsToRedeem} pointsDiscount={pointsDiscount} pointsEarned={pointsEarned}
          appliedPromo={appliedPromo} promoDiscount={promoDiscount}
          appliedVoucher={appliedVoucher} voucherDiscount={voucherDiscount}
          voucherCode={voucherCode} voucherError={voucherError}
          subtotal={subtotal} taxAmount={taxAmount} total={total}
          heldBillsCount={heldBills.length}
          formatCurrency={formatCurrency}
          onUpdateQty={updateQty} onRemoveItem={removeItem} onUpdateDiscount={updateItemDiscount}
          onSetDiscount={setDiscount} onSetNotes={setNotes}
          onOpenCustomer={() => setCustomerDialog(true)}
          onOpenHeldBills={() => setHeldBillsDialog(true)}
          onHoldBill={holdBill} onOpenPayment={openPayment} onClearCart={clearCart}
          onTogglePoints={handleTogglePoints} onPointsInput={handlePointsInput}
          onApplyVoucher={applyVoucher} onRemoveVoucher={removeVoucher}
          onSetVoucherCode={setVoucherCode} onSetVoucherError={setVoucherError}
        />
        </Suspense>
      </div>

      {/* Dialog Pembayaran: dimuat hanya ketika kasir membuka checkout */}
      {paymentDialog && (
        <Suspense fallback={null}>
          <POSPaymentDialog
            open={paymentDialog} onOpenChange={setPaymentDialog}
            subtotal={subtotal} taxAmount={taxAmount} discount={discount}
            promoDiscount={promoDiscount} voucherDiscount={voucherDiscount} pointsDiscount={pointsDiscount}
            total={total} paymentMethod={paymentMethod} paymentAmount={paymentAmount}
            isSplitPayment={isSplitPayment} splitMethod2={splitMethod2} splitAmount1={splitAmount1} splitAmount2={splitAmount2}
            appliedPromo={appliedPromo} appliedVoucher={appliedVoucher}
            pointsToRedeem={pointsToRedeem} pointsEarned={pointsEarned}
            selectedCustomer={selectedCustomer} loyaltyProgram={loyaltyProgram}
            isOnline={isOnline}
            formatCurrency={formatCurrency} onChange={handlePaymentChange} onProcess={processPayment}
          />
        </Suspense>
      )}

      {/* Dialog Sukses */}
      <Dialog open={successDialog} onOpenChange={setSuccessDialog}>
        <DialogContent className="max-w-sm">
          <div className="text-center py-2">
            <div className="w-16 h-16 bg-emerald-100 rounded-full flex items-center justify-center mx-auto mb-3">
              <CheckCircle2 className="h-8 w-8 text-emerald-600" />
            </div>
            <DialogTitle className="text-xl font-bold mb-1">{lastSaleWasOffline ? 'Tersimpan di Perangkat' : 'Transaksi Berhasil!'}</DialogTitle>
            <DialogDescription className="sr-only">
              {lastSaleWasOffline
                ? 'Transaksi tersimpan lokal dan belum tercatat di server.'
                : 'Transaksi pembayaran POS berhasil tercatat.'}
            </DialogDescription>
            {lastSaleWasOffline && (
              <p className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-left text-xs leading-5 text-amber-900" role="status">
                <strong>Transaksi tersimpan di perangkat. Belum tercatat di server.</strong><br />
                Jangan hapus data browser sebelum status tersinkronisasi. Pembayaran tunai akan dikirim otomatis saat online kembali.
              </p>
            )}
            {lastSale && (
              <div className="bg-muted rounded-xl p-4 mt-3 text-left space-y-2 text-sm">
                <div className="flex justify-between"><span className="text-muted-foreground">No. Transaksi</span><span className="font-mono font-bold text-xs">{lastSale.saleNumber}</span></div>
                <div className="flex justify-between"><span className="text-muted-foreground">Customer</span><span className="font-medium">{lastSale.customerName}</span></div>
                {lastSale.promoDiscount > 0 && <div className="flex justify-between text-orange-600 text-xs"><span className="flex items-center gap-1"><Percent className="h-3 w-3" />Promo</span><span>-{formatCurrency(lastSale.promoDiscount)}</span></div>}
                {lastSale.voucherDiscount > 0 && <div className="flex justify-between text-purple-600 text-xs"><span className="flex items-center gap-1"><Ticket className="h-3 w-3" />{lastSale.appliedVoucherCode}</span><span>-{formatCurrency(lastSale.voucherDiscount)}</span></div>}
                {lastSale.pointsDiscount > 0 && <div className="flex justify-between text-emerald-600 text-xs"><span className="flex items-center gap-1"><Star className="h-3 w-3" />Poin ditukar</span><span>-{formatCurrency(lastSale.pointsDiscount)}</span></div>}
                <div className="flex justify-between font-bold border-t pt-2"><span>Total Dibayar</span><span className="text-emerald-600">{formatCurrency(lastSale.total)}</span></div>
                {lastSale.paymentMethod === 'cash' && lastSale.change > 0 && <div className="flex justify-between"><span className="text-muted-foreground">Kembalian</span><span className="font-bold">{formatCurrency(lastSale.change)}</span></div>}
                {lastSale.pointsEarned > 0 && (
                  <div className="bg-emerald-50 border border-emerald-200 rounded-lg p-3 mt-2 space-y-1">
                    <p className="text-xs font-semibold text-emerald-700 flex items-center gap-1"><Star className="h-3.5 w-3.5" />Ringkasan Poin</p>
                    {lastSale.pointsRedeemed > 0 && <div className="flex justify-between text-xs text-red-600"><span>Ditukar</span><span>-{lastSale.pointsRedeemed.toLocaleString('id-ID')} poin</span></div>}
                    <div className="flex justify-between text-xs text-emerald-600"><span>Diperoleh</span><span>+{lastSale.pointsEarned.toLocaleString('id-ID')} poin</span></div>
                    {lastSale.newPointsBalance !== null && <div className="flex justify-between text-xs font-bold text-emerald-700 border-t pt-1"><span>Saldo Poin</span><span>{lastSale.newPointsBalance.toLocaleString('id-ID')} poin</span></div>}
                  </div>
                )}
              </div>
            )}
            <div className="grid grid-cols-2 gap-2 mt-4">
              <Button variant="outline" className="flex-1 text-sm" onClick={printReceipt}>
                <Printer className="h-4 w-4 mr-1.5" />Cetak Struk
              </Button>
              <Button className="flex-1 text-sm bg-emerald-600 hover:bg-emerald-700" onClick={() => { setSuccessDialog(false); searchRef.current?.focus(); }}>
                Transaksi Baru
              </Button>
              <Button variant="outline" className="flex-1 text-sm border-green-500 text-green-600 hover:bg-green-50" onClick={sendReceiptViaWhatsApp}>
                <MessageCircle className="h-4 w-4 mr-1.5" />Kirim via WA
              </Button>
              <Button variant="outline" className="flex-1 text-sm border-blue-400 text-blue-600 hover:bg-blue-50" onClick={exportReceiptPDF}>
                <FileDown className="h-4 w-4 mr-1.5" />Simpan PDF
              </Button>
            </div>
            {(() => {
              const ps = getPrinterSettings();
              const typeLabel = ps.connectionType === 'wifi' ? `WiFi (${ps.wifiIp || 'belum diatur'})` : ps.connectionType === 'bluetooth' ? 'Bluetooth' : 'USB';
              return (
                <Button variant="ghost" size="sm" className={`w-full mt-1 text-xs ${thermalConnected ? 'text-emerald-600' : 'text-muted-foreground'}`}
                  onClick={connectThermalPrinter} disabled={thermalConnecting}>
                  <Printer className="h-3 w-3 mr-1.5" />
                  {thermalConnected ? `● Printer ${typeLabel} Terhubung` : thermalConnecting ? 'Menghubungkan...' : `Hubungkan Printer ${typeLabel} (ESC/POS)`}
                </Button>
              );
            })()}
          </div>
        </DialogContent>
      </Dialog>

      {/* Dialog Held Bills: tidak diperlukan pada initial render */}
      {heldBillsDialog && (
        <Suspense fallback={null}>
          <POSHeldBills open={heldBillsDialog} onOpenChange={setHeldBillsDialog} heldBills={heldBills} onResume={resumeBill} />
        </Suspense>
      )}

      {/* Dialog Varian */}
      <Dialog open={variantDialog} onOpenChange={setVariantDialog}>
        <DialogContent>
          <DialogHeader><DialogTitle>Pilih Varian — {selectedProduct?.name}</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-2">
            {variants.map(v => (
              <button key={v.id} className="p-3 border rounded-lg text-left hover:border-emerald-400 transition-colors"
                onClick={() => { addToCart(selectedProduct!, v.id, v.name, v.price ?? selectedProduct?.price); setVariantDialog(false); }}>
                <p className="font-medium text-sm">{v.name}</p>
                <p className="text-emerald-600 text-sm">{formatCurrency(v.price ?? selectedProduct?.price ?? 0)}</p>
              </button>
            ))}
          </div>
        </DialogContent>
      </Dialog>

      {/* Dialog Customer */}
      <Dialog open={customerDialog} onOpenChange={setCustomerDialog}>
        <DialogContent>
          <DialogHeader><DialogTitle>Pilih Customer</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <Input placeholder="Cari nama customer..." value={customerSearch || customerName}
              onChange={e => { const v = e.target.value; setCustomerName(v); setCustomerSearch(v); searchCustomers(v); }} autoFocus />
            {customers.length > 0 && (
              <div className="space-y-1 max-h-60 overflow-y-auto">
                {customers.map(c => (
                  <button key={c.id} className="w-full flex items-center gap-3 p-2 rounded-lg hover:bg-muted text-left"
                    onClick={() => { setSelectedCustomer(c); setCustomerName(''); setCustomerSearch(''); setCustomerDialog(false); }}>
                    <div className={cn('w-9 h-9 rounded-full flex items-center justify-center text-sm font-bold flex-shrink-0', c.is_member ? 'bg-amber-100 text-amber-700' : 'bg-muted text-muted-foreground')}>
                      {c.name[0].toUpperCase()}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium">{c.name}</p>
                      {c.phone && <p className="text-xs text-muted-foreground">{c.phone}</p>}
                    </div>
                    <div className="flex flex-col items-end gap-1">
                      {c.is_member && <Badge className="bg-amber-100 text-amber-700 border-0 text-xs">Member</Badge>}
                      {loyaltyProgram && (c.loyalty_points || 0) > 0 && (
                        <span className="text-xs text-emerald-600 flex items-center gap-0.5">
                          <Star className="h-2.5 w-2.5" />{(c.loyalty_points || 0).toLocaleString('id-ID')}
                        </span>
                      )}
                    </div>
                  </button>
                ))}
              </div>
            )}
            {selectedCustomer && (
              <div className="flex items-center justify-between bg-emerald-50 border border-emerald-200 p-2 rounded-lg">
                <div>
                  <span className="text-sm font-medium">{selectedCustomer.name}</span>
                  {loyaltyProgram && <span className="ml-2 text-xs text-emerald-600">{customerPoints.toLocaleString('id-ID')} poin</span>}
                </div>
                <Button variant="ghost" size="sm" className="h-7 text-xs text-destructive" onClick={() => { setSelectedCustomer(null); setCustomerName(''); }}>Hapus</Button>
              </div>
            )}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setCustomerDialog(false)}>Batal</Button>
            <Button className="bg-emerald-600 hover:bg-emerald-700" onClick={() => setCustomerDialog(false)}>Konfirmasi</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {scannerOpen && (
        <Suspense fallback={null}>
          <BarcodeScanner open={scannerOpen} onClose={() => setScannerOpen(false)} onDetect={onBarcodeDetect} />
        </Suspense>
      )}
    </POSLayout>
  );
}
