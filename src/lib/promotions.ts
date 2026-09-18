import { supabase } from '@/integrations/supabase/client';

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

// Fetch active promotions by type
export async function fetchPromotions(type?: Promotion['type']): Promise<Promotion[]> {
  let query = supabase
    .from('promotions')
    .select('*')
    .order('sort_order', { ascending: true });

  if (type) {
    query = query.eq('type', type);
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
