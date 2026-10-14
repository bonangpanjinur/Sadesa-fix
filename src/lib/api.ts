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
async function getMerchantsWithActiveQuota(merchantScopeIds: string[]): Promise<Set<string>> {
  if (merchantScopeIds.length === 0) return new Set();
  const { data: walletGate, error: walletGateError } = await supabase.rpc(
    'get_merchant_wallet_gate' as never,
    { p_merchant_ids: merchantScopeIds } as never,
  );
  if (walletGateError && !['PGRST202', '42883'].includes(walletGateError.code)) {
    throw new Error(`Unable to check merchant wallet gate: ${walletGateError.message}`);
  }
  const walletGateRows = (walletGate ?? []) as unknown as Array<{ is_enabled: boolean; merchant_id: string | null }>;
  if (!walletGateError && walletGateRows.some((row) => row.is_enabled)) {
    return new Set(walletGateRows.flatMap((row) => row.merchant_id ? [row.merchant_id] : []));
  }
  // Scope every quota lookup to merchants represented by the current page.
  const [FREE_TIER_LIMIT, merchantsRes, subsRes] = await Promise.all([
    getFreeTierLimit(),
    supabase
      .from('merchants')
      .select('id')
      .in('id', merchantScopeIds)
      .eq('status', 'ACTIVE')
      .eq('registration_status', 'APPROVED'),
    supabase
      .from('merchant_subscriptions')
      .select('merchant_id, transaction_quota, used_quota')
      .in('merchant_id', merchantScopeIds)
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
    const { data: walletGate, error: walletGateError } = await supabase.rpc(
      'get_merchant_wallet_gate' as never,
      { p_merchant_ids: [merchantId] } as never,
    );
    if (walletGateError && !['PGRST202', '42883'].includes(walletGateError.code)) {
      console.error('Unable to check merchant wallet gate:', walletGateError);
      return false;
    }
    const walletGateRows = (walletGate ?? []) as unknown as Array<{ is_enabled: boolean; merchant_id: string | null }>;
    if (!walletGateError && walletGateRows.some((row) => row.is_enabled)) {
      return walletGateRows.some((row) => row.merchant_id === merchantId);
    }
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
  offset?: number;
  includeReviews?: boolean;
  cacheKey?: string;
  search?: string;
  categoryIds?: string[] | null;
  /** Slug fallback for legacy product rows whose category_id is null. */
  categorySlugs?: string[] | null;
  merchantId?: string | null;
  createdAfter?: string;
  promoOnly?: boolean;
  inStockOnly?: boolean;
  maxPrice?: number;
  sort?: 'nearest' | 'cheapest' | 'expensive' | 'newest' | 'best-selling';
}

export interface ProductPage {
  products: Product[];
  hasMore: boolean;
  total: number | null;
}

interface CatalogMerchant {
  id?: string;
  name?: string | null;
  image_url?: string | null;
  slug?: string | null;
  address?: string | null;
  rating_avg?: number | null;
  rating_count?: number | null;
  is_open?: boolean | null;
  open_time?: string | null;
  close_time?: string | null;
  location_lat?: number | null;
  location_lng?: number | null;
  reviews?: Array<{ id: string; rating: number; comment?: string | null; created_at: string; is_visible?: boolean | null }>;
  villages?: { name?: string | null; location_lat?: number | null; location_lng?: number | null } | null;
}

export async function fetchProductCategoryCounts(): Promise<Record<string, number>> {
  const { data, error } = await supabase.rpc('get_product_category_counts' as never);
  if (error) throw error;
  return Object.fromEntries(((data || []) as Array<{ category_id: string; product_count: number }>).map((row) => [row.category_id, Number(row.product_count)]));
}

// Fetch products from database (include availability status and location).
// Homepage callers can request a smaller payload because review details are not
// rendered in product cards.
export async function fetchProducts(options: FetchProductsOptions = {}): Promise<Product[]> {
  const page = await fetchProductPage(options);
  return page.products;
}

export async function fetchProductPage(options: FetchProductsOptions = {}): Promise<ProductPage> {
  const {
    limit = 24,
    offset = 0,
    includeReviews = false,
    cacheKey = 'products',
    search = '',
    categoryIds,
    categorySlugs,
    merchantId,
    createdAfter,
    promoOnly = false,
    inStockOnly = false,
    maxPrice,
    sort = 'newest',
  } = options;
  const normalizedLimit = Math.min(Math.max(limit, 1), 48);
  const cacheSuffix = JSON.stringify({ offset, normalizedLimit, search, categoryIds, categorySlugs, merchantId, createdAfter, promoOnly, inStockOnly, maxPrice, sort });
  const cacheKeyWithParams = `${cacheKey}:${cacheSuffix}`;
  const cached = getCached<ProductPage>(cacheKeyWithParams);
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
  let query = supabase
    .from('products')
    .select(`id, merchant_id, name, description, price, stock, category, category_id, image_url, is_active, is_promo, discount_percent, sold_count, created_at, merchants (${merchantFields})`, { count: 'exact' })
    .eq('is_active', true);
  let merchantSearchIds: string[] = [];
  if (search.trim()) {
    const term = `%${search.trim().replace(/[%(),]/g, ' ')}%`;
    const { data: matchingMerchants } = await supabase.from('merchants').select('id').ilike('name', term).limit(50);
    merchantSearchIds = (matchingMerchants || []).map((merchant) => merchant.id);
    const merchantClause = merchantSearchIds.length ? `,merchant_id.in.(${merchantSearchIds.join(',')})` : '';
    query = query.or(`name.ilike.${term},description.ilike.${term},category.ilike.${term}${merchantClause}`);
  }
  const safeCategorySlugs = (categorySlugs || []).filter((slug) => /^[a-z0-9]+(?:-[a-z0-9]+)*$/i.test(slug));
  // Match the active category tree by ID while retaining old rows that have no category_id.
  if (categoryIds?.length && safeCategorySlugs.length) {
    query = query.or(`category_id.in.(${categoryIds.join(',')}),and(category_id.is.null,category.in.(${safeCategorySlugs.join(',')}))`);
  } else if (categoryIds?.length) {
    query = query.in('category_id', categoryIds);
  } else if (safeCategorySlugs.length) {
    query = query.is('category_id', null).in('category', safeCategorySlugs);
  }
  if (merchantId) query = query.eq('merchant_id', merchantId);
  if (createdAfter) query = query.gte('created_at', createdAfter);
  if (promoOnly) query = query.eq('is_promo', true);
  if (inStockOnly) query = query.gt('stock', 0);
  if (maxPrice != null && maxPrice < 100000) query = query.lte('price', maxPrice);
  if (sort === 'cheapest') query = query.order('price', { ascending: true });
  else if (sort === 'expensive') query = query.order('price', { ascending: false });
  else if (sort === 'best-selling') {
    query = query
      .order('sold_count', { ascending: false })
      .order('created_at', { ascending: false });
  }
  else query = query.order('created_at', { ascending: false });
  query = query.order('id', { ascending: true }).range(offset, offset + normalizedLimit - 1);

  const { data, error, count } = await query;

  if (error) {
    console.error('Error fetching products:', error);
    // Let React Query expose a real error state instead of making a network or
    // database failure look like an empty catalogue.
    throw error;
  }

  // Some products store their photos in the gallery table instead of the
  // legacy products.image_url column. Use the first ordered gallery image for
  // catalogue cards, while keeping the catalogue usable if the optional table
  // is unavailable on an older deployment.
  const galleryImageByProduct = new Map<string, string>();
  const productIds = (data || []).map((item) => item.id).filter(Boolean);
  if (productIds.length > 0) {
    const { data: galleryData, error: galleryError } = await supabase
      .from('product_images')
      .select('product_id, image_url, sort_order')
      .in('product_id', productIds)
      .order('sort_order', { ascending: true });
    if (galleryError) {
      console.warn('Unable to load product gallery images:', galleryError.message);
    } else {
      for (const image of (galleryData || []) as Array<{ product_id: string; image_url: string | null }>) {
        if (image.image_url && !galleryImageByProduct.has(image.product_id)) {
          galleryImageByProduct.set(image.product_id, image.image_url);
        }
      }
    }
  }
  const merchantIds = [...new Set((data || []).map((p) => p.merchant_id).filter(Boolean))];
  const merchantsWithQuota = await getMerchantsWithActiveQuota(merchantIds);
  const weeklyHoursByMerchant = new Map<string, OperatingDaySchedule[]>();
  if (merchantIds.length > 0) {
    const { data: weeklyHours, error: weeklyHoursError } = await supabase
      .from('merchant_operating_hours')
      .select('merchant_id, day_of_week, open_time, close_time, is_closed')
      .in('merchant_id', merchantIds);
    if (weeklyHoursError) {
      throw new Error(`Unable to load merchant operating hours: ${weeklyHoursError.message}`);
    }
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
  }
  const mappedProducts = (data || []).map((rawProduct) => {
    const p = rawProduct;
    const hasQuota = merchantsWithQuota.has(p.merchant_id);
    const merchant = (Array.isArray(p.merchants) ? p.merchants[0] : p.merchants) as CatalogMerchant | null;
    
    // Weekly schedule is canonical; legacy hours are used only when no weekly
    // schedule exists for this merchant.
    const isManuallyOpen = merchant?.is_open ?? true;
    const openTime = merchant?.open_time || '08:00';
    const closeTime = merchant?.close_time || '17:00';
    const isMerchantOpen = getMerchantOperatingStatus(
      isManuallyOpen,
      openTime,
      closeTime,
      weeklyHoursByMerchant.get(p.merchant_id),
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
      image: productImages[p.id] || p.image_url || galleryImageByProduct.get(p.id) || '/placeholder.svg',
      hasImage: Boolean(productImages[p.id] || p.image_url || galleryImageByProduct.get(p.id)),
      category: p.category as Product['category'],
      categoryId: p.category_id || null,
      isActive: p.is_active,
      isPromo,
      isAvailable,
      isMerchantOpen,
      hasQuota,
      unavailableReason,
      locationLat,
      locationLng,
      sold_count: Number(p.sold_count || 0),
    };
  });

  const result = {
    products: mappedProducts,
    hasMore: (count != null ? offset + mappedProducts.length < count : mappedProducts.length === normalizedLimit),
    total: count ?? null,
  };
  setCache(cacheKeyWithParams, result);
  return result;
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

  // Check merchant quota
  const hasQuota = await checkMerchantHasActiveQuota(data.merchant_id);

  const { data: weeklySchedule, error: scheduleError } = await supabase
    .from('merchant_operating_hours')
    .select('day_of_week, open_time, close_time, is_closed')
    .eq('merchant_id', data.merchant_id)
    .order('day_of_week', { ascending: true });
  if (scheduleError) {
    throw new Error(`Unable to load merchant operating hours: ${scheduleError.message}`);
  }

  const isManuallyOpen = data.merchants?.is_open ?? true;
  const openTime = data.merchants?.open_time || '08:00';
  const closeTime = data.merchants?.close_time || '17:00';
  const isMerchantOpen = getMerchantOperatingStatus(
    isManuallyOpen,
    openTime,
    closeTime,
    weeklySchedule as OperatingDaySchedule[] | null,
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
    // Do not show an unrelated local product photo when the merchant has not
    // uploaded an image; the detail gallery can promote product_images instead.
    image: productImages[data.id] || data.image_url || '/placeholder.svg',
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
