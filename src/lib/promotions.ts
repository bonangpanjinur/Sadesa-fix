import { supabase } from '@/integrations/supabase/client';
import { getMerchantOperatingStatus, type OperatingDaySchedule } from '@/lib/merchantOperatingHours';

export interface Promotion {
  id: string;
  type: 'banner' | 'wisata_populer' | 'produk_populer' | 'promo_spesial';
  title: string | null;
  subtitle?: string;
  imageUrl?: string;
  linkUrl?: string;
  linkType?: string;
  linkId?: string;
  advertiserType?: string;
  advertiserId?: string;
  categoryId?: string | null;
  startDate: string;
  endDate?: string;
  sortOrder: number;
  viewCount: number;
  clickCount: number;
}

export interface MerchantAd {
  id: string;
  merchantId: string;
  merchantName: string;
  title: string;
  description?: string;
  imageUrl?: string;
  linkUrl?: string;
  placementType: string;
  viewCount: number;
  clickCount: number;
  merchantIsOpen: boolean;
  locationLat?: number | null;
  locationLng?: number | null;
}

async function getMerchantOpenStatuses(merchantIds: string[]): Promise<Map<string, boolean>> {
  const uniqueIds = [...new Set(merchantIds)];
  if (uniqueIds.length === 0) return new Map();
  const [{ data: merchants, error: merchantsError }, { data: weeklyHours, error: hoursError }] = await Promise.all([
    supabase.from('merchants').select('id, is_open, open_time, close_time').in('id', uniqueIds),
    supabase
      .from('merchant_operating_hours')
      .select('merchant_id, day_of_week, open_time, close_time, is_closed')
      .in('merchant_id', uniqueIds),
  ]);
  if (merchantsError) throw merchantsError;
  if (hoursError) throw hoursError;

  const schedulesByMerchant = new Map<string, OperatingDaySchedule[]>();
  for (const row of weeklyHours || []) {
    const schedule = schedulesByMerchant.get(row.merchant_id) || [];
    schedule.push({
      day_of_week: row.day_of_week,
      open_time: row.open_time,
      close_time: row.close_time,
      is_closed: row.is_closed,
    });
    schedulesByMerchant.set(row.merchant_id, schedule);
  }

  return new Map((merchants || []).map((merchant) => [
    merchant.id,
    getMerchantOperatingStatus(
      merchant.is_open,
      merchant.open_time,
      merchant.close_time,
      schedulesByMerchant.get(merchant.id),
    ).isCurrentlyOpen,
  ]));
}

export async function fetchActiveHomepageAds(): Promise<MerchantAd[]> {
  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from('merchant_ads')
    .select('id, merchant_id, title, description, image_url, link_url, placement_type, view_count, click_count, merchant:merchant_id(name, is_open, open_time, close_time, location_lat, location_lng)')
    .eq('placement_type', 'home_banner')
    .eq('status', 'active')
    .or(`start_date.is.null,start_date.lte.${now}`)
    .or(`end_date.is.null,end_date.gt.${now}`)
    .order('created_at', { ascending: false });

  if (error) {
    console.error('Error fetching active homepage ads:', error);
    return [];
  }

  let openStatuses: Map<string, boolean>;
  try {
    openStatuses = await getMerchantOpenStatuses((data || []).map((ad) => ad.merchant_id));
  } catch (statusError) {
    console.error('Unable to verify merchant operating hours for homepage ads:', statusError);
    return [];
  }

  return (data || []).flatMap((ad) => {
    const merchant = Array.isArray(ad.merchant) ? ad.merchant[0] : ad.merchant;
    if (!merchant || !openStatuses.get(ad.merchant_id)) return [];
    return [{
      id: ad.id,
      merchantId: ad.merchant_id,
      merchantName: merchant.name || 'Merchant sponsor',
      title: ad.title,
      description: ad.description || undefined,
      imageUrl: ad.image_url || undefined,
      linkUrl: ad.link_url || undefined,
      placementType: ad.placement_type,
      viewCount: ad.view_count || 0,
      clickCount: ad.click_count || 0,
      merchantIsOpen: true,
      locationLat: merchant.location_lat == null ? null : Number(merchant.location_lat),
      locationLng: merchant.location_lng == null ? null : Number(merchant.location_lng),
    }];
  });
}

// Fetch active promotions by type
export async function fetchPromotions(type?: Promotion['type'], categoryId?: string | null): Promise<Promotion[]> {
  const now = new Date().toISOString();
  let query = supabase
    .from('promotions')
    .select('*')
    .order('sort_order', { ascending: true });

  if (type) {
    query = query.eq('type', type);
  }

  // RLS hides unpublished promotions for public users, but admins can read
  // every row. Keep the homepage behavior identical for all logged-in roles.
  if (type === 'banner') {
    query = query
      .eq('is_active', true)
      .eq('is_approved', true)
      .lte('start_date', now)
      .or(`end_date.is.null,end_date.gte.${now}`);
    query = categoryId ? query.eq('category_id', categoryId) : query.is('category_id', null);
  }

  const { data, error } = await query;

  if (error) {
    console.error('Error fetching promotions:', error);
    return [];
  }

  return (data || []).map(p => ({
    id: p.id,
    type: p.type as Promotion['type'],
    title: p.title,
    subtitle: p.subtitle || undefined,
    imageUrl: p.image_url || undefined,
    linkUrl: p.link_url || undefined,
    linkType: p.link_type || undefined,
    linkId: p.link_id || undefined,
    advertiserType: p.advertiser_type || undefined,
    advertiserId: p.advertiser_id || undefined,
    categoryId: p.category_id || null,
    startDate: p.start_date,
    endDate: p.end_date || undefined,
    sortOrder: p.sort_order,
    viewCount: p.view_count,
    clickCount: p.click_count,
  }));
}

// Fetch banner promotions specifically
export async function fetchBannerPromotions(): Promise<Promotion[]> {
  const adminBanners = await fetchPromotions('banner', null);
  const now = new Date().toISOString();
  const { data: merchantAds, error } = await supabase
    .from('merchant_ads')
    .select('id, title, description, image_url, link_url, merchant_id, start_date, end_date, sort_order, view_count, click_count')
    .eq('placement_type', 'home_banner')
    .eq('status', 'active')
    .lte('start_date', now)
    .or(`end_date.is.null,end_date.gte.${now}`)
    .order('sort_order', { ascending: true })
    .limit(10);

  if (error) {
    console.warn('Error fetching merchant banner ads:', error);
    return adminBanners;
  }

  let openStatuses: Map<string, boolean>;
  try {
    openStatuses = await getMerchantOpenStatuses((merchantAds || []).map((ad) => ad.merchant_id));
  } catch (statusError) {
    console.error('Unable to verify merchant operating hours for banner ads:', statusError);
    return adminBanners;
  }

  const paidBanners: Promotion[] = (merchantAds || [])
    .filter((ad) => openStatuses.get(ad.merchant_id))
    .map((ad) => ({
    id: `merchant-ad-${ad.id}`,
    type: 'banner',
    title: ad.title,
    subtitle: ad.description || undefined,
    imageUrl: ad.image_url || undefined,
    linkUrl: ad.link_url || `/merchant/${ad.merchant_id}`,
    linkType: 'merchant',
    advertiserType: 'merchant',
    advertiserId: ad.merchant_id,
    startDate: ad.start_date,
    endDate: ad.end_date || undefined,
    sortOrder: ad.sort_order || 0,
    viewCount: ad.view_count || 0,
    clickCount: ad.click_count || 0,
    }));

  return [...paidBanners, ...adminBanners];
}

export async function fetchCategoryBannerPromotions(categoryId: string): Promise<Promotion[]> {
  return fetchPromotions('banner', categoryId);
}

export async function incrementPromotionView(id: string): Promise<void> {
  const isMerchantAd = id.startsWith('merchant-ad-');
  const rpc = isMerchantAd ? 'increment_merchant_ad_view' : 'increment_promotion_view';
  const { error } = await supabase.rpc(rpc, { [isMerchantAd ? 'p_ad_id' : 'p_promotion_id']: isMerchantAd ? id.replace('merchant-ad-', '') : id });
  if (error) console.warn('Unable to record banner view:', error.message);
}

export async function incrementPromotionClick(id: string): Promise<void> {
  const isMerchantAd = id.startsWith('merchant-ad-');
  const rpc = isMerchantAd ? 'increment_merchant_ad_click' : 'increment_promotion_click';
  const { error } = await supabase.rpc(rpc, { [isMerchantAd ? 'p_ad_id' : 'p_promotion_id']: isMerchantAd ? id.replace('merchant-ad-', '') : id });
  if (error) console.warn('Unable to record banner click:', error.message);
}
