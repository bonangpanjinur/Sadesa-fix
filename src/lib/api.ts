import { supabase } from '../integrations/supabase/client';
import type { Product, Village, Tourism, Merchant } from '../types';
import { getMerchantOperatingStatus, type OperatingDaySchedule } from './merchantOperatingHours';
import { getProductUnavailableReason } from './productAvailability';

// Import local images as fallbacks
import heroVillage from '../assets/hero-village.webp';
import villageBojong from '../assets/village-bojong.webp';
import villageSukamaju from '../assets/village-sukamaju.webp';
import productKeripik from '../assets/product-keripik.webp';
import productKopi from '../assets/product-kopi.webp';
import productAnyaman from '../assets/product-anyaman.webp';
import productSambal from '../assets/product-sambal.webp';

export const heroImage = heroVillage;

// Image mapping for products
const productImages: Record<string, string> = {
  'bbbb1111-1111-1111-1111-111111111111': productKeripik,
  'bbbb2222-2222-2222-2222-222222222222': productKopi,
  'bbbb3333-3333-3333-3333-333333333333': productAnyaman,
  'bbbb4444-4444-4444-4444-444444444444': productSambal,
};

// Image mapping for villages
const villageImages: Record<string, string> = {
  '11111111-1111-1111-1111-111111111111': villageBojong,
  '22222222-2222-2222-2222-222222222222': villageSukamaju,
};

let cachedFreeTierLimit: number | null = null;
let cacheTs = 0;
const DEFAULT_FREE_TIER_LIMIT = 100;

// Simple in-memory cache for API calls (TTL 60s)
const apiCache = new Map<string, { data: unknown; ts: number }>();
const CACHE_TTL = 60_000;

function getCached<T>(key: string): T | null {
  const entry = apiCache.get(key);
  if (entry && Date.now() - entry.ts < CACHE_TTL) return entry.data as T;
  return null;
}

function setCache(key: string, data: unknown) {
  apiCache.set(key, { data, ts: Date.now() });
}

async function getFreeTierLimit(): Promise<number> {
  if (cachedFreeTierLimit !== null && Date.now() - cacheTs < 300000) return cachedFreeTierLimit;

  const { data, error } = await supabase
    .from('app_settings')
    .select('value')
    .eq('key', 'free_tier_quota')
    .maybeSingle();

  if (error) {
    throw new Error(`Unable to load free-tier quota configuration: ${error.message}`);
  }

  const configuredLimit = (data?.value as { limit?: unknown } | null)?.limit;
  if (typeof configuredLimit !== 'number' || !Number.isInteger(configuredLimit) || configuredLimit < 0) {
    console.warn(`Invalid or missing free-tier quota configuration; using default ${DEFAULT_FREE_TIER_LIMIT}.`);
    cachedFreeTierLimit = DEFAULT_FREE_TIER_LIMIT;
    cacheTs = Date.now();
    return DEFAULT_FREE_TIER_LIMIT;
  }

  cachedFreeTierLimit = configuredLimit;
  cacheTs = Date.now();
  return cachedFreeTierLimit;
}

// Helper to get merchant IDs with active quota (subscriptions OR free tier)
async function getMerchantsWithActiveQuota(): Promise<Set<string>> {
  // Run the three independent reads in parallel instead of a request waterfall.
  const [FREE_TIER_LIMIT, merchantsRes, subsRes] = await Promise.all([
    getFreeTierLimit(),
    supabase
      .from('merchants')
      .select('id')
      .eq('status', 'ACTIVE')
      .eq('registration_status', 'APPROVED'),
    supabase
      .from('merchant_subscriptions')
      .select('merchant_id, transaction_quota, used_quota')
      .eq('status', 'ACTIVE')
      .gte('expired_at', new Date().toISOString()),
  ]);

  if (merchantsRes.error) {
    throw new Error(`Unable to load merchants for quota check: ${merchantsRes.error.message}`);
  }
  if (subsRes.error) {
    throw new Error(`Unable to load merchant subscriptions for quota check: ${subsRes.error.message}`);
  }

  const allMerchants = merchantsRes.data;
  const activeSubs = subsRes.data;

  if (!allMerchants) return new Set();


  // Build a map of merchant -> aggregate remaining quota from subscriptions
  const subQuotaMap = new Map<string, number>();
  if (activeSubs) {
    for (const sub of activeSubs) {
      const remaining = sub.transaction_quota - sub.used_quota;
      const current = subQuotaMap.get(sub.merchant_id) || 0;
      subQuotaMap.set(sub.merchant_id, current + remaining);
    }
  }

  // Separate merchants with and without subscriptions
  const merchantIds = new Set<string>();
  const freeTierMerchantIds: string[] = [];
  
  for (const m of allMerchants) {
    if (subQuotaMap.has(m.id)) {
      if ((subQuotaMap.get(m.id) || 0) > 0) {
        merchantIds.add(m.id);
      }
    } else {
      freeTierMerchantIds.push(m.id);
    }
  }

  // Batch query: get order counts for all free tier merchants in a single query
  if (freeTierMerchantIds.length > 0) {
    const startOfMonth = new Date();
    startOfMonth.setDate(1);
    startOfMonth.setHours(0, 0, 0, 0);

    // Query orders grouped by merchant_id for free tier merchants
    const { data: orderCounts, error: orderCountsError } = await supabase
      .from('orders')
      .select('merchant_id')
      .in('merchant_id', freeTierMerchantIds)
      .gte('created_at', startOfMonth.toISOString());

    if (orderCountsError) {
      throw new Error(`Unable to load merchant order usage: ${orderCountsError.message}`);
    }

    // Count orders per merchant
    const countMap = new Map<string, number>();
    if (orderCounts) {
      for (const row of orderCounts) {
        if (row.merchant_id) {
          countMap.set(row.merchant_id, (countMap.get(row.merchant_id) || 0) + 1);
        }
      }
    }

    // Add merchants under free tier limit
    for (const mid of freeTierMerchantIds) {
      if ((countMap.get(mid) || 0) < FREE_TIER_LIMIT) {
        merchantIds.add(mid);
      }
    }
  }

  return merchantIds;
}

// Check if a specific merchant has active quota
export async function checkMerchantHasActiveQuota(merchantId: string): Promise<boolean> {
  try {
    // First check subscriptions
    const { data, error: subError } = await supabase
      .from('merchant_subscriptions')
      .select('transaction_quota, used_quota')
      .eq('merchant_id', merchantId)
      .eq('status', 'ACTIVE')
      .gte('expired_at', new Date().toISOString());

    if (subError) {
      console.error('Unable to check merchant subscription quota:', subError);
      return false;
    }

    if (data && data.length > 0) {
      const totalRemaining = data.reduce((sum, sub) => sum + (sub.transaction_quota - sub.used_quota), 0);
      return totalRemaining > 0;
    }

    // Fallback: free tier - check monthly order count
    const FREE_TIER_LIMIT = await getFreeTierLimit();
    const startOfMonth = new Date();
    startOfMonth.setDate(1);
    startOfMonth.setHours(0, 0, 0, 0);

    const { count, error: countError } = await supabase
      .from('orders')
      .select('*', { count: 'exact', head: true })
      .eq('merchant_id', merchantId)
      .gte('created_at', startOfMonth.toISOString());

    if (countError) {
      console.error('Unable to check merchant free-tier quota:', countError);
      return false;
    }

    return (count || 0) < FREE_TIER_LIMIT;
  } catch (error) {
    console.error('Unable to check merchant quota:', error);
    return false;
  }
}

interface FetchProductsOptions {
  limit?: number;
  includeReviews?: boolean;
  cacheKey?: string;
}

// Fetch products from database (include availability status and location).
// Homepage callers can request a smaller payload because review details are not
// rendered in product cards.
export async function fetchProducts(options: FetchProductsOptions = {}): Promise<Product[]> {
  const { limit = 200, includeReviews = true, cacheKey = 'products' } = options;
  const cached = getCached<Product[]>(cacheKey);
  if (cached) return cached;
  const merchantFields = includeReviews
    ? `
          id,
          name,
          image_url,
          slug,
          address,
          rating_avg,
          rating_count,
          reviews (id, rating, comment, created_at, is_visible),
          is_open,
          open_time,
          close_time,
          location_lat,
          location_lng,
          villages (name, location_lat, location_lng)
        `
    : `
          id,
          name,
          image_url,
          slug,
          address,
          rating_avg,
          rating_count,
          is_open,
          open_time,
          close_time,
          location_lat,
          location_lng,
          villages (name, location_lat, location_lng)
        `;
  // Quota lookup and the product query are independent — fire both at once.
  const [merchantsWithQuota, { data, error }] = await Promise.all([
    getMerchantsWithActiveQuota(),
    supabase
      .from('products')
      .select(`*, merchants (${merchantFields})`)
      .order('created_at', { ascending: false })
      .limit(limit),
  ]);

  if (error) {
    console.error('Error fetching products:', error);
    // Let React Query expose a real error state instead of making a network or
    // database failure look like an empty catalogue.
    throw error;
  }

  const merchantIds = [...new Set((data || []).map((product) => product.merchant_id).filter(Boolean))];
  const { data: schedules, error: schedulesError } = merchantIds.length > 0
    ? await supabase
      .from('merchant_operating_hours')
      .select('merchant_id, day_of_week, open_time, close_time, is_closed')
      .in('merchant_id', merchantIds)
    : { data: [], error: null };
  if (schedulesError) console.error('Error fetching merchant operating hours:', schedulesError);

  const scheduleByMerchant = new Map<string, OperatingDaySchedule[]>();
  for (const schedule of schedules || []) {
    const merchantSchedule = scheduleByMerchant.get(schedule.merchant_id) || [];
    merchantSchedule.push({
      day_of_week: schedule.day_of_week,
      open_time: schedule.open_time,
      close_time: schedule.close_time,
      is_closed: schedule.is_closed,
    });
    scheduleByMerchant.set(schedule.merchant_id, merchantSchedule);
  }

  const mappedProducts = (data || []).map(p => {
    const hasQuota = merchantsWithQuota.has(p.merchant_id);
    const merchant = p.merchants;
    
    // Jadwal mingguan adalah sumber jam canonical; is_open tetap menjadi kill switch manual.
    const isMerchantOpen = getMerchantOperatingStatus(
      merchant?.is_open ?? true,
      merchant?.open_time || null,
      merchant?.close_time || null,
      scheduleByMerchant.get(p.merchant_id),
    ).isCurrentlyOpen;
    
    const unavailableReason = getProductUnavailableReason({
      isActive: p.is_active,
      stock: Number(p.stock || 0),
      hasQuota,
      isMerchantOpen,
    });
    const isAvailable = !unavailableReason;

    // Get location - prefer merchant location, fallback to village location
    const locationLat = merchant?.location_lat 
      ? Number(merchant.location_lat) 
      : (merchant?.villages?.location_lat ? Number(merchant.villages.location_lat) : null);
    const locationLng = merchant?.location_lng 
      ? Number(merchant.location_lng) 
      : (merchant?.villages?.location_lng ? Number(merchant.villages.location_lng) : null);
    
    // Normalize promo fields from Supabase before rendering merchant promos.
    // This keeps the label visible even when the API returns boolean/numeric values as strings.
    const isPromo = p.is_promo === true || p.is_promo === 'true' || p.is_promo === 1 || p.is_promo === '1';
    const discountPercent = Number(p.discount_percent || 0);
    const hasDiscount = isPromo && discountPercent > 0;
    const discountedPrice = hasDiscount 
      ? Math.round(p.price - (p.price * discountPercent / 100))
      : p.price;

    return {
      id: p.id,
      createdAt: p.created_at,
      merchantId: p.merchant_id,
      merchantName: merchant?.name || '',
      merchantImageUrl: merchant?.image_url || null,
      merchantSlug: merchant?.slug || null,
      merchantAddress: merchant?.address || null,
      merchantRatingAvg: merchant?.rating_avg == null ? null : Number(merchant.rating_avg),
      merchantRatingCount: merchant?.rating_count == null ? null : Number(merchant.rating_count),
      merchantReviews: (merchant?.reviews || []).filter((review) => review.is_visible !== false).slice(0, 3).map((review) => ({
        id: review.id,
        rating: Number(review.rating),
        comment: review.comment || null,
        createdAt: review.created_at,
      })),
      merchantVillage: merchant?.villages?.name || '',
      name: p.name,
      description: p.description || '',
      price: discountedPrice,
      originalPrice: hasDiscount ? p.price : undefined,
      discountPercent: hasDiscount ? discountPercent : undefined,
      stock: p.stock,
      // Jangan tampilkan foto menu lain ketika merchant belum mengunggah foto.
      // Placeholder netral lebih jujur daripada membuat dimsum terlihat seperti keripik.
      image: productImages[p.id] || p.image_url || '/placeholder.svg',
      category: p.category as Product['category'],
      isActive: p.is_active,
      isPromo,
      isAvailable,
      isMerchantOpen,
      hasQuota,
      unavailableReason,
      locationLat,
      locationLng,
      sold_count: p.sold_count || 0,
    };
  });

  setCache(cacheKey, mappedProducts);
  return mappedProducts;
}

// Fetch single product
export async function fetchProduct(id: string): Promise<Product | null> {
  const { data, error } = await supabase
    .from('products')
    .select(`
      *,
      merchants (
        id,
        name,
        phone,
        address,
        rating_avg,
        rating_count,
        badge,
        is_open,
        open_time,
        close_time,
        villages (
          name
        )
      )
    `)
    .eq('id', id)
    .maybeSingle();

  if (error || !data) {
    console.error('Error fetching product:', error);
    return null;
  }

  const [{ data: schedule }, hasQuota] = await Promise.all([
    supabase
      .from('merchant_operating_hours')
      .select('day_of_week, open_time, close_time, is_closed')
      .eq('merchant_id', data.merchant_id)
      .order('day_of_week', { ascending: true }),
    checkMerchantHasActiveQuota(data.merchant_id),
  ]);

  // Jadwal mingguan adalah sumber jam canonical; is_open tetap menjadi kill switch manual.
  const isMerchantOpen = getMerchantOperatingStatus(
    data.merchants?.is_open ?? true,
    data.merchants?.open_time || null,
    data.merchants?.close_time || null,
    (schedule || []) as OperatingDaySchedule[],
  ).isCurrentlyOpen;
  const unavailableReason = getProductUnavailableReason({
    isActive: data.is_active,
    stock: Number(data.stock || 0),
    hasQuota,
    isMerchantOpen,
  });
  const isAvailable = !unavailableReason;

  // Calculate discounted price
  const hasDiscount = data.is_promo && data.discount_percent > 0;
  const discountedPrice = hasDiscount 
    ? Math.round(data.price - (data.price * data.discount_percent / 100))
    : data.price;

  return {
    id: data.id,
    merchantId: data.merchant_id,
    merchantName: data.merchants?.name || '',
    merchantVillage: data.merchants?.villages?.name || '',
    name: data.name,
    description: data.description || '',
    price: discountedPrice,
    originalPrice: hasDiscount ? data.price : undefined,
    discountPercent: hasDiscount ? data.discount_percent : undefined,
    stock: data.stock,
    image: productImages[data.id] || data.image_url || productKeripik,
    category: data.category as Product['category'],
    isActive: data.is_active,
    isPromo: data.is_promo,
    isAvailable,
    isMerchantOpen,
    hasQuota,
    unavailableReason,
  };
}

// Fetch merchants
export async function fetchMerchant(id: string): Promise<Merchant | null> {
  const { data, error } = await supabase
    .from('merchants')
    .select(`
      *,
      villages (
        name
      )
    `)
    .eq('id', id)
    .maybeSingle();

  if (error || !data) {
    console.error('Error fetching merchant:', error);
    return null;
  }

  return {
    id: data.id,
    userId: data.user_id || '',
    name: data.name,
    address: data.address || '',
    villageId: data.village_id || '',
    villageName: data.villages?.name || '',
    openTime: data.open_time || '08:00',
    closeTime: data.close_time || '17:00',
    classificationPrice: data.classification_price as Merchant['classificationPrice'],
    status: data.status as Merchant['status'],
    orderMode: data.order_mode as Merchant['orderMode'],
    ratingAvg: Number(data.rating_avg) || 0,
    ratingCount: data.rating_count || 0,
    badge: data.badge as Merchant['badge'],
    phone: data.phone || '',
    isOpen: data.is_open,
  };
}

// Fetch villages
export async function fetchVillages(): Promise<Village[]> {
  const cached = getCached<Village[]>('villages');
  if (cached) return cached;

  const { data, error } = await supabase
    .from('villages')
    .select('*');

  if (error) {
    console.error('Error fetching villages:', error);
    return [];
  }

  const result = (data || []).map(v => ({
    id: v.id,
    name: v.name,
    district: v.district,
    regency: v.regency,
    description: v.description || '',
    image: villageImages[v.id] || v.image_url || villageBojong,
    isActive: v.is_active,
    locationLat: v.location_lat ? Number(v.location_lat) : null,
    locationLng: v.location_lng ? Number(v.location_lng) : null,
  }));
  setCache('villages', result);
  return result;
}

// Fetch tourism spots
export async function fetchTourism(): Promise<Tourism[]> {
  const cached = getCached<Tourism[]>('tourism');
  if (cached) return cached;

  const { data, error } = await supabase
    .from('tourism')
    .select(`
      *,
      villages (
        name
      )
    `);

  if (error) {
    console.error('Error fetching tourism:', error);
    return [];
  }

  const result = (data || []).map(t => ({
    id: t.id,
    villageId: t.village_id,
    villageName: t.villages?.name || '',
    name: t.name,
    description: t.description || '',
    image: villageImages[t.village_id] || t.image_url || villageBojong,
    locationLat: Number(t.location_lat) || 0,
    locationLng: Number(t.location_lng) || 0,
    waLink: t.wa_link || '',
    sosmedLink: t.sosmed_link || '',
    facilities: t.facilities || [],
    isActive: t.is_active,
    viewCount: t.view_count,
  }));
  setCache('tourism', result);
  return result;
}

// Fetch single tourism
export async function fetchTourismById(id: string): Promise<Tourism | null> {
  const { data, error } = await supabase
    .from('tourism')
    .select(`
      *,
      villages (
        name
      )
    `)
    .eq('id', id)
    .maybeSingle();

  if (error || !data) {
    console.error('Error fetching tourism:', error);
    return null;
  }

  return {
    id: data.id,
    villageId: data.village_id,
    villageName: data.villages?.name || '',
    name: data.name,
    description: data.description || '',
    image: villageImages[data.village_id] || data.image_url || villageBojong,
    locationLat: Number(data.location_lat) || 0,
    locationLng: Number(data.location_lng) || 0,
    waLink: data.wa_link || '',
    sosmedLink: data.sosmed_link || '',
    facilities: data.facilities || [],
    isActive: data.is_active,
    viewCount: data.view_count,
  };
}

// Categories - now dynamic from database, see useCategories hook
// Keeping static fallback for backward compatibility
export const categories = [
  { id: 'kuliner', name: 'Kuliner', icon: 'utensils', colorClass: 'category-kuliner' },
  { id: 'sembako', name: 'Sembako', icon: 'shopping-basket', colorClass: 'category-kuliner' },
  { id: 'kriya', name: 'Produk Desa', icon: 'shapes', colorClass: 'category-kriya' },
  { id: 'wisata', name: 'Wisata', icon: 'map-location-dot', colorClass: 'category-wisata' },
  { id: 'jasa', name: 'Jasa', icon: 'wrench', colorClass: 'category-wisata' },
  { id: 'pertanian', name: 'Pertanian', icon: 'sprout', colorClass: 'category-wisata' },
  { id: 'peternakan', name: 'Peternakan & Perikanan', icon: 'wheat', colorClass: 'category-wisata' },
] as const;
