import { useState, useEffect, useMemo, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { motion } from 'framer-motion';
import { ArrowLeft, MapPin, Truck, Package, Loader2, CheckCircle, CreditCard, AlertTriangle, Clock, Ticket } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Badge } from '@/components/ui/badge';
import { VoucherInput } from '@/components/checkout/VoucherInput';
import { useCart } from '@/contexts/CartContext';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { formatPrice, safeGoBack } from '@/lib/utils';
import { useTranslation, useFormatters } from '@/lib/i18n';
import { toast } from '@/hooks/use-toast';
import { createPaymentInvoice, isXenditEnabled } from '@/lib/paymentApi';
import { CheckoutAddressForm, type CheckoutAddressData } from '@/components/checkout/CheckoutAddressForm';
import { createEmptyCheckoutAddress } from '@/components/checkout/checkoutAddressDefaults';
import { formatFullAddress } from '@/components/AddressSelector';
import { validatePhone } from '@/lib/phoneValidation';
import { getMerchantOperatingStatus, formatTime, type OperatingDaySchedule } from '@/lib/merchantOperatingHours';
import { getDeliveryRestriction, MAX_LOCAL_DELIVERY_DISTANCE_KM } from '@/lib/deliveryRestriction';
import { getGuestCheckoutSessionKey, guestOrderUrl, rememberGuestOrderAccess } from '@/lib/guestCheckout';
import { requestRequiredLocation } from '@/lib/requiredLocation';
import { useGuestCheckoutEnabled } from '@/hooks/useGuestCheckoutEnabled';
import { getCartStockDemand } from '@/lib/productAvailability';

type PaymentMethod = 'TRANSFER' | 'ONLINE';

interface MerchantOperatingInfo {
  id: string;
  name: string;
  isOpen: boolean;
  openTime: string | null;
  closeTime: string | null;
  weeklySchedule: OperatingDaySchedule[];
}

interface MerchantPaymentSettings {
  transferEnabled: boolean;
  bankName: string | null;
  bankAccountNumber: string | null;
  bankAccountName: string | null;
}

export default function CheckoutPage() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { enabled: guestCheckoutEnabled, loading: guestCheckoutFlagLoading } = useGuestCheckoutEnabled(Boolean(user));
  const { selectedItems, removeFromCart } = useCart();
  const items = selectedItems;
  const { t } = useTranslation();
  const { formatCurrency } = useFormatters();
  const [loading, setLoading] = useState(false);
  const [success, setSuccess] = useState(false);
  const [orderId, setOrderId] = useState<string | null>(null);
  const [guestToken, setGuestToken] = useState<string | null>(null);
  const [deliveryType, setDeliveryType] = useState<'PICKUP' | 'INTERNAL' | 'EXPEDITION'>('INTERNAL');
  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod>('TRANSFER');
  const [xenditAvailable, setXenditAvailable] = useState(false);
  const [paymentRecoveryError, setPaymentRecoveryError] = useState(false);
  const [retryingPayment, setRetryingPayment] = useState(false);
  const [notes, setNotes] = useState('');
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [appliedVoucher, setAppliedVoucher] = useState<{ id: string; name: string; discount: number } | null>(null);
  // Keep the same key while a checkout attempt is retried after a timeout or
  // invoice-provider failure. The database then returns the original order.
  const checkoutKeyRef = useRef<string | null>(null);
  const guestSessionKeyRef = useRef<string | null>(null);

  // Address state
  const [addressData, setAddressData] = useState<CheckoutAddressData>(createEmptyCheckoutAddress());

  // Distance state
  const [distanceKm, setDistanceKm] = useState<number | null>(null);

  // Shipping settings from admin
  const [shippingSettings, setShippingSettings] = useState<{ base_fee: number; per_km_fee: number; min_fee: number; max_fee: number; free_shipping_min_order: number } | null>(null);
  // Merchant payment settings
  const [merchantPaymentSettings, setMerchantPaymentSettings] = useState<MerchantPaymentSettings & { qrisImageUrl: string | null } | null>(null);

  useEffect(() => {
    if (!user && !guestCheckoutFlagLoading && !guestCheckoutEnabled) {
      navigate('/auth', { replace: true });
    }
  }, [guestCheckoutEnabled, guestCheckoutFlagLoading, navigate, user]);

  // Check if Xendit is enabled
  useEffect(() => {
    isXenditEnabled().then(setXenditAvailable);
    if (!user) guestSessionKeyRef.current = getGuestCheckoutSessionKey();
    // Load admin shipping settings
    supabase.from('app_settings').select('value').eq('key', 'shipping_base_fee').maybeSingle().then(({ data }) => {
      if (data?.value) {
        const v = data.value as Record<string, number>;
        setShippingSettings({
          base_fee: v.base_fee ?? 5000,
          per_km_fee: v.per_km_fee ?? 2000,
          min_fee: v.min_fee ?? 5000,
          max_fee: v.max_fee ?? 50000,
          free_shipping_min_order: v.free_shipping_min_order ?? 100000,
        });
      }
    });
  }, [user]);

  // Get merchant location state (will be loaded after merchantIds are computed)
  const [merchantLocation, setMerchantLocation] = useState<{ lat: number; lng: number } | null>(null);
  const [merchantRegion, setMerchantRegion] = useState<{
    cityName: string | null;
    districtName: string | null;
  }>({ cityName: null, districtName: null });

  const subtotal = selectedItems.reduce((sum, item) => sum + item.product.price * item.quantity, 0);

  // Calculate shipping based on distance
  const shippingCost = useMemo(() => {
    if (deliveryType === 'PICKUP') return 0;

    // Free shipping threshold check
    const freeShippingMin = shippingSettings?.free_shipping_min_order ?? Infinity;
    if (subtotal >= freeShippingMin) return 0;

    const baseFee = shippingSettings?.base_fee ?? 5000;
    const perKmFee = shippingSettings?.per_km_fee ?? 2000;
    const minFee = shippingSettings?.min_fee ?? 5000;
    const maxFee = shippingSettings?.max_fee ?? 50000;

    if (distanceKm !== null && distanceKm > 0) {
      return Math.min(maxFee, Math.max(minFee, baseFee + Math.round(distanceKm * perKmFee)));
    }

    return baseFee;
  }, [deliveryType, distanceKm, shippingSettings, subtotal]);

  const voucherDiscount = appliedVoucher?.discount || 0;
  const total = subtotal + shippingCost - voucherDiscount;

  const deliveryRestriction = useMemo(
    () => getDeliveryRestriction(
      distanceKm,
      addressData.address,
      merchantRegion,
    ),
    [distanceKm, addressData.address, merchantRegion],
  );

  useEffect(() => {
    if (deliveryRestriction.requiresExpedition && deliveryType === 'INTERNAL') {
      setDeliveryType('EXPEDITION');
    }
  }, [deliveryRestriction.requiresExpedition, deliveryType]);

  // Group items by merchant
  const itemsByMerchant = useMemo(() => items.reduce((acc, item) => {
    const merchantId = item.product.merchantId;
    if (!acc[merchantId]) {
      acc[merchantId] = {
        merchantName: item.product.merchantName,
        items: [],
      };
    }
    acc[merchantId].items.push(item);
    return acc;
  }, {} as Record<string, { merchantName: string; items: typeof items }>), [items]);

  // Get unique merchant IDs for quota check
  const merchantIdsKey = useMemo(
    () => Object.keys(itemsByMerchant).sort().join(','),
    [itemsByMerchant],
  );
  const merchantIds = useMemo(
    () => merchantIdsKey ? merchantIdsKey.split(',') : [],
    [merchantIdsKey],
  );
  const firstMerchantId = merchantIds[0];

  // Check merchant operating hours
  const [merchantOperatingInfo, setMerchantOperatingInfo] = useState<Record<string, MerchantOperatingInfo>>({});
  const [operatingHoursLoading, setOperatingHoursLoading] = useState(false);
  const [operatingHoursError, setOperatingHoursError] = useState<Error | null>(null);

  // Load merchant location and payment settings once per merchant. The
  // provider availability check must not refetch this whole block.
  useEffect(() => {
    let cancelled = false;
    const fetchMerchantData = async () => {
      if (!firstMerchantId) return;

      // Get location and payment settings of first merchant (simplified - assumes single merchant checkout)
      const { data } = await supabase
        .from('merchants')
        .select('location_lat, location_lng, province, city, district, payment_transfer_enabled, bank_name, bank_account_number, bank_account_name, qris_image_url')
        .eq('id', firstMerchantId)
        .maybeSingle();

      if (data) {
        if (data.location_lat && data.location_lng && !cancelled) {
          setMerchantLocation({
            lat: Number(data.location_lat),
            lng: Number(data.location_lng),
          });
        }
        if (cancelled) return;
        setMerchantRegion({
          cityName: data.city ?? null,
          districtName: data.district ?? null,
        });

        // If merchant has no bank info, load admin defaults
        let bankName = data.bank_name;
        let bankAccountNumber = data.bank_account_number;
        let bankAccountName = data.bank_account_name;
        let qrisImageUrl = data.qris_image_url;

        if (!bankName || !bankAccountNumber) {
          const { data: adminSettings } = await supabase
            .from('app_settings')
            .select('value')
            .eq('key', 'admin_payment_info')
            .maybeSingle();
          if (adminSettings?.value) {
            const ap = adminSettings.value as Record<string, string>;
            if (!bankName) bankName = ap.bank_name || null;
            if (!bankAccountNumber) bankAccountNumber = ap.bank_account_number || null;
            if (!bankAccountName) bankAccountName = ap.bank_account_name || null;
            if (!qrisImageUrl) qrisImageUrl = ap.qris_image_url || null;
          }
        }

        if (cancelled) return;
        setMerchantPaymentSettings({
          transferEnabled: data.payment_transfer_enabled ?? true,
          bankName,
          bankAccountNumber,
          bankAccountName,
          qrisImageUrl,
        });

      }
    };

    fetchMerchantData();
    return () => { cancelled = true; };
  }, [firstMerchantId]);

  useEffect(() => {
    if (!merchantPaymentSettings) return;
    setPaymentMethod((current) => {
      if (!user) return 'TRANSFER';
      if (merchantPaymentSettings.transferEnabled) {
        return current === 'ONLINE' && xenditAvailable ? current : 'TRANSFER';
      }
      return xenditAvailable ? 'ONLINE' : current;
    });
  }, [merchantPaymentSettings, xenditAvailable, user]);

  useEffect(() => {
    let cancelled = false;
    const loadMerchantOperatingHours = async () => {
      const ids = merchantIdsKey ? merchantIdsKey.split(',') : [];
      if (ids.length === 0) {
        setMerchantOperatingInfo({});
        setOperatingHoursError(null);
        setOperatingHoursLoading(false);
        return;
      }

      setOperatingHoursLoading(true);
      setOperatingHoursError(null);
      try {
        const [{ data, error }, { data: weeklySchedule, error: scheduleError }] = await Promise.all([
          supabase
            .from('merchants')
            .select('id, name, is_open, open_time, close_time')
            .in('id', ids),
          supabase
            .from('merchant_operating_hours')
            .select('merchant_id, day_of_week, open_time, close_time, is_closed')
            .in('merchant_id', ids),
        ]);

        if (error) throw error;
        if (scheduleError) throw scheduleError;

        if (data && !cancelled) {
          const info: Record<string, MerchantOperatingInfo> = {};
          data.forEach(m => {
            info[m.id] = {
              id: m.id,
              name: m.name,
              isOpen: m.is_open,
              openTime: m.open_time,
              closeTime: m.close_time,
              weeklySchedule: (weeklySchedule ?? [])
                .filter(schedule => schedule.merchant_id === m.id)
                .map(({ merchant_id: _merchantId, ...schedule }) => schedule),
            };
          });
          setMerchantOperatingInfo(info);
        }
      } catch (error) {
        console.error('Error loading merchant operating hours:', error);
        if (!cancelled) setOperatingHoursError(error instanceof Error ? error : new Error('Gagal memeriksa jam toko'));
      } finally {
        if (!cancelled) setOperatingHoursLoading(false);
      }
    };

    loadMerchantOperatingHours();
    return () => { cancelled = true; };
  }, [merchantIdsKey]);

  // Get closed merchants
  const closedMerchants = useMemo(() => {
    return Object.values(merchantOperatingInfo).filter(m => {
      const status = getMerchantOperatingStatus(m.isOpen, m.openTime, m.closeTime, m.weeklySchedule);
      return !status.isCurrentlyOpen;
    });
  }, [merchantOperatingInfo]);

  const allMerchantsOpen = !operatingHoursError && closedMerchants.length === 0;

  const hasCompleteDeliveryAddress = Boolean(
    addressData.address.province &&
    addressData.address.city &&
    addressData.address.district &&
    addressData.address.village,
  );
  const hasValidDeliveryLocation = Boolean(
    addressData.location &&
    Number.isFinite(addressData.location.lat) &&
    Number.isFinite(addressData.location.lng),
  );
  const isDeliveryReady = deliveryType === 'PICKUP' || (hasCompleteDeliveryAddress && hasValidDeliveryLocation);

  // Remove items from a specific merchant
  const handleRemoveMerchantItems = (merchantId: string) => {
    const merchantItems = itemsByMerchant[merchantId]?.items || [];
    merchantItems.forEach(item => {
      removeFromCart(item.product.id);
    });
    toast({
      title: 'Produk dihapus',
      description: `Produk dari ${itemsByMerchant[merchantId]?.merchantName || 'toko'} telah dihapus dari keranjang`,
    });
  };

  const validateForm = (): boolean => {
    const newErrors: Record<string, string> = {};

    if (!addressData.name || addressData.name.trim().length < 2) {
      newErrors.name = 'Nama minimal 2 karakter';
    }

    if (!addressData.phone || !validatePhone(addressData.phone).isValid) {
      newErrors.phone = 'Nomor telepon tidak valid';
    }

    // Only validate address fields for delivery, not pickup
    if (deliveryType !== 'PICKUP') {
      if (!addressData.address.province) {
        newErrors.address = 'Pilih provinsi';
      } else if (!addressData.address.city) {
        newErrors.address = 'Pilih kota/kabupaten';
      } else if (!addressData.address.district) {
        newErrors.address = 'Pilih kecamatan';
      } else if (!addressData.address.village) {
        newErrors.address = 'Pilih kelurahan/desa';
      }
    }

    // Only require map location for delivery, not pickup
    if (deliveryType !== 'PICKUP' && !addressData.location) {
      newErrors.location = 'Tentukan titik lokasi pengiriman di peta';
    }

    if (deliveryType === 'INTERNAL' && deliveryRestriction.requiresExpedition) {
      newErrors.delivery = 'Alamat ini wajib menggunakan ekspedisi.';
    }

    if (Object.keys(newErrors).length > 0) {
      console.warn('Validation failed:', newErrors);
      // Scroll to the first error
      const firstErrorField = Object.keys(newErrors)[0];
      const element = document.getElementById(`error-${firstErrorField}`);
      if (element) {
        element.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (items.length === 0) {
      toast({
        title: 'Keranjang kosong',
        variant: 'destructive',
      });
      return;
    }

    // Checkout currently creates one order and one payment flow. Do not create
    // partial child orders for a cart containing multiple merchants.
    if (merchantIds.length > 1) {
      toast({
        title: 'Checkout hanya untuk satu toko',
        description: 'Pisahkan produk berdasarkan toko sebelum checkout.',
        variant: 'destructive',
      });
      return;
    }

    // Check if any merchant is closed
    if (!allMerchantsOpen) {
      const closedNames = closedMerchants.map(m => m.name).join(', ');
      toast({
        title: 'Toko sedang tutup',
        description: `${closedNames} sedang tidak menerima pesanan`,
        variant: 'destructive',
      });
      return;
    }

    if (!validateForm()) {
      toast({
        title: 'Data belum lengkap',
        description: 'Silakan lengkapi form checkout',
        variant: 'destructive',
      });
      // Scroll to first error
      setTimeout(() => {
        document.querySelector('.text-destructive')?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }, 100);
      return;
    }

    if (deliveryType !== 'PICKUP' && !await requestRequiredLocation()) {
      toast({ title: 'GPS wajib diaktifkan', description: 'Aktifkan Lokasi untuk menghitung alamat dan melanjutkan pengiriman.', variant: 'destructive' });
      return;
    }

    setLoading(true);

    try {
      checkoutKeyRef.current ??= crypto.randomUUID();
      // Validate stock before creating orders
      const allProductIds = items.flatMap(item => [item.product.id, ...(item.toppings || []).map(topping => topping.product.id)]);
      const { data: currentStocks, error: stockCheckError } = await supabase
        .from('products')
        .select('id, name, stock')
        .in('id', allProductIds);

      if (stockCheckError) {
        throw new Error('Gagal memeriksa stok produk');
      }

      const stockMap = new Map((currentStocks ?? []).map((product) => [product.id, product]));
      const outOfStockItems: string[] = [];
      const demand = getCartStockDemand(items);
      for (const [productId, requested] of demand) {
        const product = stockMap.get(productId);
        if (!product || product.stock < requested) {
          const cartItem = items.find((item) => item.product.id === productId);
          const topping = items.flatMap((item) => item.toppings || []).find((candidate) => candidate.product.id === productId);
          const productName = product?.name || cartItem?.product.name || topping?.product.name || 'Produk';
          outOfStockItems.push(`${productName} (tersisa: ${product?.stock ?? 0}, diminta: ${requested})`);
        }
      }

      if (outOfStockItems.length > 0) {
        setLoading(false);
        toast({
          title: 'Stok tidak mencukupi',
          description: outOfStockItems.join(', '),
          variant: 'destructive',
        });
        return;
      }

      const fullAddress = formatFullAddress(addressData.address);
      const checkoutPayload = {
        p_items: items.flatMap((item) => [
          { product_id: item.product.id, quantity: Math.trunc(item.quantity) },
          ...(item.toppings || []).map((topping) => ({ product_id: topping.product.id, quantity: Math.trunc(item.quantity * topping.quantity) })),
        ]),
        p_delivery: {
          name: addressData.name,
          phone: addressData.phone,
          address: fullAddress,
          lat: addressData.location?.lat ?? null,
          lng: addressData.location?.lng ?? null,
          province_id: addressData.address.province || null,
          province_name: addressData.address.provinceName || null,
          city_id: addressData.address.city || null,
          city_name: addressData.address.cityName || null,
          district_id: addressData.address.district || null,
          district_name: addressData.address.districtName || null,
          notes: notes || null,
        },
        p_delivery_type: deliveryType,
        p_payment_method: paymentMethod,
        p_voucher_id: user ? appliedVoucher?.id ?? null : null,
        p_distance_km: null,
        p_checkout_key: checkoutKeyRef.current,
        ...(user ? {} : { p_guest_checkout_key: guestSessionKeyRef.current ?? getGuestCheckoutSessionKey() }),
      };
      const { data: checkoutResult, error: checkoutError } = await supabase.rpc(
        (user ? 'create_marketplace_checkout' : 'create_guest_marketplace_checkout') as never,
        checkoutPayload as never,
      );
      if (checkoutError) {
        console.error('Authoritative checkout error:', checkoutError);
        throw new Error(checkoutError.message || 'Checkout gagal divalidasi server');
      }

      const typedCheckoutResult = checkoutResult as { primary_order_id?: string; order_ids?: string[]; guest_access_token?: string; guest_token_expires_at?: string } | null;
      const authoritativeOrderId = typedCheckoutResult?.primary_order_id;
      if (!authoritativeOrderId) throw new Error('Checkout tidak menghasilkan order');
      if (!user) {
        if (!typedCheckoutResult.guest_access_token || !typedCheckoutResult.guest_token_expires_at) throw new Error('Token akses guest tidak diterima');
        setGuestToken(typedCheckoutResult.guest_access_token);
        rememberGuestOrderAccess({
          orderIds: typedCheckoutResult.order_ids?.length ? typedCheckoutResult.order_ids : [authoritativeOrderId],
          token: typedCheckoutResult.guest_access_token,
          expiresAt: typedCheckoutResult.guest_token_expires_at,
        });
      }
      let paymentNeedsRecovery = false;

      if (user && paymentMethod === 'ONLINE' && xenditAvailable) {
        try {
          const invoice = await createPaymentInvoice({ orderId: authoritativeOrderId });
          window.location.href = invoice.invoice_url;
          return;
        } catch (paymentError) {
          console.error('Payment error:', paymentError);
          toast({
            title: 'Invoice belum berhasil dibuat',
            description: 'Pesanan tersimpan dan Anda dapat mencoba pembayaran lagi.',
            variant: 'destructive',
          });
          paymentNeedsRecovery = true;
          setPaymentRecoveryError(true);
        }
      }

      selectedItems.forEach(item => removeFromCart(item.product.id));
      checkoutKeyRef.current = null;
      if (paymentMethod === 'TRANSFER') {
        navigate(user ? `/payment/${authoritativeOrderId}` : guestOrderUrl(authoritativeOrderId, typedCheckoutResult?.guest_access_token || guestToken || '', 'payment'));
        return;
      }
      setOrderId(authoritativeOrderId);
      setSuccess(true);
      toast({
        title: paymentNeedsRecovery ? 'Pesanan dibuat, pembayaran tertunda' : 'Pesanan berhasil dibuat!',
        description: paymentNeedsRecovery
            ? 'Gunakan tombol coba lagi untuk membuat invoice pembayaran.'
            : 'Pesanan Anda telah masuk ke sistem',
      });
      return;

      } catch (error: unknown) {
      console.error('Checkout error:', error);

      // Extract more specific error message
      let errorMessage = 'Terjadi kesalahan, silakan coba lagi';
      const rawMessage = error instanceof Error ? error.message : '';
      if (rawMessage) {
        if (rawMessage.includes('violates row-level security')) {
          errorMessage = user
            ? 'Anda tidak memiliki izin untuk membuat pesanan. Silakan coba lagi.'
            : 'Checkout guest tidak dapat diproses. Periksa data pesanan lalu coba lagi.';
        } else if (rawMessage.includes('violates foreign key')) {
          errorMessage = 'Data merchant atau produk tidak valid.';
        } else if (rawMessage.includes('null value')) {
          errorMessage = 'Data belum lengkap. Pastikan semua field terisi.';
        } else {
          errorMessage = rawMessage;
        }
      }

      toast({
        title: 'Gagal membuat pesanan',
        description: errorMessage,
        variant: 'destructive',
      });
    } finally {
      setLoading(false);
    }
  };

  if (success) {
    const retryPayment = async () => {
      if (!orderId || retryingPayment) return;
      setRetryingPayment(true);
      try {
        const invoice = await createPaymentInvoice({ orderId });
        window.location.href = invoice.invoice_url;
      } catch (error) {
        console.error('Payment retry error:', error);
        toast({
          title: 'Invoice belum berhasil dibuat',
          description: 'Silakan coba lagi beberapa saat lagi.',
          variant: 'destructive',
        });
      } finally {
        setRetryingPayment(false);
      }
    };
    return (
      <div className="mobile-shell bg-background flex flex-col min-h-screen items-center justify-center p-8">
        <motion.div
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          className="text-center"
        >
          <div className={`w-20 h-20 rounded-full flex items-center justify-center mx-auto mb-4 ${paymentRecoveryError ? 'bg-amber-100' : 'bg-primary/10'}`}>
            <CheckCircle className={`h-10 w-10 ${paymentRecoveryError ? 'text-amber-600' : 'text-primary'}`} />
          </div>
          <h1 className="text-2xl font-bold text-foreground mb-2">
            {paymentRecoveryError ? 'Pesanan Dibuat, Pembayaran Tertunda' : 'Pesanan Berhasil!'}
          </h1>
          <p className="text-muted-foreground mb-6">
            {paymentRecoveryError
              ? 'Order sudah tersimpan dan stok diamankan sementara. Invoice online belum berhasil dibuat.'
              : 'Pesanan Anda telah masuk ke sistem dan sedang menunggu konfirmasi dari penjual.'}
          </p>
          <div className="space-y-3">
            {paymentRecoveryError && (
              <Button onClick={retryPayment} className="w-full" disabled={retryingPayment}>
                {retryingPayment ? 'Mencoba membuat invoice...' : 'Coba Bayar Lagi'}
              </Button>
            )}
            <Button onClick={() => navigate(user ? '/orders' : (orderId && guestToken ? guestOrderUrl(orderId, guestToken) : '/'))} className="w-full">
              {user ? 'Lihat Pesanan Saya' : 'Lihat Status Pesanan'}
            </Button>
            <Button onClick={() => navigate('/')} variant="outline" className="w-full">
              Lanjut Belanja
            </Button>
          </div>
        </motion.div>
      </div>
    );
  }

  return (
    <div className="mobile-shell bg-secondary flex flex-col min-h-screen">
      {/* Sticky Header & Step Indicator */}
      <div className="sticky top-0 z-50 bg-card shadow-sm">
        {/* Header */}
        <div className="p-4 border-b border-border flex items-center gap-3">
          <button
            onClick={() => safeGoBack(navigate)}
            className="w-8 h-8 rounded-full hover:bg-secondary flex items-center justify-center"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>
          <h2 className="font-bold text-lg text-foreground">
            Checkout
            {items.length > 0 && (
              <Badge variant="secondary" className="ml-2 text-xs">{items.length} item</Badge>
            )}
          </h2>
        </div>

        {/* Step Indicator */}
        <div className="px-4 pt-3 pb-1 border-b border-border">
          <div className="flex items-center justify-between">
            {[
              { icon: Package, label: 'Pesanan', done: items.length > 0 },
              { icon: MapPin, label: 'Alamat', done: !!(addressData.address.province && addressData.address.city && addressData.address.district) },
              { icon: Truck, label: 'Pengiriman', done: true },
              { icon: CreditCard, label: 'Bayar', done: !!paymentMethod },
            ].map((step, i) => (
              <div key={step.label} className="flex items-center">
                <div className="flex flex-col items-center gap-0.5">
                  <div className={`w-7 h-7 rounded-full flex items-center justify-center transition-colors ${
                    step.done
                      ? 'bg-primary text-primary-foreground'
                      : 'bg-muted text-muted-foreground'
                  }`}>
                    {step.done ? (
                      <CheckCircle className="h-3.5 w-3.5" />
                    ) : (
                      <step.icon className="h-3.5 w-3.5" />
                    )}
                  </div>
                  <span className={`text-[9px] font-medium ${step.done ? 'text-primary' : 'text-muted-foreground'}`}>{step.label}</span>
                </div>
                {i < 3 && <div className={`w-6 h-px mx-1 mb-4 ${step.done ? 'bg-primary' : 'bg-border'}`} />}
              </div>
            ))}
          </div>
        </div>
      </div>

      <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto p-4 pb-56">
        {/* Closed Merchants Alert */}
        {!operatingHoursLoading && closedMerchants.length > 0 && (
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            className="bg-destructive/10 border border-destructive/20 rounded-xl p-4 mb-4"
          >
            <div className="flex items-start gap-3">
              <div className="w-10 h-10 rounded-full bg-destructive/20 flex items-center justify-center flex-shrink-0">
                <Clock className="h-5 w-5 text-destructive" />
              </div>
              <div className="flex-1">
                <h4 className="font-bold text-destructive text-sm mb-1">
                  Beberapa toko sedang tutup
                </h4>
                <div className="space-y-2">
                  {closedMerchants.map(m => {
                    const status = getMerchantOperatingStatus(m.isOpen, m.openTime, m.closeTime, m.weeklySchedule);
                    return (
                      <div key={m.id} className="flex items-center justify-between">
                        <div>
                          <p className="text-sm font-medium text-foreground">{m.name}</p>
                          <p className="text-xs text-muted-foreground">{status.reason}</p>
                        </div>
                        <Button
                          type="button"
                          variant="outline"
                          size="sm"
                          onClick={() => handleRemoveMerchantItems(m.id)}
                          className="text-xs"
                        >
                          Hapus
                        </Button>
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>
          </motion.div>
        )}

        {/* Loading store availability check */}
        {operatingHoursLoading && (
          <div className="bg-muted/50 rounded-lg p-4 mb-4 flex items-center justify-center gap-2">
            <Loader2 className="h-4 w-4 animate-spin" />
            <span className="text-sm text-muted-foreground">Memeriksa ketersediaan toko...</span>
          </div>
        )}

        {operatingHoursError && !operatingHoursLoading && (
          <div className="bg-destructive/10 border border-destructive/20 rounded-xl p-4 mb-4 text-sm text-destructive">
            Ketersediaan toko belum dapat diverifikasi. Periksa koneksi Anda lalu muat ulang halaman sebelum melanjutkan checkout.
          </div>
        )}

        {/* Order Summary - moved to top */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="bg-card rounded-xl p-4 border border-border shadow-sm mb-4"
        >
          <div className="flex items-center gap-2 mb-4">
            <Package className="h-5 w-5 text-primary" />
            <h3 className="font-bold text-foreground">Ringkasan Pesanan</h3>
            <Badge variant="secondary" className="text-xs ml-auto">{items.length} produk</Badge>
          </div>

          <div className="space-y-3">
            {items.map(item => (
              <div key={item.product.id} className="flex gap-3">
                <img
                  src={item.product.image}
                  alt={item.product.name}
                  className="w-12 h-12 rounded-lg object-cover"
                />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium line-clamp-1">{item.product.name}</p>
                  <p className="text-xs text-muted-foreground">{item.quantity}x {formatPrice(item.product.price)}</p>
                </div>
                <p className="text-sm font-bold">{formatPrice(item.product.price * item.quantity)}</p>
              </div>
            ))}
          </div>
        </motion.div>

        {/* Delivery Address */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.05 }}
          className="bg-card rounded-xl p-4 border border-border shadow-sm mb-4"
        >
          <div className="flex items-center gap-2 mb-4">
            <MapPin className="h-5 w-5 text-primary" />
            <h3 className="font-bold text-foreground">Alamat Pengiriman</h3>
          </div>

          <CheckoutAddressForm
            value={addressData}
            onChange={setAddressData}
            onDistanceChange={setDistanceKm}
            merchantLocation={merchantLocation}
            errors={errors}
            hideMap={deliveryType === 'PICKUP'}
          />
        </motion.div>

        {/* Distance & ETA Info */}
        {distanceKm !== null && deliveryType !== 'PICKUP' && (
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            className="bg-muted/50 rounded-lg p-3 mb-4 space-y-1"
          >
            <div className="flex items-center gap-2">
              <MapPin className="h-4 w-4 text-muted-foreground" />
              <span className="text-sm text-muted-foreground">
                {t('shipping.distanceLabel')}: <span className="font-medium text-foreground">{distanceKm.toFixed(1)} KM</span>
              </span>
            </div>
            <div className="flex items-center gap-2">
              <Clock className="h-4 w-4 text-muted-foreground" />
              <span className="text-sm text-muted-foreground">
                {t('shipping.etaLabel')}: <span className="font-medium text-foreground">
                  {(() => {
                    const etaMin = Math.ceil((distanceKm / 25) * 60 * 1.2);
                    const variance = Math.max(5, Math.ceil(etaMin * 0.2));
                    const min = Math.max(1, etaMin - variance);
                    const max = etaMin + variance;
                    return max < 60
                      ? t('shipping.etaMinutes', { min, max })
                      : t('shipping.etaHours', { min: Math.floor(min / 60), max: Math.ceil(max / 60) });
                  })()}
                </span>
              </span>
            </div>
          </motion.div>
        )}

        {deliveryType !== 'PICKUP' && deliveryRestriction.requiresExpedition && (
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            className="bg-amber-50 border border-amber-200 rounded-lg p-3 mb-4"
            role="status"
          >
            <div className="flex items-start gap-2">
              <AlertTriangle className="h-4 w-4 text-amber-600 mt-0.5 flex-shrink-0" />
              <div className="text-sm">
                <p className="font-semibold text-amber-900">Alamat ini wajib menggunakan ekspedisi</p>
                <p className="text-xs text-amber-800 mt-1">
                  Ojek/kurir lokal hanya tersedia sampai {MAX_LOCAL_DELIVERY_DISTANCE_KM} km dan dalam kecamatan serta kabupaten/kota yang sama.
                </p>
                <p className="text-xs text-amber-800 mt-1">
                  Alasan: {deliveryRestriction.reasons.join(' dan ')}.
                </p>
              </div>
            </div>
          </motion.div>
        )}

        {/* Delivery Method */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1 }}
          className="bg-card rounded-xl p-4 border border-border shadow-sm mb-4"
        >
          <div className="flex items-center gap-2 mb-4">
            <Truck className="h-5 w-5 text-primary" />
            <h3 className="font-bold text-foreground">{t('shipping.method')}</h3>
          </div>

          <RadioGroup
            value={deliveryType}
            onValueChange={(value) => setDeliveryType(value as 'PICKUP' | 'INTERNAL' | 'EXPEDITION')}
            className="space-y-2"
          >
            <label className={`flex items-center gap-3 p-3 border rounded-lg cursor-pointer transition ${
              deliveryType === 'INTERNAL' ? 'border-primary bg-primary/5' : 'border-border'
            } ${deliveryRestriction.requiresExpedition ? 'opacity-60 cursor-not-allowed' : ''}`}>
              <RadioGroupItem value="INTERNAL" id="internal" disabled={deliveryRestriction.requiresExpedition} />
              <div className="flex-1">
                <p className="font-bold text-sm">{t('shipping.delivery')}</p>
                <p className="text-xs text-muted-foreground">
                  {deliveryRestriction.requiresExpedition
                    ? 'Tidak tersedia untuk alamat di luar jangkauan kurir lokal'
                    : t('shipping.deliveryDesc')}
                </p>
              </div>
              <span className="text-sm font-bold text-primary">{formatCurrency(shippingCost)}</span>
            </label>

            <label className={`flex items-center gap-3 p-3 border rounded-lg cursor-pointer transition ${
              deliveryType === 'EXPEDITION' ? 'border-primary bg-primary/5' : 'border-border'
            }`}>
              <RadioGroupItem value="EXPEDITION" id="expedition" />
              <div className="flex-1">
                <p className="font-bold text-sm">Ekspedisi</p>
                <p className="text-xs text-muted-foreground">
                  Untuk jarak lebih dari {MAX_LOCAL_DELIVERY_DISTANCE_KM} km atau beda kecamatan/kabupaten
                </p>
              </div>
              <span className="text-sm font-bold text-primary">{formatCurrency(shippingCost)}</span>
            </label>

            <label className={`flex items-center gap-3 p-3 border rounded-lg cursor-pointer transition ${
              deliveryType === 'PICKUP' ? 'border-primary bg-primary/5' : 'border-border'
            }`}>
              <RadioGroupItem value="PICKUP" id="pickup" />
              <div className="flex-1">
                <p className="font-bold text-sm">{t('shipping.pickup')}</p>
                <p className="text-xs text-muted-foreground">{t('shipping.pickupDesc')}</p>
              </div>
              <span className="text-sm font-bold text-primary">{t('shipping.freeLabel')}</span>
            </label>
          </RadioGroup>
          {errors.delivery && (
            <p className="text-xs text-destructive mt-2" role="alert">{errors.delivery}</p>
          )}
        </motion.div>

        {/* Payment Method */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.15 }}
          className="bg-card rounded-xl p-4 border border-border shadow-sm mb-4"
        >
          <div className="flex items-center gap-2 mb-4">
            <CreditCard className="h-5 w-5 text-primary" />
            <h3 className="font-bold text-foreground">Metode Pembayaran</h3>
          </div>

          <RadioGroup
            value={paymentMethod}
            onValueChange={(value) => setPaymentMethod(value as PaymentMethod)}
            className="space-y-2"
          >
            {/* Transfer Option - Based on merchant settings */}
            {(!user || merchantPaymentSettings?.transferEnabled !== false) && (
              <label className={`flex items-center gap-3 p-3 border rounded-lg cursor-pointer transition ${
                paymentMethod === 'TRANSFER' ? 'border-primary bg-primary/5' : 'border-border'
              } ${merchantIds.length > 1 ? 'opacity-50 cursor-not-allowed' : ''}`}>
                <RadioGroupItem value="TRANSFER" id="transfer" disabled={merchantIds.length > 1} />
                <CreditCard className="h-5 w-5 text-muted-foreground" />
                <div className="flex-1">
                  <p className="font-bold text-sm">Transfer Bank</p>
                  <p className="text-xs text-muted-foreground">
                    {merchantIds.length > 1
                      ? 'Tersedia untuk checkout satu toko saja'
                      : merchantPaymentSettings?.bankName
                      ? `Transfer ke ${merchantPaymentSettings.bankName}`
                      : 'Transfer ke rekening penjual'}
                  </p>
                </div>
              </label>
            )}

            {/* Online Payment via Xendit */}
            {user && xenditAvailable && (
              <label className={`flex items-center gap-3 p-3 border rounded-lg cursor-pointer transition ${
                paymentMethod === 'ONLINE' ? 'border-primary bg-primary/5' : 'border-border'
              } ${merchantIds.length > 1 ? 'opacity-50 cursor-not-allowed' : ''}`}>
                <RadioGroupItem value="ONLINE" id="online" disabled={merchantIds.length > 1} />
                <CreditCard className="h-5 w-5 text-muted-foreground" />
                <div className="flex-1">
                  <p className="font-bold text-sm">Bayar Online</p>
                  <p className="text-xs text-muted-foreground">QRIS, Transfer Bank, E-Wallet</p>
                </div>
              </label>
            )}
          </RadioGroup>

          {/* Bank Transfer Info */}
          {paymentMethod === 'TRANSFER' && merchantPaymentSettings?.bankName && (
            <div className="mt-3 p-3 bg-secondary/50 rounded-lg space-y-1">
              <p className="text-xs font-medium text-foreground">Informasi Rekening:</p>
              <p className="text-sm font-bold">{merchantPaymentSettings.bankName}</p>
              <p className="text-sm font-mono">{merchantPaymentSettings.bankAccountNumber}</p>
              <p className="text-xs text-muted-foreground">a.n. {merchantPaymentSettings.bankAccountName}</p>
            </div>
          )}

          {/* QRIS Info */}
          {paymentMethod === 'TRANSFER' && merchantPaymentSettings?.qrisImageUrl && (
            <div className="mt-3 p-3 bg-secondary/50 rounded-lg">
              <p className="text-xs font-medium text-foreground mb-2">QRIS:</p>
              <div className="flex justify-center p-2 bg-card rounded border">
                <img
                  src={merchantPaymentSettings.qrisImageUrl}
                  alt="QRIS"
                  className="max-w-[200px] w-full h-auto"
                />
              </div>
            </div>
          )}

        </motion.div>

        {/* Order Summary moved to top of form */}

        {/* Voucher */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.25 }}
          className="bg-card rounded-xl p-4 border border-border shadow-sm mb-4"
        >
          {!user ? (
            <p className="text-sm text-muted-foreground">Voucher akun dan diskon tersimpan hanya tersedia setelah login.</p>
          ) : merchantIds.length > 1 ? (
            <p className="text-sm text-muted-foreground">Voucher hanya dapat digunakan untuk checkout satu toko.</p>
          ) : (
            <VoucherInput
              orderTotal={subtotal}
              merchantId={merchantIds[0]}
              onVoucherApplied={(discount, voucherId, voucherName) => {
                setAppliedVoucher({ id: voucherId, name: voucherName, discount });
              }}
              onVoucherRemoved={() => setAppliedVoucher(null)}
              appliedVoucher={appliedVoucher}
            />
          )}
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3 }}
          className="bg-card rounded-xl p-4 border border-border shadow-sm"
        >
          <Label htmlFor="notes">Catatan (opsional)</Label>
          <Textarea
            id="notes"
            placeholder="Catatan untuk penjual..."
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={2}
            className="mt-2"
          />
        </motion.div>
      </form>

      {/* Checkout Summary */}
      <div className="mobile-action-safe fixed bottom-0 left-0 right-0 max-w-[480px] mx-auto bg-card border-t border-border p-5 shadow-lg">
        {/* Free shipping badge */}
        {shippingSettings && subtotal >= shippingSettings.free_shipping_min_order && deliveryType !== 'PICKUP' && (
          <div className="flex items-center gap-1.5 mb-2 text-xs text-emerald-600 font-medium">
            <CheckCircle className="h-3.5 w-3.5" />
            <span>{t('shipping.freeMinOrder', { min: formatCurrency(shippingSettings.free_shipping_min_order) })}</span>
          </div>
        )}
        <div className="flex justify-between items-center mb-1 text-sm">
          <span className="text-muted-foreground">{t('shipping.subtotal')}</span>
          <span className="font-bold">{formatCurrency(subtotal)}</span>
        </div>
        <div className="flex justify-between items-center mb-1 text-sm">
          <span className="text-muted-foreground">{t('shipping.fee')}</span>
          <span className="font-bold">{formatCurrency(shippingCost)}</span>
        </div>
        {voucherDiscount > 0 && (
          <div className="flex justify-between items-center mb-1 text-sm">
            <span className="text-primary">{t('shipping.voucherDiscount')}</span>
            <span className="font-bold text-primary">-{formatCurrency(voucherDiscount)}</span>
          </div>
        )}
        <div className="flex justify-between items-center mb-3 pt-3 border-t border-border">
          <span className="text-lg font-bold">{t('shipping.total')}</span>
          <span className="text-xl font-bold text-primary">{formatCurrency(total)}</span>
        </div>
        {/* Payment method label */}
        <div className="flex items-center gap-1.5 mb-3 text-xs text-muted-foreground">
          <CreditCard className="h-3.5 w-3.5" />
          <span>
            {t('shipping.payVia')}: <span className="font-medium text-foreground">
              {paymentMethod === 'TRANSFER' ? 'Transfer Bank' : 'Online Payment'}
            </span>
          </span>
        </div>
        <Button
          type="submit"
          onClick={handleSubmit}
          className={`w-full shadow-brand font-bold transition-all ${
            !loading && items.length > 0 && allMerchantsOpen ? 'animate-pulse hover:animate-none' : ''
          }`}
          size="lg"
          disabled={loading || items.length === 0 || merchantIds.length > 1 || operatingHoursLoading || !allMerchantsOpen || !isDeliveryReady || (!user && (guestCheckoutFlagLoading || !guestCheckoutEnabled))}
        >
          {loading ? (
            <>
              <Loader2 className="h-4 w-4 mr-2 animate-spin" />
              Memproses...
            </>
          ) : operatingHoursLoading ? (
            <>
              <Loader2 className="h-4 w-4 mr-2 animate-spin" />
              Memeriksa Toko...
            </>
          ) : operatingHoursError ? (
            'Ketersediaan Belum Terverifikasi'
          ) : !allMerchantsOpen ? (
            <>
              <Clock className="h-4 w-4 mr-2" />
              Ada Toko Tutup
            </>
          ) : (
            user ? 'Pesan' : 'Pesan tanpa Login'
          )}
        </Button>
        {!isDeliveryReady && (
          <p className="mt-2 text-center text-xs text-muted-foreground">
            Pilih alamat pengiriman dan tentukan titik lokasi di peta untuk melanjutkan.
          </p>
        )}
      </div>
    </div>
  );
}
