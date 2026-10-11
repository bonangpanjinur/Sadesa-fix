import { useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { trackVisitorRoute } from '@/lib/pageViewTracker';

const MANAGED_META_NAMES = ['google-site-verification', 'msvalidate.01'];
const MANAGED_ELEMENT_IDS = ['sadesa-ga4-script', 'sadesa-ga4-config', 'sadesa-gtm-script', 'sadesa-global-schema'];

type AppSetting = { key: string; value: unknown };

function settingString(settings: AppSetting[], key: string): string {
  const value = settings.find((setting) => setting.key === key)?.value;
  return typeof value === 'string' ? value.trim() : '';
}

function normalizeVerification(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) return '';

  // Accept either the token or a complete verification meta tag pasted from
  // Google's dashboard, while storing and publishing only the content value.
  const contentMatch = trimmed.match(/content=["']([^"']+)["']/i);
  return contentMatch?.[1]?.trim() || trimmed.replace(/^google-site-verification\s*=\s*/i, '').trim();
}

function isValidMeasurementId(value: string): boolean {
  return /^G-[A-Z0-9]+$/i.test(value);
}

function isValidTagManagerId(value: string): boolean {
  return /^GTM-[A-Z0-9]+$/i.test(value);
}

function removeManagedHeadElements() {
  MANAGED_META_NAMES.forEach((name) => {
    document.querySelector(`meta[name="${name}"]`)?.remove();
  });
  MANAGED_ELEMENT_IDS.forEach((id) => document.getElementById(id)?.remove());
}

function upsertMeta(name: string, content: string) {
  if (!content) return;
  const element = document.createElement('meta');
  element.name = name;
  element.content = content;
  element.dataset.sadesaManaged = 'true';
  document.head.appendChild(element);
}

function installAnalytics(settings: AppSetting[]) {
  const ga4Id = settingString(settings, 'seo_ga4_measurement_id').toUpperCase();
  const gtmId = settingString(settings, 'seo_gtm_id').toUpperCase();

  if (isValidMeasurementId(ga4Id)) {
    const script = document.createElement('script');
    script.id = 'sadesa-ga4-script';
    script.async = true;
    script.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(ga4Id)}`;
    document.head.appendChild(script);

    const config = document.createElement('script');
    config.id = 'sadesa-ga4-config';
    config.textContent = `window.dataLayer = window.dataLayer || []; function gtag(){dataLayer.push(arguments);} gtag('js', new Date()); gtag('config', '${ga4Id}', { send_page_view: false });`;
    document.head.appendChild(config);

    window.dispatchEvent(new CustomEvent('sadesa-analytics-ready', { detail: { measurementId: ga4Id } }));
  }

  // GTM is optional. Keep it separate from the GA4 element so an admin can
  // configure either provider without creating duplicate script tags.
  if (isValidTagManagerId(gtmId)) {
    const script = document.createElement('script');
    script.id = 'sadesa-gtm-script';
    script.async = true;
    script.src = `https://www.googletagmanager.com/gtm.js?id=${encodeURIComponent(gtmId)}`;
    document.head.appendChild(script);
  }
}

function updatePageView(path: string) {
  const ga4Id = document.getElementById('sadesa-ga4-script')
    ? document.querySelector<HTMLScriptElement>('#sadesa-ga4-script')?.src.match(/[?&]id=([^&]+)/i)?.[1]
    : null;
  if (!ga4Id) return;

  const win = window as Window & { gtag?: (...args: unknown[]) => void };
  win.gtag?.('config', decodeURIComponent(ga4Id), { page_path: path, page_title: document.title });
}

export const SEO = () => {
  const location = useLocation();

  useEffect(() => {
    void trackVisitorRoute(location.pathname, document.title);
  }, [location.pathname]);

  useEffect(() => {
    let cancelled = false;

    const updateSEO = async () => {
      try {
        const [seoResult, toolsResult] = await Promise.all([
          supabase
            .from('seo_settings')
            .select('*')
            .eq('page_path', location.pathname)
            .maybeSingle(),
          supabase
            .from('app_settings')
            .select('key,value')
            .in('key', [
              'seo_google_verification',
              'seo_bing_verification',
              'seo_ga4_measurement_id',
              'seo_gtm_id',
              'seo_global_schema',
              'seo_global_title',
              'seo_global_description',
              'seo_global_keywords',
              'seo_global_robots',
              'seo_global_canonical_url',
              'seo_global_og_title',
              'seo_global_og_description',
              'seo_global_og_image',
              'seo_global_twitter_title',
              'seo_global_twitter_description',
              'seo_global_twitter_image',
            ]),
        ]);

        if (cancelled) return;
        if (seoResult.error) console.warn('SEO page settings unavailable:', seoResult.error.message);
        if (toolsResult.error) console.warn('SEO tools settings unavailable:', toolsResult.error.message);

        const data = seoResult.data;
        const toolSettings = (toolsResult.data || []) as AppSetting[];

        // Replace only tags/scripts owned by SaDesa, preserving other metadata
        // injected by the host or browser extensions.
        removeManagedHeadElements();
        upsertMeta('google-site-verification', normalizeVerification(settingString(toolSettings, 'seo_google_verification')));
        upsertMeta('msvalidate.01', normalizeVerification(settingString(toolSettings, 'seo_bing_verification')));
        installAnalytics(toolSettings);

        const globalSchema = settingString(toolSettings, 'seo_global_schema');
        if (globalSchema) {
          try {
            const schema = JSON.parse(globalSchema) as object;
            const script = document.createElement('script');
            script.id = 'sadesa-global-schema';
            script.type = 'application/ld+json';
            script.textContent = JSON.stringify(schema);
            document.head.appendChild(script);
          } catch {
            console.warn('Invalid global SEO schema JSON was ignored.');
          }
        }

        const globalMeta = {
          title: settingString(toolSettings, 'seo_global_title'),
          description: settingString(toolSettings, 'seo_global_description'),
          keywords: settingString(toolSettings, 'seo_global_keywords'),
          robots: settingString(toolSettings, 'seo_global_robots'),
          canonicalUrl: settingString(toolSettings, 'seo_global_canonical_url'),
          ogTitle: settingString(toolSettings, 'seo_global_og_title'),
          ogDescription: settingString(toolSettings, 'seo_global_og_description'),
          ogImage: settingString(toolSettings, 'seo_global_og_image'),
          twitterTitle: settingString(toolSettings, 'seo_global_twitter_title'),
          twitterDescription: settingString(toolSettings, 'seo_global_twitter_description'),
          twitterImage: settingString(toolSettings, 'seo_global_twitter_image'),
        };

        const updateMeta = (name: string, content: string | null, isProperty = false) => {
            if (!content) return;
            let element = isProperty
              ? document.querySelector(`meta[property="${name}"]`)
              : document.querySelector(`meta[name="${name}"]`);

            if (!element) {
              element = document.createElement('meta');
              if (isProperty) element.setAttribute('property', name);
              else element.setAttribute('name', name);
              document.head.appendChild(element);
            }
            element.setAttribute('content', content);
        };

        const title = data?.title || globalMeta.title;
        const description = data?.description || globalMeta.description;
        const keywords = data?.keywords || globalMeta.keywords;
        const robots = data?.robots || globalMeta.robots;
        const ogTitle = data?.og_title || data?.title || globalMeta.ogTitle || title;
        const ogDescription = data?.og_description || data?.description || globalMeta.ogDescription || description;
        const ogImage = data?.og_image || globalMeta.ogImage;
        const twitterTitle = globalMeta.twitterTitle || ogTitle;
        const twitterDescription = globalMeta.twitterDescription || ogDescription;
        const twitterImage = globalMeta.twitterImage || ogImage;

        if (title) document.title = title;
        updateMeta('description', description);
        updateMeta('keywords', keywords);
        updateMeta('robots', robots);
        updateMeta('og:title', ogTitle, true);
        updateMeta('og:description', ogDescription, true);
        updateMeta('og:image', ogImage, true);
        updateMeta('twitter:card', twitterImage ? 'summary_large_image' : 'summary');
        updateMeta('twitter:title', twitterTitle);
        updateMeta('twitter:description', twitterDescription);
        updateMeta('twitter:image', twitterImage);

        const canonicalUrl = data?.canonical_url || globalMeta.canonicalUrl;
        if (canonicalUrl) {
          let canonical = document.querySelector('link[rel="canonical"]');
          if (!canonical) {
            canonical = document.createElement('link');
            canonical.setAttribute('rel', 'canonical');
            document.head.appendChild(canonical);
          }
          canonical.setAttribute('href', canonicalUrl);
        }

        updatePageView(location.pathname);
      } catch (error) {
        console.error('Error updating SEO tags:', error);
      }
    };

    void updateSEO();
    return () => {
      cancelled = true;
    };
  }, [location.pathname]);

  return null;
};
