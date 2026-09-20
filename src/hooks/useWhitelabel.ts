import { useCallback, useEffect, useRef, useState, createContext, useContext } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { setBaseUrl } from '@/lib/addressApi';

interface PWAIcon {
  src: string;
  sizes: string;
  type: string;
  purpose?: string;
}

interface PWAConfig {
  appName: string;
  shortName: string;
  description: string;
  themeColor: string;
  backgroundColor: string;
  icons: PWAIcon[];
}

interface WhitelabelSettings {
  siteName: string;
  siteTagline: string;
  companyLegalName: string;
  logoUrl: string;
  faviconUrl: string;
  pwa?: PWAConfig;
}

const DEFAULT_LOGO_URL = '/branding/sadesa-logo.png';
const DEFAULT_ICON_URL = '/branding/sadesa-favicon.png';
const DEFAULT_PWA_ICONS: PWAIcon[] = [
  { src: '/branding/sadesa-icon-192.png', sizes: '192x192', type: 'image/png' },
  { src: '/branding/sadesa-icon-512.png', sizes: '512x512', type: 'image/png' },
];

const defaultSettings: WhitelabelSettings = {
  siteName: 'SaDesa',
  siteTagline: 'EKOSISTEM UMKM',
  companyLegalName: '',
  logoUrl: DEFAULT_LOGO_URL,
  faviconUrl: DEFAULT_ICON_URL,
  pwa: {
    appName: 'SaDesa - Marketplace UMKM & Desa Wisata',
    shortName: 'SaDesa',
    description: 'Jelajahi produk UMKM asli desa dan destinasi wisata desa di Indonesia',
    themeColor: '#10b981',
    backgroundColor: '#ffffff',
    icons: DEFAULT_PWA_ICONS,
  },
};

interface WhitelabelContextType {
  settings: WhitelabelSettings;
  loading: boolean;
  refetch: () => Promise<void>;
}

const WhitelabelContext = createContext<WhitelabelContextType | undefined>(undefined);

function upsertMeta(name: string, content: string): void {
  let meta = document.querySelector(`meta[name="${name}"]`) as HTMLMetaElement | null;
  if (!meta) {
    meta = document.createElement('meta');
    meta.name = name;
    document.head.appendChild(meta);
  }
  meta.content = content;
}

function upsertLink(rel: string, href: string, type?: string): HTMLLinkElement {
  let link = document.querySelector(`link[rel="${rel}"]`) as HTMLLinkElement | null;
  if (!link) {
    link = document.createElement('link');
    link.rel = rel;
    document.head.appendChild(link);
  }
  link.href = href;
  if (type) link.type = type;
  return link;
}

function applyBrandingHead(settings: WhitelabelSettings, previousManifestUrl: string | null): string | null {
  document.title = settings.siteName;
  upsertLink('icon', settings.faviconUrl, 'image/png');
  upsertLink('apple-touch-icon', settings.pwa?.icons.find(icon => icon.sizes === '180x180')?.src ?? settings.faviconUrl, 'image/png');
  upsertMeta('application-name', settings.siteName);
  upsertMeta('apple-mobile-web-app-title', settings.pwa?.shortName ?? settings.siteName);
  upsertMeta('theme-color', settings.pwa?.themeColor ?? '#10b981');

  if (!settings.pwa) return previousManifestUrl;

  // A manifest loaded from a blob URL has an opaque origin. Relative URLs in
  // that manifest (including start_url, scope, and icon src) are therefore
  // invalid in Chromium. Resolve every URL against the real application origin
  // before serialising the dynamic manifest.
  const resolveManifestUrl = (value: string): string => {
    try {
      return new URL(value, window.location.href).href;
    } catch {
      return value;
    }
  };
  const manifest = {
    name: settings.pwa.appName || settings.siteName,
    short_name: settings.pwa.shortName || settings.siteName,
    description: settings.pwa.description,
    start_url: new URL('/', window.location.origin).href,
    scope: new URL('/', window.location.origin).href,
    display: 'standalone',
    theme_color: settings.pwa.themeColor,
    background_color: settings.pwa.backgroundColor,
    icons: settings.pwa.icons.map((icon) => ({ ...icon, src: resolveManifestUrl(icon.src) })),
  };
  const manifestUrl = URL.createObjectURL(new Blob([JSON.stringify(manifest)], { type: 'application/manifest+json' }));
  upsertLink('manifest', manifestUrl, 'application/manifest+json');
  if (previousManifestUrl) URL.revokeObjectURL(previousManifestUrl);
  return manifestUrl;
}

export function useWhitelabel() {
  const context = useContext(WhitelabelContext);
  if (!context) {
    return {
      settings: defaultSettings,
      loading: false,
      refetch: async () => {},
    };
  }
  return context;
}

export function useWhitelabelProvider() {
  const [settings, setSettings] = useState<WhitelabelSettings>(defaultSettings);
  const [loading, setLoading] = useState(true);
  const manifestUrlRef = useRef<string | null>(null);

  const fetchSettings = useCallback(async () => {
    try {
      const { data, error } = await supabase
        .from('app_settings')
        .select('key, value, category');

      if (error) throw error;

      const newSettings: WhitelabelSettings = {
        ...defaultSettings,
        pwa: defaultSettings.pwa ? { ...defaultSettings.pwa, icons: [...defaultSettings.pwa.icons] } : undefined,
      };

      data?.forEach((item) => {
        if (item.category === 'whitelabel') {
          if (item.key === 'site_name' && item.value) newSettings.siteName = String(item.value);
          if (item.key === 'site_tagline' && item.value) newSettings.siteTagline = String(item.value);
          if (item.key === 'company_legal_name' && item.value) newSettings.companyLegalName = String(item.value);
          if (item.key === 'logo_url' && item.value) newSettings.logoUrl = String(item.value);
          if (item.key === 'favicon_url' && item.value) newSettings.faviconUrl = String(item.value);
        }
        if (item.category === 'pwa' && item.key === 'pwa_config' && typeof item.value === 'object' && item.value !== null) {
          const storedPwa = item.value as unknown as Partial<PWAConfig>;
          newSettings.pwa = {
            ...newSettings.pwa,
            ...storedPwa,
            icons: storedPwa.icons?.length ? storedPwa.icons : (newSettings.pwa?.icons ?? DEFAULT_PWA_ICONS),
          } as PWAConfig;
        }
        if (item.key === 'address_api' && item.value && typeof item.value === 'object') {
          const addressApi = item.value as unknown as { base_url?: string };
          if (addressApi.base_url) setBaseUrl(addressApi.base_url);
        }
      });

      setSettings(newSettings);
      manifestUrlRef.current = applyBrandingHead(newSettings, manifestUrlRef.current);
    } catch (error) {
      console.error('Error fetching whitelabel settings:', error);
      setSettings(defaultSettings);
      manifestUrlRef.current = applyBrandingHead(defaultSettings, manifestUrlRef.current);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void fetchSettings();
    return () => {
      if (manifestUrlRef.current) URL.revokeObjectURL(manifestUrlRef.current);
    };
  }, [fetchSettings]);

  return {
    settings,
    loading,
    refetch: fetchSettings,
  };
}

export { WhitelabelContext, defaultSettings };
export type { PWAConfig, PWAIcon, WhitelabelSettings };
