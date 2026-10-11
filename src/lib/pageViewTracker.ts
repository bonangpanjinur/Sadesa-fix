import { supabase } from '@/integrations/supabase/client';

const trackedPages = new Set<string>();
const VISITOR_ID_KEY = 'sadesa_visitor_id';

function getVisitorId(): string {
  try {
    const current = window.localStorage.getItem(VISITOR_ID_KEY);
    if (current && /^[a-zA-Z0-9_-]{16,128}$/.test(current)) return current;
    const next = `${crypto.randomUUID().replaceAll('-', '')}${Date.now().toString(36)}`;
    window.localStorage.setItem(VISITOR_ID_KEY, next);
    return next;
  } catch {
    return `${crypto.randomUUID().replaceAll('-', '')}${Date.now().toString(36)}`;
  }
}

/** Tracks a public route. Network metadata is captured only by the Edge Function. */
export async function trackVisitorRoute(path: string, pageTitle = document.title) {
  if (!path.startsWith('/') || path.startsWith('/admin') || path.startsWith('/auth')) return;
  if (trackedPages.has(path)) return;
  trackedPages.add(path);
  try {
    const { error } = await supabase.functions.invoke('track-visitor', {
      body: { path, page_title: pageTitle, referrer: document.referrer || null, visitor_id: getVisitorId() },
    });
    if (error) console.warn('Visitor analytics unavailable:', error.message);
  } catch (error) {
    console.warn('Visitor analytics tracking error:', error);
  }
}

export async function trackPageView(options: {
  merchantId?: string;
  productId?: string;
  pageType: 'store' | 'product';
}) {
  const key = `${options.pageType}-${options.merchantId || ''}-${options.productId || ''}`;
  
  if (trackedPages.has(key)) return;
  trackedPages.add(key);

  try {
    const { data: { user } } = await supabase.auth.getUser();
    
    await supabase.from('page_views').insert({
      merchant_id: options.merchantId || null,
      product_id: options.productId || null,
      viewer_id: user?.id || null,
      page_type: options.pageType,
    });
  } catch (error) {
    console.error('Page view tracking error:', error);
  }
}
