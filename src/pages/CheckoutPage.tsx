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
import { createGdcQrisPayment } from '@/lib/gdcQrisApi';
import { CheckoutAddressForm, type CheckoutAddressData } from '@/components/checkout/CheckoutAddressForm';
import { createEmptyCheckoutAddress } from '@/components/checkout/checkoutAddressDefaults';
import { formatFullAddress } from '@/components/AddressSelector';
import { validatePhone } from '@/lib/phoneValidation';
import { getMerchantOperatingStatus, formatTime, type OperatingDaySchedule } from '@/lib/merchantOperatingHours';
import { getDeliveryRestriction, MAX_LOCAL_DELIVERY_DISTANCE_KM } from '@/lib/deliveryRestriction';
import { getGuestCheckoutSessionKey, guestOrderUrl, rememberGuestOrderAccess } from '@/lib/guestCheckout';
import { useGuestCheckoutEnabled } from '@/hooks/useGuestCheckoutEnabled';
import { getCartStockDemand } from '@/lib/productAvailability';
import { getCartItemSubtotal, getCartItemsSubtotal } from '@/lib/cartPricing';
import { isCheckoutPaymentMethodAvailable, isCheckoutPaymentSettingsReady, type CheckoutPaymentSettingsStatus } from '@/lib/checkoutPaymentReadiness';
import { normalizeCheckoutProductQuantities } from '@/lib/normalizeCheckoutItems';
import { getCheckoutMerchantIds, hasMultipleCheckoutMerchants } from '@/lib/cartSelection';
import { getCartItemKey } from '@/lib/cartItemIdentity';
import { getOptimizedImageSrcSet, optimizeSupabaseImage } from '@/components/ui/OptimizedImage';

type PaymentMethod = 'TRANSFER' | 'ONLINE' | 'QRIS_DYNAMIC';

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

interface ShippingZoneEstimate {
  name: string;
  max_distance_km: number;
  fee: number;
}

interface MarketplaceCheckoutQuote {
  subtotal: number;
  shipping_cost: number;
  voucher_discount: number;
  total: number;
  distance_km: number;
  quoted_at: string;
  line_items?: Array<{
    product_id: string;
    product_name: string;
    quantity: number;
    unit_price: number;
    line_subtotal: number;
  }>;
  shipping_contract?: {
    contract: string;
    provider_name?: string;
    service_name?: string;
    weight_kg?: number;
    eta_min_days?: number;
    eta_max_days?: number;
  };
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
  // The first available options are visibly selected by default, so the step
  // indicator and CTA should not pretend the buyer still needs to choose them.
  const [hasChosenDelivery, setHasChosenDelivery] = useState(true);
  const [hasChosenPayment, setHasChosenPayment] = useState(true);
  const [xenditAvailable, setXenditAvailable] = useState(false);
  const [gdcAvailable, setGdcAvailable] = useState(false);
  const [onlineProvider, setOnlineProvider] = useState<'XENDIT' | 'GDC'>('XENDIT');
  const [paymentRecoveryError, setPaymentRecoveryError] = useState(false);
  const [paymentRecoveryProvider, setPaymentRecoveryProvider] = useState<'XENDIT' | 'GDC'>('XENDIT');
  const [retryingPayment, setRetryingPayment] = useState(false);
  const [stockConflict, setStockConflict] = useState<string | null>(null);
  const [notes, setNotes] = useState('');
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [appliedVoucher, setAppliedVoucher] = useState<{ id: string; name: string; discount: number } | null>(null);
  // Keep the same key while a checkout attempt is retried after a timeout or
  // invoice-provider failure. The database then returns the original order.
  const checkoutKeyRef = useRef<string | null>(null);
  const guestSessionKeyRef = useRef<string | null>(null);
  const checkoutSummaryRef = useRef<HTMLDivElement | null>(null);
  const [checkoutSummaryHeight, setCheckoutSummaryHeight] = useState(0);

  useEffect(() => {
    const summary = checkoutSummaryRef.current;
    if (!summary) return;

    const measureSummary = () => {
      setCheckoutSummaryHeight(Math.ceil(summary.getBoundingClientRect().height));
    };
    measureSummary();

    if (typeof ResizeObserver === 'undefined') {
      window.addEventListener('resize', measureSummary);
      return () => window.removeEventListener('resize', measureSummary);
    }

    const observer = new ResizeObserver(measureSummary);
    observer.observe(summary);
    return () => observer.disconnect();
  }, [items.length]);

  // Address state
  const [addressData, setAddressData] = useState<CheckoutAddressData>(createEmptyCheckoutAddress());

  // Distance state
  const [distanceKm, setDistanceKm] = useState<number | null>(null);
  const [distanceSource, setDistanceSource] = useState<'google' | 'fallback' | 'straight-line' | 'calculating' | null>(null);
  const [checkoutQuoteResult, setCheckoutQuoteResult] = useState<{ key: string; quote: MarketplaceCheckoutQuote } | null>(null);
  const [checkoutQuoteLoading, setCheckoutQuoteLoading] = useState(false);
  const [checkoutQuoteError, setCheckoutQuoteError] = useState<string | null>(null);
  const [quoteRetryNonce, setQuoteRetryNonce] = useState(0);

  // Shipping settings from admin
  const [shippingSettings, setShippingSettings] = useState<{ base_fee: number; per_km_fee: number; min_fee: number; max_fee: number; free_shipping_min_order: number } | null>(null);
  const [shippingZones, setShippingZones] = useState<ShippingZoneEstimate[]>([]);
  // Merchant payment settings
  const [merchantPaymentSettings, setMerchantPaymentSettings] = useState<MerchantPaymentSettings & { qrisImageUrl: string | null } | null>(null);
  const [paymentSettingsLoadState, setPaymentSettingsLoadState] = useState<{
    merchantId: string | null;
    status: CheckoutPaymentSettingsStatus;
  }>({ merchantId: null, status: 'loading' });

  useEffect(() => {
    if (!user && !guestCheckoutFlagLoading && !guestCheckoutEnabled) {
      navigate('/auth', { replace: true });
    }
  }, [guestCheckoutEnabled, guestCheckoutFlagLoading, navigate, user]);

  // Check if Xendit is enabled
  useEffect(() => {
    isXenditEnabled().then(setXenditAvailable);
    if (!user) guestSessionKeyRef.current = getGuestCheckoutSessionKey();
    // Load the distance formula and the optional difficult-road zone surcharge.
    supabase.from('app_settings').select('key, value').in('key', ['shipping_base_fee', 'shipping_zones']).then(({ data }) => {
      const settings = (data || []) as Array<{ key: string; value: unknown }>;
      const baseSetting = settings.find((setting) => setting.key === 'shipping_base_fee')?.value;
      if (baseSetting && typeof baseSetting === 'object') {
        const v = baseSetting as Record<string, number>;
        setShippingSettings({
          base_fee: v.base_fee ?? 5000,
          per_km_fee: v.per_km_fee ?? 2000,
          min_fee: v.min_fee ?? 5000,
          max_fee: v.max_fee ?? 50000,
          free_shipping_min_order: v.free_shipping_min_order ?? 100000,
        });
      }
      const zoneSetting = settings.find((setting) => setting.key === 'shipping_zones')?.value;
      if (zoneSetting && typeof zoneSetting === 'object' && Array.isArray((zoneSetting as { zones?: unknown }).zones)) {
        setShippingZones(((zoneSetting as { zones: unknown[] }).zones).filter((zone): zone is ShippingZoneEstimate => {
          if (!zone || typeof zone !== 'object') return false;
          const candidate = zone as Partial<ShippingZoneEstimate>;
          return typeof candidate.name === 'string'
            && Number.isFinite(Number(candidate.max_distance_km))
            && Number.isFinite(Number(candidate.fee));
        }).map((zone) => ({
          name: zone.name,
          max_distance_km: Number(zone.max_distance_km),
          fee: Math.max(0, Number(zone.fee)),
        })));
      }
    });
  }, [user]);

  // Get merchant location state (will be loaded after merchantIds are computed)
  const [merchantLocation, setMerchantLocation] = useState<{ lat: number; lng: number } | null>(null);
  const [merchantRegion, setMerchantRegion] = useState<{
    cityName: string | null;
    districtName: string | null;
  }>({ cityName: null, districtName: null });

  const subtotal = getCartItemsSubtotal(selectedItems);
  const selectedItemCount = items.reduce((count, item) => count + item.quantity, 0);
  const knownStockConflict = items.some((item) =>
    item.product.stock <= 0 || item.quantity > item.product.stock ||
    (item.toppings || []).some((topping) => topping.product.stock < item.quantity * topping.quantity),
  );

  // Calculate shipping based on distance
  const estimatedShippingCost = useMemo(() => {
    if (deliveryType === 'PICKUP') return 0;

    // Free shipping threshold check
    const freeShippingMin = shippingSettings?.free_shipping_min_order ?? Infinity;
    if (subtotal >= freeShippingMin) return 0;

    const baseFee = shippingSettings?.base_fee ?? 5000;
    const perKmFee = shippingSettings?.per_km_fee ?? 2000;
    const minFee = shippingSettings?.min_fee ?? 5000;
    const maxFee = shippingSettings?.max_fee ?? 50000;
    const distance = Math.max(distanceKm ?? 0, 0);
    const zone = shippingZones
      .filter((candidate) => candidate.max_distance_km >= distance)
      .sort((a, b) => a.max_distance_km - b.max_distance_km)[0]
      ?? [...shippingZones].sort((a, b) => b.max_distance_km - a.max_distance_km)[0];
    const zoneSurcharge = Math.max(0, zone?.fee ?? 0);

    if (distanceKm !== null && distanceKm > 0) {
      return Math.min(maxFee, Math.max(minFee, baseFee + Math.round(distanceKm * perKmFee) + zoneSurcharge));
    }

    return Math.min(maxFee, Math.max(minFee, baseFee + zoneSurcharge));
  }, [deliveryType, distanceKm, shippingSettings, shippingZones, subtotal]);
  const routeCalculationPending = deliveryType !== 'PICKUP'
    && Boolean(merchantLocation && addressData.location)
    && distanceSource === 'calculating';
  // Route distance remains useful for local-delivery eligibility and ETA.
  // The server quote and order pricing independently derive distance from coordinates.
  const distanceCalculationRequired = deliveryType !== 'PICKUP'
    && Boolean(merchantLocation && addressData.location);
  const distanceReady = !distanceCalculationRequired
    || (distanceKm !== null && Number.isFinite(distanceKm) && distanceKm > 0 && distanceSource !== 'calculating');

  const voucherDiscount = appliedVoucher?.discount || 0;
  const quoteItems = useMemo(() => normalizeCheckoutProductQuantities(items.flatMap((item) => [
    { product_id: item.product.id, quantity: Math.trunc(item.quantity) },
    ...(item.toppings || []).map((topping) => ({
      product_id: topping.product.id,
      quantity: Math.trunc(item.quantity * topping.quantity),
    })),
  ])), [items]);
  const deliveryCityId = addressData.address.city || null;
  const deliveryDistrictId = addressData.address.district || null;
  const checkoutQuoteKey = useMemo(() => JSON.stringify({
    items: quoteItems,
    deliveryType,
    lat: addressData.location?.lat ?? null,
    lng: addressData.location?.lng ?? null,
    cityId: deliveryCityId,
    districtId: deliveryDistrictId,
    voucherId: user ? appliedVoucher?.id ?? null : null,
    merchantId: items[0]?.product.merchantId ?? null,
  }), [addressData.location?.lat, addressData.location?.lng, appliedVoucher?.id, deliveryCityId, deliveryDistrictId, deliveryType, items, quoteItems, user]);
  const serverQuote = checkoutQuoteResult?.key === checkoutQuoteKey ? checkoutQuoteResult.quote : null;
  const shippingCost = serverQuote?.shipping_cost ?? estimatedShippingCost;
  const displaySubtotal = serverQuote?.subtotal ?? subtotal;
  const displayVoucherDiscount = serverQuote?.voucher_discount ?? voucherDiscount;
  const total = serverQuote?.total ?? (subtotal + estimatedShippingCost - voucherDiscount);
  const checkoutQuoteReady = Boolean(serverQuote);
  const authoritativeLinePrices = useMemo(
    () => new Map((serverQuote?.line_items ?? []).map((line) => [line.product_id, line.unit_price])),
    [serverQuote?.line_items],
  );
  const getDisplayedItemSubtotal = (item: typeof items[number]) => {
    if (!serverQuote?.line_items?.length) return getCartItemSubtotal(item);
    const basePrice = authoritativeLinePrices.get(item.product.id) ?? item.product.price;
    const toppingTotal = (item.toppings || []).reduce((sum, topping) => (
      sum + (authoritativeLinePrices.get(topping.product.id) ?? topping.product.price) * topping.quantity
    ), 0);
    return (basePrice + toppingTotal) * item.quantity;
  };

  const deliveryRestriction = useMemo(
    () => getDeliveryRestriction(
      distanceKm,
      addressData.address,
      merchantRegion,
    ),
    [distanceKm, addressData.address, merchantRegion],
  );

  useEffect(() => {
    // Expedition remains supported server-side for a later rollout, but is
    // intentionally hidden from buyer checkout for now.
    if (deliveryType === 'EXPEDITION' || (deliveryRestriction.requiresExpedition && deliveryType === 'INTERNAL')) {
      setDeliveryType('PICKUP');
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

  // Stable merchant IDs keep checkout policy independent from display names and item variants.
  const merchantIds = useMemo(() => getCheckoutMerchantIds(items), [items]);
  const merchantIdsKey = useMemo(() => merchantIds.join(','), [merchantIds]);
  const hasMultipleMerchants = hasMultipleCheckoutMerchants(merchantIds);
  const firstMerchantId = merchantIds[0];

  // GDC is enabled only when an administrator has activated the merchant
  // profile. The query failing (for example before migration deployment)
  // deliberately fails closed and keeps the existing Xendit path intact.
  useEffect(() => {
    let cancelled = false;
    if (!user || !firstMerchantId || hasMultipleMerchants) {
      setGdcAvailable(false);
      return () => { cancelled = true; };
    }
    supabase.from('gdc_payment_profiles').select('id').eq('merchant_id', firstMerchantId).eq('provider', 'GDC').eq('status', 'ACTIVE').maybeSingle()
      .then(({ data, error }) => {
        if (!cancelled) {
          const available = !error && Boolean(data);
          setGdcAvailable(available);
          if (available) setOnlineProvider('GDC');
        }
      });
    return () => { cancelled = true; };
  }, [firstMerchantId, hasMultipleMerchants, user]);

  useEffect(() => {
    let cancelled = false;
    if (!quoteItems.length || !firstMerchantId || hasMultipleMerchants
      || (deliveryType !== 'PICKUP' && !addressData.location)
      || (deliveryType !== 'PICKUP' && !merchantLocation)) {
      setCheckoutQuoteResult(null);
      setCheckoutQuoteLoading(false);
      // Wait for merchant data before showing a quote error. The effect is
      // keyed by merchantLocation below, so it will retry automatically once
      // the merchant coordinates have loaded.
      setCheckoutQuoteError(
        deliveryType !== 'PICKUP' && paymentSettingsLoadState.status !== 'loading'
          ? 'Lokasi toko belum tersedia untuk menghitung ongkir.'
          : null,
      );
      return () => { cancelled = true; };
    }

    setCheckoutQuoteResult(null);
    setCheckoutQuoteLoading(true);
    setCheckoutQuoteError(null);
    void (async () => {
      try {
        const { data, error } = await supabase.rpc('quote_marketplace_checkout' as never, {
          p_items: quoteItems,
          p_delivery: {
            lat: addressData.location?.lat ?? null,
            lng: addressData.location?.lng ?? null,
            city_id: deliveryCityId,
            district_id: deliveryDistrictId,
          },
          p_delivery_type: deliveryType,
          p_voucher_id: user ? appliedVoucher?.id ?? null : null,
        } as never);
        if (cancelled) return;
        if (error || !data) {
          setCheckoutQuoteError(error?.message || 'Quote checkout tidak tersedia');
          setCheckoutQuoteResult(null);
          return;
        }
        const quote = data as unknown as MarketplaceCheckoutQuote;
        if (![quote.subtotal, quote.shipping_cost, quote.voucher_discount, quote.total, quote.distance_km].every(Number.isFinite)) {
          setCheckoutQuoteError('Quote checkout dari server tidak valid');
          setCheckoutQuoteResult(null);
          return;
        }
        setCheckoutQuoteResult({ key: checkoutQuoteKey, quote });
      } catch (error: unknown) {
        if (cancelled) return;
        setCheckoutQuoteError(error instanceof Error ? error.message : 'Quote checkout tidak tersedia');
        setCheckoutQuoteResult(null);
      } finally {
        if (!cancelled) setCheckoutQuoteLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [addressData.location, addressData.location?.lat, addressData.location?.lng, appliedVoucher?.id, checkoutQuoteKey, deliveryCityId, deliveryDistrictId, deliveryType, firstMerchantId, hasMultipleMerchants, merchantLocation, merchantLocation?.lat, merchantLocation?.lng, paymentSettingsLoadState.status, quoteItems, quoteRetryNonce, user]);

  // Check merchant operating hours
  const [merchantOperatingInfo, setMerchantOperatingInfo] = useState<Record<string, MerchantOperatingInfo>>({});
  const [operatingHoursLoading, setOperatingHoursLoading] = useState(false);
  const [operatingHoursError, setOperatingHoursError] = useState<Error | null>(null);

  // Load merchant location and payment settings once per merchant. The
  // provider availability check must not refetch this whole block.
  useEffect(() => {
    let cancelled = false;
    if (!firstMerchantId) {
      setMerchantPaymentSettings(null);
      setPaymentSettingsLoadState({ merchantId: null, status: 'error' });
      return () => { cancelled = true; };
    }

    setMerchantPaymentSettings(null);
    setPaymentSettingsLoadState({ merchantId: firstMerchantId, status: 'loading' });
    // Do not let a previous merchant's coordinates be used while the next
    // merchant is loading (for example after changing the cart).
    setMerchantLocation(null);
    setMerchantRegion({ cityName: null, districtName: null });
    const fetchMerchantData = async () => {
      try {
        // Get location and payment settings of first merchant (simplified - assumes single merchant checkout)
        const { data, error } = await supabase
          .from('merchants')
          .select('location_lat, location_lng, province, city, district, payment_transfer_enabled, bank_name, bank_account_number, bank_account_name, qris_image_url')
          .eq('id', firstMerchantId)
          .maybeSingle();
        if (error) throw error;
        if (!data) throw new Error('Pengaturan merchant tidak ditemukan');

        if (Number.isFinite(Number(data.location_lat)) && Number.isFinite(Number(data.location_lng)) && !cancelled) {
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
          const { data: adminSettings, error: adminSettingsError } = await supabase
            .from('app_settings')
            .select('value')
            .eq('key', 'admin_payment_info')
            .maybeSingle();
          if (adminSettingsError) throw adminSettingsError;
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
        setPaymentSettingsLoadState({ merchantId: firstMerchantId, status: 'ready' });
      } catch (error) {
        console.error('Error loading merchant payment settings:', error);
        if (!cancelled) {
          setMerchantPaymentSettings(null);
          setPaymentSettingsLoadState({ merchantId: firstMerchantId, status: 'error' });
        }
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
        return (current === 'ONLINE' && xenditAvailable) || current === 'QRIS_DYNAMIC' ? current : 'TRANSFER';
      }
      return xenditAvailable || gdcAvailable ? 'ONLINE' : current;
    });
  }, [gdcAvailable, merchantPaymentSettings, xenditAvailable, user]);

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
  const contactStepComplete = Boolean(addressData.name.trim().length >= 2 && validatePhone(addressData.phone).isValid);
  const addressStepComplete = contactStepComplete && isDeliveryReady;
  const deliveryStepComplete = addressStepComplete && hasChosenDelivery;
  const paymentStepComplete = deliveryStepComplete && hasChosenPayment;
  const currentStepIndex = !items.length ? 0 : !addressStepComplete ? 1 : !deliveryStepComplete ? 2 : !paymentStepComplete ? 3 : 3;
  const paymentSettingsReady = isCheckoutPaymentSettingsReady(
    paymentSettingsLoadState.status,
    paymentSettingsLoadState.merchantId,
    firstMerchantId,
  ) && merchantPaymentSettings !== null;
  const transferDetailsAvailable = Boolean(
    (merchantPaymentSettings?.bankName && merchantPaymentSettings.bankAccountNumber) || merchantPaymentSettings?.qrisImageUrl,
  );
  const paymentReady = paymentSettingsReady && (paymentMethod === 'QRIS_DYNAMIC'
    ? Boolean(user && !hasMultipleMerchants)
    : isCheckoutPaymentMethodAvailable(
      paymentMethod,
      merchantPaymentSettings?.transferEnabled === true,
      Boolean(user && xenditAvailable),
    ));

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
      newErrors.name = t('checkout.validation.name');
    }

    if (!addressData.phone || !validatePhone(addressData.phone).isValid) {
      newErrors.phone = t('checkout.validation.phone');
    }

    // Only validate address fields for delivery, not pickup
    if (deliveryType !== 'PICKUP') {
      if (!addressData.address.province) {
        newErrors.address = t('checkout.validation.province');
      } else if (!addressData.address.city) {
        newErrors.address = t('checkout.validation.city');
      } else if (!addressData.address.district) {
        newErrors.address = t('checkout.validation.district');
      } else if (!addressData.address.village) {
        newErrors.address = t('checkout.validation.village');
      }
    }

    // Only require map location for delivery, not pickup
    if (deliveryType !== 'PICKUP' && !addressData.location) {
      newErrors.location = t('checkout.validation.location');
    }

    if (deliveryType === 'INTERNAL' && deliveryRestriction.requiresExpedition) {
      newErrors.delivery = t('checkout.validation.expedition');
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

    if (!paymentSettingsReady) {
      toast({
        title: paymentSettingsLoadState.status === 'error' ? 'Metode pembayaran belum dapat diverifikasi' : 'Menyiapkan metode pembayaran',
        description: paymentSettingsLoadState.status === 'error'
          ? 'Pengaturan pembayaran toko gagal dimuat. Muat ulang halaman sebelum membuat pesanan.'
          : 'Tunggu sampai pengaturan pembayaran toko selesai dimuat sebelum membuat pesanan.',
        variant: 'destructive',
      });
      return;
    }

    if (routeCalculationPending) {
      toast({
        title: 'Sedang menghitung jarak',
        description: 'Tunggu sampai estimasi ongkir selesai dihitung sebelum membuat pesanan.',
      });
      return;
    }

    if (!distanceReady) {
      toast({
        title: 'Jarak pengiriman belum siap',
        description: 'Tunggu sampai jarak rute selesai dihitung sebelum membuat pesanan.',
        variant: 'destructive',
      });
      return;
    }
    if (!checkoutQuoteReady || checkoutQuoteLoading) {
      toast({
        title: 'Total checkout belum terverifikasi',
        description: checkoutQuoteError || 'Tunggu sampai server selesai menghitung subtotal, ongkir, dan diskon.',
        variant: 'destructive',
      });
      return;
    }

    if (items.length === 0) {
      toast({
        title: 'Keranjang kosong',
        variant: 'destructive',
      });
      return;
    }

    // Checkout currently creates one order and one payment flow. Do not create
    // partial child orders for a cart containing multiple merchants.
    if (hasMultipleMerchants) {
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
        title: t('checkout.form.errorTitle'),
        description: t('checkout.form.errorDescription'),
        variant: 'destructive',
      });
      return;
    }

    setLoading(true);
    setStockConflict(null);

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
        const message = outOfStockItems.join(', ');
        setStockConflict(message);
        setLoading(false);
        toast({
          title: 'Stok tidak mencukupi',
          description: message,
          variant: 'destructive',
        });
        return;
      }

      const fullAddress = [formatFullAddress(addressData.address), addressData.detailAddress?.trim()].filter(Boolean).join(', ');
      const checkoutPayload = {
        p_items: quoteItems,
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
        // The order RPC uses its existing transfer workflow; GDC MPM is
        // generated by the server once this authoritative order exists.
        p_payment_method: paymentMethod === 'QRIS_DYNAMIC' ? 'TRANSFER' : paymentMethod,
        // Persist the MPM discriminator before the orders BEFORE INSERT trigger
        // runs; merchants.qris_image_url is only for static QRIS/manual transfer.
        p_payment_channel: paymentMethod === 'QRIS_DYNAMIC' ? 'QRIS_MPM_GDC' : null,
        p_voucher_id: user ? appliedVoucher?.id ?? null : null,
        // The server derives distance from the submitted destination and the
        // merchant's stored coordinates; never trust a client-supplied rate input.
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

      if (user && paymentMethod === 'ONLINE' && (xenditAvailable || gdcAvailable)) {
        try {
          if (onlineProvider === 'GDC' && gdcAvailable) {
            const gdcPayment = await createGdcQrisPayment(authoritativeOrderId);
            selectedItems.forEach(item => {
              if (item.toppings?.length) removeFromCart(item.product.id, item.toppings);
              else removeFromCart(item.product.id);
            });
            checkoutKeyRef.current = null;
            navigate(`/payment/gdc/${authoritativeOrderId}/${gdcPayment.attempt.id}`);
            return;
          }
          const invoice = await createPaymentInvoice({ orderId: authoritativeOrderId });
          // The order is already committed and the invoice is ready. Clear the
          // purchased lines before navigating away so a successful online
          // checkout cannot leave stale items in the cart.
          selectedItems.forEach(item => {
            if (item.toppings?.length) removeFromCart(item.product.id, item.toppings);
            else removeFromCart(item.product.id);
          });
          checkoutKeyRef.current = null;
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
          setPaymentRecoveryProvider(onlineProvider === 'GDC' && gdcAvailable ? 'GDC' : 'XENDIT');
        }
      }

      selectedItems.forEach(item => {
        if (item.toppings?.length) removeFromCart(item.product.id, item.toppings);
        else removeFromCart(item.product.id);
      });
      checkoutKeyRef.current = null;
      if (paymentMethod === 'QRIS_DYNAMIC') {
        navigate(`/payment/${authoritativeOrderId}?provider=gdc-mpm`);
        return;
      }
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
        } else if (/insufficient stock|stock is unavailable|marketplace stock/i.test(rawMessage)) {
          errorMessage = 'Stok produk sudah habis atau berubah. Perbarui keranjang lalu coba lagi.';
          setStockConflict(errorMessage);
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
        if (paymentRecoveryProvider === 'GDC' && gdcAvailable) {
          const gdcPayment = await createGdcQrisPayment(orderId);
          navigate(`/payment/gdc/${orderId}/${gdcPayment.attempt.id}`);
          return;
        }
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
              ? `Order sudah tersimpan dan stok diamankan sementara. ${paymentRecoveryProvider === 'GDC' ? 'QRIS dinamis belum berhasil dibuat.' : 'Invoice online belum berhasil dibuat.'}`
              : 'Pesanan Anda telah masuk ke sistem dan sedang menunggu konfirmasi dari penjual.'}
          </p>
          <div className="space-y-3">
            {paymentRecoveryError && (
              <Button onClick={retryPayment} className="w-full" disabled={retryingPayment}>
                {retryingPayment ? (paymentRecoveryProvider === 'GDC' ? 'Membuat QRIS...' : 'Mencoba membuat invoice...') : 'Coba Bayar Lagi'}
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

  if (items.length === 0) {
    return (
      <div className="mobile-shell bg-background min-h-screen p-6">
        <div className="flex min-h-[80dvh] flex-col items-center justify-center text-center">
          <Package className="h-12 w-12 text-muted-foreground mb-4" aria-hidden="true" />
          <h1 className="text-xl font-bold">{t('checkout.empty.title')}</h1>
          <p className="mt-2 max-w-sm text-sm text-muted-foreground">
            {t('checkout.empty.description')}
          </p>
          <Button className="mt-6 w-full max-w-xs" onClick={() => navigate('/cart')}>
            {t('checkout.empty.backToCart')}
          </Button>
          <Button variant="ghost" className="mt-2 w-full max-w-xs" onClick={() => navigate('/products')}>
            {t('checkout.empty.continueShopping')}
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="mobile-shell bg-secondary flex h-[100dvh] min-h-0 flex-col">
      {/* Sticky Header & Step Indicator */}
      <div className="sticky top-0 z-50 bg-card/95 shadow-sm backdrop-blur-md">
        {/* Header */}
        <div className="p-4 border-b border-border flex items-center gap-3">
          <button
            onClick={() => safeGoBack(navigate)}
            className="w-8 h-8 rounded-full hover:bg-secondary flex items-center justify-center"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>
          <h2 className="font-bold text-lg text-foreground">
            {t('checkout.title')}
            {items.length > 0 && (
              <Badge variant="secondary" className="ml-2 text-xs">{t('checkout.productCount', { count: selectedItemCount })}</Badge>
            )}
          </h2>
        </div>

        {/* Step Indicator */}
        <div role="group" className="px-3 pt-2 pb-2 border-b border-border" aria-label={t('checkout.steps')}>
          <div className="flex items-center justify-between gap-1">
            {[
              { icon: Package, label: t('checkout.step.order'), done: items.length > 0, current: currentStepIndex === 0 },
              { icon: MapPin, label: t('checkout.step.address'), done: addressStepComplete, current: currentStepIndex === 1 },
              { icon: Truck, label: t('checkout.step.delivery'), done: deliveryStepComplete, current: currentStepIndex === 2 },
              { icon: CreditCard, label: t('checkout.step.payment'), done: paymentStepComplete, current: currentStepIndex === 3 },
            ].map((step, i) => (
              <div key={step.label} className="flex items-center" aria-current={step.current && !step.done ? 'step' : undefined}>
                <div className="flex flex-col items-center gap-0.5">
                  <div className={`w-7 h-7 rounded-full flex items-center justify-center transition-colors ${
                    step.done
                      ? 'bg-primary text-primary-foreground'
                      : step.current ? 'bg-primary/10 text-primary ring-1 ring-primary' : 'bg-muted text-muted-foreground'
                  }`}>
                    {step.done ? (
                      <CheckCircle className="h-3.5 w-3.5" />
                    ) : (
                      <step.icon className="h-3.5 w-3.5" />
                    )}
                  </div>
                  <span className={`text-[9px] font-medium ${step.done || step.current ? 'text-primary' : 'text-muted-foreground'}`}>{step.label}</span>
                </div>
                {i < 3 && <div className={`h-px flex-1 min-w-2 mx-1 mb-4 ${step.done ? 'bg-primary' : 'bg-border'}`} />}
              </div>
            ))}
          </div>
        </div>
      </div>

      <form
        id="checkout-form"
        onSubmit={handleSubmit}
        className="min-h-0 flex-1 touch-pan-y overflow-y-auto overscroll-contain p-4"
        style={{ paddingBottom: checkoutSummaryHeight }}
      >
        {hasMultipleMerchants && (
          <div role="alert" className="bg-amber-50 border border-amber-200 rounded-xl p-4 mb-4">
            <h3 className="font-bold text-amber-900 text-sm">{t('checkout.multiStore.title')}</h3>
            <p className="text-xs text-amber-800 mt-1">{t('checkout.multiStore.description')}</p>
            <Button type="button" variant="outline" size="sm" className="mt-3" onClick={() => navigate('/cart')}>
              {t('checkout.multiStore.action')}
            </Button>
          </div>
        )}
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
          className="bg-card rounded-xl p-3 sm:p-4 border border-border shadow-sm mb-3 sm:mb-4"
        >
          <div className="flex items-center gap-2 mb-4">
            <Package className="h-5 w-5 text-primary" />
            <h3 className="font-bold text-foreground">{t('checkout.orderSummary')}</h3>
            <Badge variant="secondary" className="text-xs ml-auto">{t('checkout.productCount', { count: selectedItemCount })}</Badge>
          </div>

          <div className="space-y-3">
            <p className="mb-3 text-xs text-muted-foreground">Harga item berasal dari keranjang; subtotal dan total akhir diverifikasi dari server sebelum pesanan dibuat.</p>
            {items.map(item => (
              <div key={getCartItemKey(item)} className="flex gap-3">
                <img
                  src={optimizeSupabaseImage(item.product.image, 160)}
                  srcSet={getOptimizedImageSrcSet(item.product.image, [160, 240])}
                  sizes="48px"
                  alt={item.product.name}
                  width={48}
                  height={48}
                  loading="eager"
                  decoding="async"
                  className="w-12 h-12 rounded-lg object-cover"
                />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium line-clamp-1">{item.product.name}</p>
                  <p className="text-xs text-muted-foreground">{item.quantity} × {formatPrice(authoritativeLinePrices.get(item.product.id) ?? item.product.price)}</p>
                  {item.toppings?.map(topping => (
                    <p key={topping.product.id} className="text-[11px] text-muted-foreground">
                      {t('checkout.itemTopping', { name: topping.product.name, quantity: topping.quantity, price: formatPrice(authoritativeLinePrices.get(topping.product.id) ?? topping.product.price) })}
                    </p>
                  ))}
                </div>
                <p className="text-sm font-bold">{formatPrice(getDisplayedItemSubtotal(item))}</p>
              </div>
            ))}
          </div>
        </motion.div>

        {/* Delivery Address */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.05 }}
          className="bg-card rounded-xl p-3 sm:p-4 border border-border shadow-sm mb-3 sm:mb-4"
        >
          <div className="flex items-center gap-2 mb-4">
            <MapPin className="h-5 w-5 text-primary" />
            <h3 className="font-bold text-foreground">{t('checkout.address.title')}</h3>
          </div>

          <CheckoutAddressForm
            value={addressData}
            onChange={setAddressData}
            onDistanceChange={setDistanceKm}
            onDistanceSourceChange={setDistanceSource}
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
            <p className="pl-6 text-xs text-muted-foreground">
              {distanceSource === 'google'
                ? 'Rute dihitung Google Maps.'
                : distanceSource === 'fallback'
                  ? 'Rute memakai layanan cadangan OpenStreetMap.'
                  : distanceSource === 'straight-line'
                    ? 'Jarak garis lurus digunakan sebagai perkiraan; ongkir dapat dikonfirmasi kembali.'
                    : 'Menghitung jarak rute…'}
            </p>
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
                <p className="font-semibold text-amber-900">Kurir lokal tidak tersedia untuk alamat ini</p>
                <p className="text-xs text-amber-800 mt-1">
                  Ojek/kurir lokal hanya tersedia sampai {MAX_LOCAL_DELIVERY_DISTANCE_KM} km dan dalam kecamatan serta kabupaten/kota yang sama. Untuk sementara, pilih Ambil Sendiri.
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
          className="bg-card rounded-xl p-3 sm:p-4 border border-border shadow-sm mb-3 sm:mb-4"
        >
          <div className="flex items-center gap-2 mb-4">
            <Truck className="h-5 w-5 text-primary" />
            <h3 className="font-bold text-foreground">{t('shipping.method')}</h3>
          </div>

          <RadioGroup
            value={deliveryType}
            onValueChange={(value) => {
              setDeliveryType(value as 'PICKUP' | 'INTERNAL' | 'EXPEDITION');
              setHasChosenDelivery(true);
            }}
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
              <span className="text-sm font-bold text-primary">
                {serverQuote ? formatCurrency(shippingCost) : checkoutQuoteLoading ? 'Menghitung…' : '—'}
              </span>
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
          className="bg-card rounded-xl p-3 sm:p-4 border border-border shadow-sm mb-3 sm:mb-4"
        >
          <div className="flex items-center gap-2 mb-4">
            <CreditCard className="h-5 w-5 text-primary" />
            <h3 className="font-bold text-foreground">{t('checkout.payment.title')}</h3>
          </div>

          <RadioGroup
            value={paymentMethod}
            onValueChange={(value) => {
              setPaymentMethod(value as PaymentMethod);
              setHasChosenPayment(true);
            }}
            className="space-y-2"
          >
            {/* Transfer Option - Based on merchant settings */}
            {(!user || merchantPaymentSettings?.transferEnabled !== false) && (
              <label className={`flex items-center gap-3 p-3 border rounded-lg cursor-pointer transition ${
                paymentMethod === 'TRANSFER' ? 'border-primary bg-primary/5' : 'border-border'
              } ${hasMultipleMerchants ? 'opacity-50 cursor-not-allowed' : ''}`}>
                <RadioGroupItem value="TRANSFER" id="transfer" disabled={!paymentSettingsReady || hasMultipleMerchants} />
                <CreditCard className="h-5 w-5 text-muted-foreground" />
                <div className="flex-1">
                  <p className="font-bold text-sm">{t('checkout.payment.transfer')}</p>
                  <p className="text-xs text-muted-foreground">
                    {hasMultipleMerchants
                      ? t('checkout.payment.oneStoreOnly')
                      : merchantPaymentSettings?.bankName
                      ? `Transfer ke ${merchantPaymentSettings.bankName}`
                      : t('checkout.payment.transferToSeller')}
                  </p>
                </div>
              </label>
            )}

            {/* Online Payment via Xendit */}
            {user && (xenditAvailable || gdcAvailable) && (
              <label className={`flex items-center gap-3 p-3 border rounded-lg cursor-pointer transition ${
                paymentMethod === 'ONLINE' ? 'border-primary bg-primary/5' : 'border-border'
              } ${hasMultipleMerchants ? 'opacity-50 cursor-not-allowed' : ''}`}>
                <RadioGroupItem value="ONLINE" id="online" disabled={!paymentSettingsReady || hasMultipleMerchants} />
                <CreditCard className="h-5 w-5 text-muted-foreground" />
                <div className="flex-1">
                  <p className="font-bold text-sm">{gdcAvailable ? 'QRIS Dinamis GDC' : t('checkout.payment.online')}</p>
                  <p className="text-xs text-muted-foreground">{gdcAvailable ? 'Scan QRIS setelah pesanan dibuat. Status pembayaran diperbarui otomatis.' : t('checkout.payment.onlineMethods')}</p>
                </div>
              </label>
            )}
            {user && (
              <label className={`flex items-center gap-3 p-3 border rounded-lg cursor-pointer transition ${
                paymentMethod === 'QRIS_DYNAMIC' ? 'border-primary bg-primary/5' : 'border-border'
              } ${hasMultipleMerchants ? 'opacity-50 cursor-not-allowed' : ''}`}>
                <RadioGroupItem value="QRIS_DYNAMIC" id="qris-dynamic" disabled={!paymentSettingsReady || hasMultipleMerchants} />
                <CreditCard className="h-5 w-5 text-muted-foreground" />
                <div className="flex-1">
                  <p className="font-bold text-sm">QRIS Dinamis</p>
                  <p className="text-xs text-muted-foreground">Nominal otomatis, pembayaran langsung ke merchant</p>
                </div>
              </label>
            )}
          </RadioGroup>

          {/* Bank Transfer Info */}
          {paymentMethod === 'TRANSFER' && merchantPaymentSettings?.bankName && (
            <div className="mt-3 p-3 bg-secondary/50 rounded-lg space-y-1">
              <p className="text-xs font-medium text-foreground">{t('checkout.payment.accountInfo')}</p>
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

          {merchantPaymentSettings && paymentMethod === 'TRANSFER' && !transferDetailsAvailable && (
            <div className="mt-3 rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-900" role="alert">
              Status pembayaran: menunggu instruksi dari penjual. Jangan melakukan transfer sebelum menerima detail pembayaran dan nominal resmi untuk pesanan ini.
            </div>
          )}
          {paymentMethod === 'QRIS_DYNAMIC' && (
            <div className="mt-3 rounded-lg border border-primary/20 bg-primary/5 p-3 text-xs text-foreground" role="status">
              QR akan dibuat setelah pesanan tersimpan menggunakan Merchant ID GDC yang sudah diverifikasi admin. Pembayaran masuk langsung ke akun merchant.
            </div>
          )}

        </motion.div>

        {/* Order Summary moved to top of form */}

        {/* Voucher */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.25 }}
          className="bg-card rounded-xl p-3 sm:p-4 border border-border shadow-sm mb-3 sm:mb-4"
        >
          {!user ? (
            <p className="text-sm text-muted-foreground">{t('checkout.voucher.loginRequired')}</p>
          ) : hasMultipleMerchants ? (
            <p className="text-sm text-muted-foreground">{t('checkout.voucher.oneStoreOnly')}</p>
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
          <Label htmlFor="notes">{t('checkout.notes.label')}</Label>
          <Textarea
            id="notes"
            placeholder={t('checkout.notes.placeholder')}
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={2}
            className="mt-2"
          />
        </motion.div>
      </form>

        {/* Checkout Summary */}
      <div ref={checkoutSummaryRef} className="mobile-action-safe fixed bottom-0 left-0 right-0 max-w-[480px] mx-auto z-40 bg-card/95 border-t border-border px-3 pt-2 shadow-lg backdrop-blur-md sm:p-5">
        {(knownStockConflict || stockConflict) && (
          <div className="mb-3 flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-xs text-destructive" role="alert">
            <AlertTriangle className="mt-0.5 h-4 w-4 flex-shrink-0" />
            <span>{stockConflict || t('checkout.cta.stockHelp')}</span>
          </div>
        )}
        {/* Free shipping badge */}
        {checkoutQuoteLoading && (
          <p className="mb-2 text-center text-xs text-muted-foreground" role="status">
            <Loader2 className="mr-1 inline h-3 w-3 animate-spin" /> Memverifikasi subtotal, ongkir, dan total dari server...
          </p>
        )}
        {checkoutQuoteError && !checkoutQuoteLoading && (
          <div className="mb-2 flex items-center justify-center gap-2 text-center text-xs text-destructive" role="alert">
            <span>{checkoutQuoteError}</span>
            <Button type="button" variant="outline" size="sm" className="h-7 px-2 text-xs" onClick={() => setQuoteRetryNonce((value) => value + 1)}>
              Coba lagi
            </Button>
          </div>
        )}
        {serverQuote && serverQuote.shipping_cost === 0 && deliveryType !== 'PICKUP' && (
          <div className="flex items-center gap-1.5 mb-2 text-xs text-emerald-600 font-medium">
            <CheckCircle className="h-3.5 w-3.5" />
            <span>Ongkir gratis berdasarkan perhitungan server</span>
          </div>
        )}
        <div className="flex justify-between items-center mb-1 text-xs sm:text-sm">
          <span className="text-muted-foreground">{t('shipping.subtotal')}</span>
          <span className="font-bold">{serverQuote ? formatCurrency(displaySubtotal) : '—'}</span>
        </div>
        <div className="flex justify-between items-center mb-1 text-xs sm:text-sm">
          <span className="text-muted-foreground">{t('shipping.fee')}</span>
          <span className="font-bold">{serverQuote ? formatCurrency(shippingCost) : '—'}</span>
        </div>
        {(serverQuote ? displayVoucherDiscount > 0 : Boolean(appliedVoucher)) && (
          <div className="flex justify-between items-center mb-1 text-sm">
            <span className="text-primary">{t('shipping.voucherDiscount')}</span>
            <span className="font-bold text-primary">{serverQuote ? `-${formatCurrency(displayVoucherDiscount)}` : '—'}</span>
          </div>
        )}
        <div className="flex justify-between items-center mb-2 pt-2 sm:mb-3 sm:pt-3 border-t border-border">
          <span className="text-base sm:text-lg font-bold">{t('shipping.total')}</span>
          <span className="text-lg sm:text-xl font-bold text-primary">{serverQuote ? formatCurrency(total) : '—'}</span>
        </div>
        {/* Payment method label */}
        <div className="flex items-center gap-1.5 mb-2 text-[11px] text-muted-foreground">
          <CreditCard className="h-3.5 w-3.5" />
          <span>
            {t('shipping.payVia')}: <span className="font-medium text-foreground">
              {paymentMethod === 'QRIS_DYNAMIC' ? 'Bayar dengan QRIS Dinamis' : paymentMethod === 'TRANSFER' ? t('checkout.payment.transfer') : t('checkout.payment.online')}
            </span>
          </span>
        </div>
        <Button
          type="submit"
          form="checkout-form"
          className="w-full shadow-brand font-bold transition-all"
          size="lg"
          disabled={loading || checkoutQuoteLoading || !checkoutQuoteReady || routeCalculationPending || !distanceReady || knownStockConflict || Boolean(stockConflict) || items.length === 0 || hasMultipleMerchants || operatingHoursLoading || !allMerchantsOpen || !isDeliveryReady || !paymentSettingsReady || !paymentReady || (!user && (guestCheckoutFlagLoading || !guestCheckoutEnabled))}
        >
          {loading ? (
            <>
              <Loader2 className="h-4 w-4 mr-2 animate-spin" />
              {t('checkout.cta.processing')}
            </>
          ) : operatingHoursLoading ? (
            <>
              <Loader2 className="h-4 w-4 mr-2 animate-spin" />
              {t('checkout.cta.checkingStore')}
            </>
          ) : operatingHoursError ? (
            t('checkout.cta.storeUnverified')
          ) : !allMerchantsOpen ? (
            <>
              <Clock className="h-4 w-4 mr-2" />
              {t('checkout.cta.storeClosed')}
            </>
          ) : knownStockConflict || stockConflict ? (
            t('checkout.cta.stockUnavailable')
          ) : (
            user ? t('checkout.cta.placeOrder') : t('checkout.cta.guestOrder')
          )}
        </Button>
        {!isDeliveryReady && (
          <p className="mt-2 text-center text-xs text-muted-foreground">
            {t('checkout.cta.addressNeeded')}
          </p>
        )}
        {!paymentReady && !loading && (
          <p className="mt-2 text-center text-xs text-muted-foreground">
            {paymentSettingsLoadState.status === 'error'
              ? 'Pengaturan pembayaran gagal dimuat. Muat ulang halaman untuk mencoba lagi.'
              : !paymentSettingsReady
                ? 'Menyiapkan metode pembayaran toko...'
                : 'Pilih metode pembayaran yang tersedia untuk melanjutkan.'}
          </p>
        )}
        {hasMultipleMerchants && (
          <p className="mt-2 text-center text-xs text-amber-800">
            {t('checkout.multiStore.inline')}{' '}
            <button type="button" className="underline font-medium" onClick={() => navigate('/cart')}>
              {t('checkout.multiStore.adjust')}
            </button>
          </p>
        )}
      </div>
    </div>
  );
}
