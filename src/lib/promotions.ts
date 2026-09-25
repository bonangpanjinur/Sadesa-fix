import { supabase } from '@/integrations/supabase/client';
import { isWithinOperatingHours } from '@/lib/merchantOperatingHours';

export interface Promotion {
  id: string;
  type: 'banner' | 'wisata_populer' | 'produk_populer' | 'promo_spesial';
  title: string;
  subtitle?: string;
  imageUrl?: string;
  linkUrl?: string;
  linkType?: string;
  linkId?: string;
  advertiserType?: string;
  advertiserId?: string;
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

  return (data || []).flatMap((ad) => {
    const merchant = Array.isArray(ad.merchant) ? ad.merchant[0] : ad.merchant;
    if (!merchant?.is_open || !isWithinOperatingHours(merchant.open_time || '08:00', merchant.close_time || '17:00')) return [];
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
export async function fetchPromotions(type?: Promotion['type']): Promise<Promotion[]> {
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
    startDate: p.start_date,
    endDate: p.end_date || undefined,
    sortOrder: p.sort_order,
    viewCount: p.view_count,
    clickCount: p.click_count,
  }));
}

// Fetch banner promotions specifically
export async function fetchBannerPromotions(): Promise<Promotion[]> {
  const adminBanners = await fetchPromotions('banner');
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

  const paidBanners: Promotion[] = (merchantAds || []).map((ad) => ({
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
