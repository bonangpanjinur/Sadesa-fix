import { useState, useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Save, Loader2, Image as ImageIcon, Palette, Globe, Type, Upload, CheckCircle2, Info, RefreshCw, Search, Plus, Edit2, Trash2, Eye, EyeOff, Share2, Layout, GripVertical, BarChart3 } from 'lucide-react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Checkbox } from '@/components/ui/checkbox';
import { Switch } from '@/components/ui/switch';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
  DialogDescription,
} from '@/components/ui/dialog';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { ImageUpload } from '@/components/ui/ImageUpload';
import { useWhitelabel } from '@/hooks/useWhitelabel';
import {
  EMPTY_HOMEPAGE_SERVICE_CARD_IMAGE_OVERRIDES,
  HOMEPAGE_SERVICE_CARDS,
  parseHomepageServiceCardImageOverrides,
} from '@/lib/homeServiceCards';

type JsonValue = string | number | boolean | null | { [key: string]: JsonValue } | JsonValue[];

type BrandingSettingValue = string | null | JsonValue;

interface PWASettings {
  appName: string;
  shortName: string;
  description: string;
  themeColor: string;
  backgroundColor: string;
  enableOffline: boolean;
  enableNotifications: boolean;
  enableInstallPrompt: boolean;
  installPromptDelay: number;
  showInstallBanner: boolean;
  icons: {
    src: string;
    sizes: string;
    type: string;
  }[];
}

interface SEOSetting {
  id: string;
  page_path: string;
  title: string | null;
  description: string | null;
  keywords: string | null;
  og_image: string | null;
  og_title: string | null;
  og_description: string | null;
  canonical_url: string | null;
  robots: string;
}

interface HomepageSection {
  id: string;
  name: string;
  enabled: boolean;
  order: number;
}

interface HomepageLayoutSettings {
  sections: HomepageSection[];
  visible_categories: string[];
}

interface HomepageRecommendationBanner {
  enabled: boolean;
  target: 'courier' | 'merchant';
  eyebrow: string;
  title: string;
  description: string;
  cta: string;
  linkUrl: string;
}

const DEFAULT_RECOMMENDATION_BANNER: HomepageRecommendationBanner = {
  enabled: false,
  target: 'courier',
  eyebrow: 'Bergabung bersama kami',
  title: 'Jadi mitra SaDesa',
  description: 'Daftar sekarang dan dapatkan peluang baru bersama SaDesa.',
  cta: 'Daftar sekarang',
  linkUrl: '/register/courier',
};

const DEFAULT_PWA_SETTINGS: PWASettings = {
  appName: 'SaDesa - Marketplace UMKM & Desa Wisata',
  shortName: 'SaDesa',
  description: 'Jelajahi produk UMKM asli desa dan destinasi wisata desa di Indonesia',
  themeColor: '#10b981',
  backgroundColor: '#ffffff',
  enableOffline: true,
  enableNotifications: true,
  enableInstallPrompt: true,
  installPromptDelay: 30,
  showInstallBanner: true,
  icons: [
    { src: '/branding/sadesa-icon-192.png', sizes: '192x192', type: 'image/png' },
    { src: '/branding/sadesa-icon-512.png', sizes: '512x512', type: 'image/png' },
  ],
};

const COMMON_PAGES = [
  { path: '/', label: 'Beranda' },
  { path: '/products', label: 'Produk' },
  { path: '/tourism', label: 'Wisata' },
  { path: '/shops', label: 'Toko' },
  { path: '/search', label: 'Pencarian' },
  { path: '/auth', label: 'Login' },
];

const DEFAULT_HOMEPAGE_SECTIONS: HomepageSection[] = [
  { id: 'hero', name: 'Hero Banner', enabled: true, order: 0 },
  { id: 'categories', name: 'Kategori', enabled: true, order: 1 },
  { id: 'popular_tourism', name: 'Wisata Populer', enabled: true, order: 2 },
  { id: 'promo', name: 'Promo Spesial', enabled: true, order: 3 },
  { id: 'recommendations', name: 'Rekomendasi Pilihan', enabled: true, order: 4 },
  { id: 'villages', name: 'Jelajahi Desa', enabled: true, order: 5 },
];

// Categories are now loaded dynamically from the database

interface BrandingAppearanceSettingsProps {
  isSaving?: string | null;
  onSave?: (key: string, values: BrandingSettingValue) => Promise<void>;
}

export function BrandingAppearanceSettings({ isSaving: externalIsSaving, onSave }: BrandingAppearanceSettingsProps) {
  const { refetch: refetchWhitelabel } = useWhitelabel();
  const queryClient = useQueryClient();
  
  // Whitelabel State
  const [siteName, setSiteName] = useState('SaDesa');
  const [siteTagline, setSiteTagline] = useState('EKOSISTEM UMKM');
  const [companyLegalName, setCompanyLegalName] = useState('');
  const [logoUrl, setLogoUrl] = useState<string | null>(null);
  const [faviconUrl, setFaviconUrl] = useState<string | null>(null);
  
  // PWA State
  const [pwaSettings, setPwaSettings] = useState<PWASettings>(DEFAULT_PWA_SETTINGS);
  const [uploading, setUploading] = useState<string | null>(null);

  // Google Search Console & Analytics State
  const [googleVerification, setGoogleVerification] = useState('');
  const [ga4MeasurementId, setGa4MeasurementId] = useState('');
  const [gtmId, setGtmId] = useState('');
  
  // SEO State
  const [seoSettings, setSeoSettings] = useState<SEOSetting[]>([]);
  const [seoDialogOpen, setSeoDialogOpen] = useState(false);
  const [editingSeo, setEditingSeo] = useState<SEOSetting | null>(null);
  const [seoSearchTerm, setSeoSearchTerm] = useState('');
  const [seoFormData, setSeoFormData] = useState({
    page_path: '',
    title: '',
    description: '',
    keywords: '',
    og_image: '',
    og_title: '',
    og_description: '',
    canonical_url: '',
    robots: 'index, follow',
  });
  const [globalSeoForm, setGlobalSeoForm] = useState({
    title: '',
    description: '',
    keywords: '',
    robots: 'index, follow',
    canonicalUrl: '',
    ogTitle: '',
    ogDescription: '',
    ogImage: '',
    twitterTitle: '',
    twitterDescription: '',
    twitterImage: '',
  });

  // Homepage Layout State
  const [homepageSections, setHomepageSections] = useState<HomepageSection[]>(DEFAULT_HOMEPAGE_SECTIONS);
  const [visibleCategories, setVisibleCategories] = useState<string[]>([]);
  const [allCategories, setAllCategories] = useState<{id: string; name: string}[]>([]);
  const [draggedIndex, setDraggedIndex] = useState<number | null>(null);
  const [recommendationBanner, setRecommendationBanner] = useState<HomepageRecommendationBanner>(DEFAULT_RECOMMENDATION_BANNER);
  const [homepageServiceCardImages, setHomepageServiceCardImages] = useState({ ...EMPTY_HOMEPAGE_SERVICE_CARD_IMAGE_OVERRIDES });

  // Loading & Saving State
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState<string | null>(null);

  const updatePwaIcon = (size: string, src: string) => {
    setPwaSettings((current) => ({
      ...current,
      icons: current.icons.some((icon) => icon.sizes === size)
        ? current.icons.map((icon) => icon.sizes === size ? { ...icon, src } : icon)
        : [...current.icons, { src, sizes: size, type: 'image/png', purpose: 'any maskable' }],
    }));
  };

  useEffect(() => {
    fetchAllSettings();
  }, []);

  const fetchAllSettings = async () => {
    setLoading(true);
    try {
      // Fetch Whitelabel
      const { data: whitelabelData } = await supabase
        .from('app_settings')
        .select('*')
        .eq('category', 'whitelabel');

      if (whitelabelData) {
        whitelabelData.forEach((item) => {
          if (item.key === 'site_name') setSiteName(String(item.value) || 'SaDesa');
          if (item.key === 'site_tagline') setSiteTagline(String(item.value) || 'EKOSISTEM UMKM');
          if (item.key === 'company_legal_name') setCompanyLegalName(String(item.value) || '');
          if (item.key === 'logo_url') setLogoUrl(item.value ? String(item.value) : null);
          if (item.key === 'favicon_url') setFaviconUrl(item.value ? String(item.value) : null);
        });
      }

      const { data: googleData } = await supabase
        .from('app_settings')
        .select('key, value')
        .in('key', ['seo_google_verification', 'seo_ga4_measurement_id', 'seo_gtm_id']);
      googleData?.forEach((item) => {
        const value = typeof item.value === 'string' ? item.value : '';
        if (item.key === 'seo_google_verification') setGoogleVerification(value);
        if (item.key === 'seo_ga4_measurement_id') setGa4MeasurementId(value);
        if (item.key === 'seo_gtm_id') setGtmId(value);
      });

      const { data: globalSeoData } = await supabase
        .from('app_settings')
        .select('key, value')
        .in('key', [
          'seo_global_title', 'seo_global_description', 'seo_global_keywords', 'seo_global_robots',
          'seo_global_canonical_url', 'seo_global_og_title', 'seo_global_og_description', 'seo_global_og_image',
          'seo_global_twitter_title', 'seo_global_twitter_description', 'seo_global_twitter_image',
        ]);
      const globalSeoValues = new Map((globalSeoData || []).map((item) => [item.key, typeof item.value === 'string' ? item.value : '']));
      setGlobalSeoForm({
        title: globalSeoValues.get('seo_global_title') || '',
        description: globalSeoValues.get('seo_global_description') || '',
        keywords: globalSeoValues.get('seo_global_keywords') || '',
        robots: globalSeoValues.get('seo_global_robots') || 'index, follow',
        canonicalUrl: globalSeoValues.get('seo_global_canonical_url') || '',
        ogTitle: globalSeoValues.get('seo_global_og_title') || '',
        ogDescription: globalSeoValues.get('seo_global_og_description') || '',
        ogImage: globalSeoValues.get('seo_global_og_image') || '',
        twitterTitle: globalSeoValues.get('seo_global_twitter_title') || '',
        twitterDescription: globalSeoValues.get('seo_global_twitter_description') || '',
        twitterImage: globalSeoValues.get('seo_global_twitter_image') || '',
      });

      // Fetch PWA
      const { data: pwaData } = await supabase
        .from('app_settings')
        .select('*')
        .eq('category', 'pwa')
        .eq('key', 'pwa_config')
        .maybeSingle();

      if (pwaData && pwaData.value) {
        setPwaSettings({ ...DEFAULT_PWA_SETTINGS, ...(pwaData.value as unknown as Partial<PWASettings>) });
      }

      // Fetch SEO
      const { data: seoData } = await supabase
        .from('seo_settings')
        .select('*')
        .order('page_path');
      setSeoSettings(seoData || []);

      // Fetch Homepage Layout and Dynamic Categories in parallel
      const [layoutRes, categoriesRes, recommendationRes, serviceCardImagesRes] = await Promise.all([
        supabase.from('app_settings').select('value').eq('key', 'homepage_layout').maybeSingle(),
        supabase.from('categories').select('id, name, slug').eq('is_active', true).order('sort_order'),
        supabase.from('app_settings').select('value').eq('key', 'homepage_recommendation_banner').maybeSingle(),
        supabase.from('app_settings').select('value').eq('key', 'homepage_service_card_images').maybeSingle(),
      ]);

      const cats = (categoriesRes.data || []).map(c => ({ id: c.slug, name: c.name }));
      setAllCategories(cats);

      if (layoutRes.data?.value) {
        const settings = layoutRes.data.value as unknown as HomepageLayoutSettings;
        if (settings.sections) setHomepageSections(settings.sections.sort((a, b) => a.order - b.order));
        if (settings.visible_categories) {
          setVisibleCategories(settings.visible_categories);
        } else {
          setVisibleCategories(cats.map(c => c.id));
        }
      } else {
        setVisibleCategories(cats.map(c => c.id));
      }
      if (recommendationRes.data?.value && typeof recommendationRes.data.value === 'object' && !Array.isArray(recommendationRes.data.value)) {
        setRecommendationBanner({ ...DEFAULT_RECOMMENDATION_BANNER, ...(recommendationRes.data.value as unknown as Partial<HomepageRecommendationBanner>) });
      }
      setHomepageServiceCardImages(parseHomepageServiceCardImageOverrides(serviceCardImagesRes.data?.value));
    } catch (error) {
      console.error('Error fetching settings:', error);
      toast.error('Gagal memuat beberapa pengaturan');
    } finally {
      setLoading(false);
    }
  };

  const handleSaveWhitelabel = async () => {
    setSaving('whitelabel');
    try {
      const saveSetting = async (key: string, value: string | null) => {
        const { data: existing } = await supabase
          .from('app_settings')
          .select('id')
          .eq('key', key)
          .eq('category', 'whitelabel')
          .maybeSingle();

        if (existing) {
          await supabase
            .from('app_settings')
            .update({ value: value as unknown as JsonValue, updated_at: new Date().toISOString() })
            .eq('id', existing.id);
        } else {
          await supabase
            .from('app_settings')
            .insert({
              key,
              value: value as unknown as JsonValue,
              category: 'whitelabel',
              description: `Whitelabel setting: ${key}`,
            });
        }
      };

      await Promise.all([
        saveSetting('site_name', siteName),
        saveSetting('site_tagline', siteTagline),
        saveSetting('company_legal_name', companyLegalName),
        saveSetting('logo_url', logoUrl),
        saveSetting('favicon_url', faviconUrl),
      ]);

      await refetchWhitelabel();
      toast.success('Pengaturan Whitelabel berhasil disimpan');
    } catch (error) {
      console.error('Error saving whitelabel:', error);
      toast.error('Gagal menyimpan pengaturan Whitelabel');
    } finally {
      setSaving(null);
    }
  };

  const handleSavePWA = async () => {
    setSaving('pwa');
    try {
      const { error } = await supabase
        .from('app_settings')
        .upsert({
          key: 'pwa_config',
          category: 'pwa',
          value: pwaSettings as unknown as JsonValue,
          description: 'Progressive Web App configuration',
          updated_at: new Date().toISOString(),
        }, { onConflict: 'key' });

      if (error) throw error;
      toast.success('Pengaturan PWA berhasil disimpan');
    } catch (error) {
      console.error('Error saving PWA:', error);
      toast.error('Gagal menyimpan pengaturan PWA');
    } finally {
      setSaving(null);
    }
  };

  const handleSaveGoogleSettings = async () => {
    const normalizedGa4 = ga4MeasurementId.trim().toUpperCase();
    const normalizedGtm = gtmId.trim().toUpperCase();
    if (normalizedGa4 && !/^G-[A-Z0-9]+$/.test(normalizedGa4)) {
      toast.error('Format Google Analytics 4 harus seperti G-XXXXXXXXXX');
      return;
    }
    if (normalizedGtm && !/^GTM-[A-Z0-9]+$/.test(normalizedGtm)) {
      toast.error('Format Google Tag Manager harus seperti GTM-XXXXXXX');
      return;
    }

    setSaving('google');
    try {
      const values = [
        { key: 'seo_google_verification', value: googleVerification.trim(), description: 'Google Search Console verification token' },
        { key: 'seo_ga4_measurement_id', value: normalizedGa4, description: 'Google Analytics 4 Measurement ID' },
        { key: 'seo_gtm_id', value: normalizedGtm, description: 'Google Tag Manager container ID' },
      ];
      const { error } = await supabase.from('app_settings').upsert(
        values.map((setting) => ({ ...setting, category: 'seo', updated_at: new Date().toISOString() })),
        { onConflict: 'key' },
      );
      if (error) throw error;
      setGa4MeasurementId(normalizedGa4);
      setGtmId(normalizedGtm);
      toast.success('Pengaturan Google berhasil disimpan');
    } catch (error) {
      console.error('Error saving Google settings:', error);
      toast.error('Gagal menyimpan pengaturan Google');
    } finally {
      setSaving(null);
    }
  };

  const handleSaveGlobalSeo = async () => {
    setSaving('global-seo');
    try {
      const values = [
        ['seo_global_title', globalSeoForm.title],
        ['seo_global_description', globalSeoForm.description],
        ['seo_global_keywords', globalSeoForm.keywords],
        ['seo_global_robots', globalSeoForm.robots],
        ['seo_global_canonical_url', globalSeoForm.canonicalUrl],
        ['seo_global_og_title', globalSeoForm.ogTitle],
        ['seo_global_og_description', globalSeoForm.ogDescription],
        ['seo_global_og_image', globalSeoForm.ogImage],
        ['seo_global_twitter_title', globalSeoForm.twitterTitle],
        ['seo_global_twitter_description', globalSeoForm.twitterDescription],
        ['seo_global_twitter_image', globalSeoForm.twitterImage],
      ];
      const { error } = await supabase.from('app_settings').upsert(
        values.map(([key, value]) => ({ key, value, category: 'seo', description: `Global SEO meta: ${key}`, updated_at: new Date().toISOString() })),
        { onConflict: 'key' },
      );
      if (error) throw error;
      toast.success('Meta tags SEO global berhasil disimpan');
    } catch (error) {
      console.error('Error saving global SEO:', error);
      toast.error('Gagal menyimpan meta tags SEO global');
    } finally {
      setSaving(null);
    }
  };

  const handleSaveSeo = async () => {
    if (!seoFormData.page_path) {
      toast.error('Path halaman wajib diisi');
      return;
    }

    setSaving('seo');
    try {
      const seoData = {
        page_path: seoFormData.page_path,
        title: seoFormData.title || null,
        description: seoFormData.description || null,
        keywords: seoFormData.keywords || null,
        og_image: seoFormData.og_image || null,
        og_title: seoFormData.og_title || null,
        og_description: seoFormData.og_description || null,
        canonical_url: seoFormData.canonical_url || null,
        robots: seoFormData.robots,
      };

      if (editingSeo) {
        const { error } = await supabase
          .from('seo_settings')
          .update(seoData)
          .eq('id', editingSeo.id);
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from('seo_settings')
          .insert(seoData);
        if (error) throw error;
      }

      await fetchAllSettings();
      setSeoDialogOpen(false);
      setEditingSeo(null);
      toast.success('Pengaturan SEO berhasil disimpan');
    } catch (error) {
      console.error('Error saving SEO:', error);
      toast.error('Gagal menyimpan pengaturan SEO');
    } finally {
      setSaving(null);
    }
  };

  const handleDeleteSeo = async (id: string) => {
    if (!confirm('Yakin ingin menghapus pengaturan SEO ini?')) return;
    
    try {
      const { error } = await supabase.from('seo_settings').delete().eq('id', id);
      if (error) throw error;
      toast.success('Pengaturan SEO dihapus');
      fetchAllSettings();
    } catch (error) {
      toast.error('Gagal menghapus pengaturan SEO');
    }
  };

  const handleSaveHomepageLayout = async () => {
    setSaving('layout');
    try {
      const layoutSettings: HomepageLayoutSettings = {
        sections: homepageSections,
        visible_categories: visibleCategories,
      };

      const { error } = await supabase
        .from('app_settings')
        .upsert({
          key: 'homepage_layout',
          category: 'layout',
          value: layoutSettings as unknown as JsonValue,
          description: 'Homepage layout and sections configuration',
          updated_at: new Date().toISOString(),
        }, { onConflict: 'key' });

      if (error) throw error;
      toast.success('Layout beranda berhasil disimpan');
    } catch (error) {
      console.error('Error saving layout:', error);
      toast.error('Gagal menyimpan layout beranda');
    } finally {
      setSaving(null);
    }
  };

  const handleSaveHomepageServiceCardImages = async () => {
    setSaving('service-card-images');
    try {
      const { error } = await supabase.from('app_settings').upsert({
        key: 'homepage_service_card_images',
        category: 'layout',
        value: homepageServiceCardImages as unknown as JsonValue,
        description: 'Gambar untuk tiga kartu layanan utama di halaman beranda',
        updated_at: new Date().toISOString(),
      }, { onConflict: 'key' });

      if (error) throw error;
      await queryClient.invalidateQueries({ queryKey: ['homepage-service-card-images'] });
      toast.success('Gambar menu utama berhasil disimpan');
    } catch (error) {
      console.error('Error saving homepage service card images:', error);
      toast.error('Gagal menyimpan gambar menu utama');
    } finally {
      setSaving(null);
    }
  };

  const handleSaveRecommendationBanner = async () => {
    setSaving('recommendation');
    try {
      const { error } = await supabase
        .from('app_settings')
        .upsert({
          key: 'homepage_recommendation_banner',
          category: 'layout',
          value: recommendationBanner as unknown as JsonValue,
          description: 'Pesan ajakan pada banner rekomendasi di atas menu beranda',
          updated_at: new Date().toISOString(),
        }, { onConflict: 'key' });
      if (error) throw error;
      toast.success('Pesan rekomendasi berhasil disimpan');
    } catch (error) {
      console.error('Error saving recommendation banner:', error);
      toast.error('Gagal menyimpan pesan rekomendasi');
    } finally {
      setSaving(null);
    }
  };

  const moveSection = (fromIndex: number, toIndex: number) => {
    const updated = [...homepageSections];
    const [moved] = updated.splice(fromIndex, 1);
    updated.splice(toIndex, 0, moved);
    
    // Update order property
    const final = updated.map((s, i) => ({ ...s, order: i }));
    setHomepageSections(final);
  };

  const toggleSection = (id: string) => {
    setHomepageSections(prev => prev.map(s => 
      s.id === id ? { ...s, enabled: !s.enabled } : s
    ));
  };

  const toggleCategory = (id: string) => {
    setVisibleCategories(prev => 
      prev.includes(id) ? prev.filter(c => c !== id) : [...prev, id]
    );
  };

  const filteredSeo = seoSettings.filter(s => 
    s.page_path.toLowerCase().includes(seoSearchTerm.toLowerCase()) ||
    s.title?.toLowerCase().includes(seoSearchTerm.toLowerCase())
  );

  return (
    <div className="space-y-6">
      <Tabs defaultValue="whitelabel">
        <TabsList className="grid grid-cols-5 w-full">
          <TabsTrigger value="whitelabel">Branding</TabsTrigger>
          <TabsTrigger value="google">Google</TabsTrigger>
          <TabsTrigger value="pwa">PWA</TabsTrigger>
          <TabsTrigger value="seo">SEO</TabsTrigger>
          <TabsTrigger value="layout">Layout</TabsTrigger>
        </TabsList>

        <TabsContent value="whitelabel">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Palette className="h-5 w-5" />
                Branding & Whitelabel
              </CardTitle>
              <CardDescription>Sesuaikan identitas situs Anda</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid md:grid-cols-3 gap-4">
                <div className="space-y-2">
                  <Label>Nama Situs</Label>
                  <Input value={siteName} onChange={(e) => setSiteName(e.target.value)} />
                </div>
                <div className="space-y-2">
                  <Label>Tagline</Label>
                  <Input value={siteTagline} onChange={(e) => setSiteTagline(e.target.value)} />
                </div>
                <div className="space-y-2">
                  <Label>Nama PT Pemilik Aplikasi</Label>
                  <Input value={companyLegalName} onChange={(e) => setCompanyLegalName(e.target.value)} placeholder="PT Nama Perusahaan" maxLength={150} />
                  <p className="text-xs text-muted-foreground">Ditampilkan pada footer frontend sebagai identitas legal aplikasi.</p>
                </div>
              </div>
              <div className="grid md:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Logo Toko</Label>
                  <ImageUpload
                    bucket="admin-assets"
                    path="branding/logo"
                    value={logoUrl}
                    onChange={(url) => setLogoUrl(url || '')}
                    aspectRatio="wide"
                    stableFileName
                    placeholder="Upload logo toko"
                  />
                  <p className="text-xs text-muted-foreground">Ditampilkan pada header toko SaDesa. Format JPG, PNG, WEBP, atau GIF. Maksimal 5MB.</p>
                </div>
                <div className="space-y-2">
                  <Label>Favicon Aplikasi</Label>
                  <ImageUpload
                    bucket="admin-assets"
                    path="branding/favicon"
                    value={faviconUrl}
                    onChange={(url) => setFaviconUrl(url || '')}
                    aspectRatio="square"
                    stableFileName
                    placeholder="Upload favicon aplikasi"
                  />
                  <p className="text-xs text-muted-foreground">Gunakan gambar persegi untuk ikon browser. Maksimal 5MB.</p>
                </div>
              </div>
              <Button onClick={handleSaveWhitelabel} disabled={saving === 'whitelabel'} className="w-full">
                {saving === 'whitelabel' ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Save className="h-4 w-4 mr-2" />}
                Simpan Branding
              </Button>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="google">
          <div className="grid gap-4">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2"><Globe className="h-5 w-5" /> Google Search Console</CardTitle>
                <CardDescription>Simpan kode verifikasi agar otomatis dipasang pada halaman frontend.</CardDescription>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="space-y-2">
                  <Label>Google Site Verification</Label>
                  <Input value={googleVerification} onChange={(event) => setGoogleVerification(event.target.value)} placeholder="google-site-verification=..." className="font-mono text-sm" />
                  <p className="text-xs text-muted-foreground">Bisa diisi token saja atau meta tag dari Google Search Console.</p>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2"><BarChart3 className="h-5 w-5" /> Google Analytics</CardTitle>
                <CardDescription>Analytics aktif otomatis setelah Measurement ID disimpan.</CardDescription>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="space-y-2">
                  <Label>Google Analytics 4 Measurement ID</Label>
                  <Input value={ga4MeasurementId} onChange={(event) => setGa4MeasurementId(event.target.value)} placeholder="G-XXXXXXXXXX" className="font-mono text-sm" />
                </div>
                <div className="space-y-2">
                  <Label>Google Tag Manager ID <span className="font-normal text-muted-foreground">(opsional)</span></Label>
                  <Input value={gtmId} onChange={(event) => setGtmId(event.target.value)} placeholder="GTM-XXXXXXX" className="font-mono text-sm" />
                </div>
                <Button onClick={() => void handleSaveGoogleSettings()} disabled={saving === 'google'} className="w-full">
                  {saving === 'google' ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Save className="h-4 w-4 mr-2" />}
                  Simpan Pengaturan Google
                </Button>
              </CardContent>
            </Card>
          </div>
        </TabsContent>

        <TabsContent value="pwa">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <RefreshCw className="h-5 w-5" />
                Progressive Web App (PWA)
              </CardTitle>
              <CardDescription>Konfigurasi aplikasi agar dapat diinstal di HP/Desktop</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid md:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Nama Aplikasi</Label>
                  <Input value={pwaSettings.appName} onChange={(e) => setPwaSettings({...pwaSettings, appName: e.target.value})} />
                </div>
                <div className="space-y-2">
                  <Label>Nama Pendek</Label>
                  <Input value={pwaSettings.shortName} onChange={(e) => setPwaSettings({...pwaSettings, shortName: e.target.value})} />
                </div>
              </div>
              <div className="space-y-2">
                <Label>Deskripsi PWA</Label>
                <Textarea value={pwaSettings.description} onChange={(e) => setPwaSettings({...pwaSettings, description: e.target.value})} />
              </div>
              <div className="grid md:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Icon PWA 192×192 URL</Label>
                  <Input
                    value={pwaSettings.icons.find((icon) => icon.sizes === '192x192')?.src ?? ''}
                    onChange={(e) => updatePwaIcon('192x192', e.target.value)}
                    placeholder="https://.../icon-192.png atau /branding/..."
                  />
                </div>
                <div className="space-y-2">
                  <Label>Icon PWA 512×512 URL</Label>
                  <Input
                    value={pwaSettings.icons.find((icon) => icon.sizes === '512x512')?.src ?? ''}
                    onChange={(e) => updatePwaIcon('512x512', e.target.value)}
                    placeholder="https://.../icon-512.png atau /branding/..."
                  />
                </div>
              </div>
              <div className="grid md:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Warna Tema (Hex)</Label>
                  <Input type="color" className="h-10" value={pwaSettings.themeColor} onChange={(e) => setPwaSettings({...pwaSettings, themeColor: e.target.value})} />
                </div>
                <div className="space-y-2">
                  <Label>Warna Background (Hex)</Label>
                  <Input type="color" className="h-10" value={pwaSettings.backgroundColor} onChange={(e) => setPwaSettings({...pwaSettings, backgroundColor: e.target.value})} />
                </div>
              </div>
              <div className="grid md:grid-cols-2 gap-4">
                <div className="flex items-center justify-between p-3 border rounded-lg">
                  <div className="space-y-0.5">
                    <Label>Offline Mode</Label>
                    <p className="text-xs text-muted-foreground">Aktifkan akses saat tanpa internet</p>
                  </div>
                  <Switch checked={pwaSettings.enableOffline} onCheckedChange={(val) => setPwaSettings({...pwaSettings, enableOffline: val})} />
                </div>
                <div className="flex items-center justify-between p-3 border rounded-lg">
                  <div className="space-y-0.5">
                    <Label>Install Prompt</Label>
                    <p className="text-xs text-muted-foreground">Tampilkan ajakan instal aplikasi</p>
                  </div>
                  <Switch checked={pwaSettings.enableInstallPrompt} onCheckedChange={(val) => setPwaSettings({...pwaSettings, enableInstallPrompt: val})} />
                </div>
              </div>
              <Button onClick={handleSavePWA} disabled={saving === 'pwa'} className="w-full">
                {saving === 'pwa' ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Save className="h-4 w-4 mr-2" />}
                Simpan Konfigurasi PWA
              </Button>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="seo">
          <Card className="mb-4">
            <CardHeader>
              <CardTitle className="flex items-center gap-2"><Globe className="h-5 w-5" /> Meta Tags Global</CardTitle>
              <CardDescription>Default SEO untuk halaman yang belum memiliki pengaturan per halaman. Meta per halaman akan menjadi prioritas.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2"><Label>Meta Title Global</Label><Input value={globalSeoForm.title} onChange={(event) => setGlobalSeoForm((prev) => ({ ...prev, title: event.target.value }))} placeholder="SaDesa — Marketplace UMKM & Desa Wisata" maxLength={70} /><p className="text-xs text-muted-foreground">Idealnya maksimal 60–70 karakter.</p></div>
                <div className="space-y-2"><Label>Robots</Label><Input value={globalSeoForm.robots} onChange={(event) => setGlobalSeoForm((prev) => ({ ...prev, robots: event.target.value }))} placeholder="index, follow" /></div>
              </div>
              <div className="space-y-2"><Label>Meta Description Global</Label><Textarea value={globalSeoForm.description} onChange={(event) => setGlobalSeoForm((prev) => ({ ...prev, description: event.target.value }))} placeholder="Deskripsi utama aplikasi untuk mesin pencari..." rows={3} maxLength={170} /><p className="text-xs text-muted-foreground">Idealnya maksimal 150–160 karakter.</p></div>
              <div className="space-y-2"><Label>Meta Keywords</Label><Input value={globalSeoForm.keywords} onChange={(event) => setGlobalSeoForm((prev) => ({ ...prev, keywords: event.target.value }))} placeholder="UMKM, desa wisata, marketplace desa" /></div>
              <div className="space-y-2"><Label>Canonical URL</Label><Input value={globalSeoForm.canonicalUrl} onChange={(event) => setGlobalSeoForm((prev) => ({ ...prev, canonicalUrl: event.target.value }))} placeholder="https://sadesa.id" type="url" /></div>
              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2"><Label>Open Graph Title</Label><Input value={globalSeoForm.ogTitle} onChange={(event) => setGlobalSeoForm((prev) => ({ ...prev, ogTitle: event.target.value }))} placeholder="Judul saat dibagikan ke media sosial" /></div>
                <div className="space-y-2"><Label>Open Graph Image URL</Label><Input value={globalSeoForm.ogImage} onChange={(event) => setGlobalSeoForm((prev) => ({ ...prev, ogImage: event.target.value }))} placeholder="https://.../og-image.jpg" type="url" /></div>
              </div>
              <div className="space-y-2"><Label>Open Graph Description</Label><Textarea value={globalSeoForm.ogDescription} onChange={(event) => setGlobalSeoForm((prev) => ({ ...prev, ogDescription: event.target.value }))} placeholder="Deskripsi ketika link dibagikan" rows={2} /></div>
              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2"><Label>Twitter Card Title</Label><Input value={globalSeoForm.twitterTitle} onChange={(event) => setGlobalSeoForm((prev) => ({ ...prev, twitterTitle: event.target.value }))} placeholder="Judul Twitter/X" /></div>
                <div className="space-y-2"><Label>Twitter Card Image URL</Label><Input value={globalSeoForm.twitterImage} onChange={(event) => setGlobalSeoForm((prev) => ({ ...prev, twitterImage: event.target.value }))} placeholder="https://.../twitter-image.jpg" type="url" /></div>
              </div>
              <div className="space-y-2"><Label>Twitter Card Description</Label><Textarea value={globalSeoForm.twitterDescription} onChange={(event) => setGlobalSeoForm((prev) => ({ ...prev, twitterDescription: event.target.value }))} placeholder="Deskripsi Twitter/X" rows={2} /></div>
              <Button onClick={() => void handleSaveGlobalSeo()} disabled={saving === 'global-seo'} className="w-full">
                {saving === 'global-seo' ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Save className="h-4 w-4 mr-2" />} Simpan Meta Tags Global
              </Button>
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0">
              <div>
                <CardTitle className="flex items-center gap-2">
                  <Globe className="h-5 w-5" />
                  SEO & Meta Tags
                </CardTitle>
                <CardDescription>Optimalkan visibilitas di mesin pencari</CardDescription>
              </div>
              <Button onClick={() => { setEditingSeo(null); setSeoFormData({ page_path: '', title: '', description: '', keywords: '', og_image: '', og_title: '', og_description: '', canonical_url: '', robots: 'index, follow' }); setSeoDialogOpen(true); }}>
                <Plus className="h-4 w-4 mr-2" /> Tambah SEO
              </Button>
            </CardHeader>
            <CardContent>
              <div className="relative mb-4">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input placeholder="Cari path atau judul..." className="pl-9" value={seoSearchTerm} onChange={(e) => setSeoSearchTerm(e.target.value)} />
              </div>
              <div className="border rounded-lg overflow-hidden">
                <table className="w-full text-sm">
                  <thead className="bg-muted">
                    <tr>
                      <th className="text-left p-3 font-medium">Path</th>
                      <th className="text-left p-3 font-medium">Judul Halaman</th>
                      <th className="text-right p-3 font-medium">Aksi</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y">
                    {filteredSeo.length > 0 ? filteredSeo.map((item) => (
                      <tr key={item.id} className="hover:bg-muted/50 transition-colors">
                        <td className="p-3 font-mono text-xs">{item.page_path}</td>
                        <td className="p-3 truncate max-w-[200px]">{item.title || '-'}</td>
                        <td className="p-3 text-right">
                          <div className="flex justify-end gap-1">
                            <Button size="icon" variant="ghost" className="h-8 w-8" onClick={() => { setEditingSeo(item); setSeoFormData({ ...item, title: item.title || '', description: item.description || '', keywords: item.keywords || '', og_image: item.og_image || '', og_title: item.og_title || '', og_description: item.og_description || '', canonical_url: item.canonical_url || '' }); setSeoDialogOpen(true); }}>
                              <Edit2 className="h-4 w-4" />
                            </Button>
                            <Button size="icon" variant="ghost" className="h-8 w-8 text-destructive" onClick={() => handleDeleteSeo(item.id)}>
                              <Trash2 className="h-4 w-4" />
                            </Button>
                          </div>
                        </td>
                      </tr>
                    )) : (
                      <tr><td colSpan={3} className="p-8 text-center text-muted-foreground">Tidak ada pengaturan SEO ditemukan</td></tr>
                    )}
                  </tbody>
                </table>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="layout">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Layout className="h-5 w-5" />
                Layout Beranda
              </CardTitle>
              <CardDescription>Atur urutan dan visibilitas bagian di halaman depan</CardDescription>
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="space-y-3">
                <Label>Urutan Bagian</Label>
                <div className="space-y-2">
                  {homepageSections.map((section, index) => (
                    <div 
                      key={section.id}
                      draggable
                      onDragStart={() => setDraggedIndex(index)}
                      onDragOver={(e) => { e.preventDefault(); if (draggedIndex !== null && draggedIndex !== index) moveSection(draggedIndex, index); setDraggedIndex(index); }}
                      onDragEnd={() => setDraggedIndex(null)}
                      className={`flex items-center justify-between p-3 border rounded-lg bg-card cursor-move ${draggedIndex === index ? 'opacity-50 border-primary' : ''}`}
                    >
                      <div className="flex items-center gap-3">
                        <GripVertical className="h-4 w-4 text-muted-foreground" />
                        <span className="font-medium">{section.name}</span>
                      </div>
                      <Switch checked={section.enabled} onCheckedChange={() => toggleSection(section.id)} />
                    </div>
                  ))}
                </div>
              </div>

              <div className="space-y-3">
                <Label>Kategori yang Ditampilkan</Label>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                  {allCategories.map(cat => (
                    <div key={cat.id} className="flex items-center space-x-2 p-2 border rounded-md">
                      <Checkbox id={cat.id} checked={visibleCategories.includes(cat.id)} onCheckedChange={() => toggleCategory(cat.id)} />
                      <Label htmlFor={cat.id} className="text-sm cursor-pointer">{cat.name}</Label>
                    </div>
                  ))}
                </div>
              </div>

              <Button onClick={handleSaveHomepageLayout} disabled={saving === 'layout'} className="w-full">
                {saving === 'layout' ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Save className="h-4 w-4 mr-2" />}
                Simpan Layout
              </Button>
            </CardContent>
          </Card>
          <Card className="mt-6">
            <CardHeader>
              <CardTitle>Gambar Menu Utama</CardTitle>
              <CardDescription>Atur gambar untuk kartu Makanan &amp; Minuman, Ojek, dan Belanja yang tampil di halaman beranda.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-5">
              <p className="text-sm text-muted-foreground">Ukuran gambar yang disarankan: <span className="font-semibold text-foreground">1120 × 1000 px</span> (rasio 1,12:1). Gambar dengan ukuran atau rasio lain akan otomatis menyesuaikan dan dapat terpotong agar pas di kartu.</p>
              <div className="grid gap-5 md:grid-cols-3">
                {HOMEPAGE_SERVICE_CARDS.map((card) => (
                  <div key={card.id} className="space-y-2">
                    <Label>{card.title}</Label>
                    <ImageUpload
                      bucket="admin-assets"
                      path={`homepage/service-cards/${card.id}`}
                      value={homepageServiceCardImages[card.id] || card.fallbackImage}
                      onChange={(url) => setHomepageServiceCardImages((current) => ({ ...current, [card.id]: url }))}
                      aspectRatio="home-card"
                      maxSizeMB={15}
                      compressionOptions={{ maxWidth: 1120, maxHeight: 1000, quality: 0.82, force: true }}
                      stableFileName
                      placeholder={`Upload gambar ${card.title}`}
                    />
                    <p className="text-xs text-muted-foreground">Unggah JPG, PNG, WEBP, atau GIF hingga 15 MB. Gambar otomatis dikompres ke JPEG maksimal 1120 × 1000 px; GIF animasi menjadi gambar statis. Tombol hapus mengembalikan gambar bawaan.</p>
                    {homepageServiceCardImages[card.id] && (
                      <Button
                        type="button"
                        variant="link"
                        size="sm"
                        className="h-auto px-0"
                        onClick={() => setHomepageServiceCardImages((current) => ({ ...current, [card.id]: null }))}
                      >
                        Gunakan gambar bawaan
                      </Button>
                    )}
                  </div>
                ))}
              </div>
              <Button onClick={handleSaveHomepageServiceCardImages} disabled={saving === 'service-card-images'} className="w-full">
                {saving === 'service-card-images' ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Save className="mr-2 h-4 w-4" />}
                Simpan Gambar Menu Utama
              </Button>
            </CardContent>
          </Card>
          <Card className="mt-6">
            <CardHeader>
              <CardTitle>Pesan Banner Rekomendasi</CardTitle>
              <CardDescription>Atur ajakan yang tampil di atas menu beranda, misalnya untuk mengajak pengguna menjadi driver atau pedagang.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex items-center justify-between rounded-lg border p-3">
                <div>
                  <Label className="text-sm font-medium">Tampilkan banner custom</Label>
                  <p className="text-xs text-muted-foreground">Jika dimatikan, rekomendasi otomatis berdasarkan waktu akan digunakan.</p>
                </div>
                <Switch checked={recommendationBanner.enabled} onCheckedChange={(enabled) => setRecommendationBanner((current) => ({ ...current, enabled }))} />
              </div>
              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label>Ajakan untuk</Label>
                  <Select
                    value={recommendationBanner.target}
                    onValueChange={(target: HomepageRecommendationBanner['target']) => setRecommendationBanner((current) => ({
                      ...current,
                      target,
                      linkUrl: target === 'merchant' ? '/register/merchant' : '/register/courier',
                    }))}
                  >
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="courier">Driver / Kurir</SelectItem>
                      <SelectItem value="merchant">Pedagang / UMKM</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label>Label kecil</Label>
                  <Input value={recommendationBanner.eyebrow} onChange={(e) => setRecommendationBanner((current) => ({ ...current, eyebrow: e.target.value }))} placeholder="Bergabung bersama kami" />
                </div>
                <div className="space-y-2 md:col-span-2">
                  <Label>Judul banner</Label>
                  <Input value={recommendationBanner.title} onChange={(e) => setRecommendationBanner((current) => ({ ...current, title: e.target.value }))} placeholder="Jadi driver di SaDesa" />
                </div>
                <div className="space-y-2 md:col-span-2">
                  <Label>Pesan</Label>
                  <Textarea value={recommendationBanner.description} onChange={(e) => setRecommendationBanner((current) => ({ ...current, description: e.target.value }))} placeholder="Bantu antar pesanan dan dapatkan penghasilan tambahan." />
                </div>
                <div className="space-y-2">
                  <Label>Teks tombol</Label>
                  <Input value={recommendationBanner.cta} onChange={(e) => setRecommendationBanner((current) => ({ ...current, cta: e.target.value }))} placeholder="Daftar sekarang" />
                </div>
                <div className="space-y-2">
                  <Label>Link tombol</Label>
                  <Input value={recommendationBanner.linkUrl} onChange={(e) => setRecommendationBanner((current) => ({ ...current, linkUrl: e.target.value }))} placeholder="/register/courier" />
                </div>
              </div>
              <Button onClick={handleSaveRecommendationBanner} disabled={saving === 'recommendation'} className="w-full">
                {saving === 'recommendation' ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Save className="mr-2 h-4 w-4" />}
                Simpan Pesan Rekomendasi
              </Button>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      <Dialog open={seoDialogOpen} onOpenChange={setSeoDialogOpen}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editingSeo ? 'Edit SEO Settings' : 'Tambah SEO Settings'}</DialogTitle>
            <DialogDescription>Masukkan meta tags untuk path halaman spesifik</DialogDescription>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div className="grid grid-cols-4 items-center gap-4">
              <Label className="text-right">Path Halaman</Label>
              <div className="col-span-3 space-y-1">
                <Input placeholder="/produk/nama-produk" value={seoFormData.page_path} onChange={(e) => setSeoFormData({...seoFormData, page_path: e.target.value})} />
                <p className="text-[10px] text-muted-foreground">Gunakan / untuk beranda</p>
              </div>
            </div>
            <div className="grid grid-cols-4 items-center gap-4">
              <Label className="text-right">Judul (Title)</Label>
              <Input className="col-span-3" value={seoFormData.title} onChange={(e) => setSeoFormData({...seoFormData, title: e.target.value})} />
            </div>
            <div className="grid grid-cols-4 items-center gap-4">
              <Label className="text-right">Deskripsi</Label>
              <Textarea className="col-span-3" value={seoFormData.description} onChange={(e) => setSeoFormData({...seoFormData, description: e.target.value})} />
            </div>
            <div className="grid grid-cols-4 items-center gap-4">
              <Label className="text-right">Keywords</Label>
              <Input className="col-span-3" placeholder="umkm, desa wisata, produk lokal" value={seoFormData.keywords} onChange={(e) => setSeoFormData({...seoFormData, keywords: e.target.value})} />
            </div>
            <div className="grid grid-cols-4 items-center gap-4">
              <Label className="text-right">Robots</Label>
              <Select value={seoFormData.robots} onValueChange={(val) => setSeoFormData({...seoFormData, robots: val})}>
                <SelectTrigger className="col-span-3">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="index, follow">Index, Follow (Default)</SelectItem>
                  <SelectItem value="noindex, nofollow">No Index, No Follow</SelectItem>
                  <SelectItem value="index, nofollow">Index, No Follow</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="border-t pt-4 mt-2">
              <h4 className="text-sm font-semibold mb-4 flex items-center gap-2"><Share2 className="h-4 w-4" /> Social Media (Open Graph)</h4>
              <div className="space-y-4">
                <div className="grid grid-cols-4 items-center gap-4">
                  <Label className="text-right">OG Image URL</Label>
                  <div className="col-span-3 flex gap-2">
                    <Input value={seoFormData.og_image} onChange={(e) => setSeoFormData({...seoFormData, og_image: e.target.value})} />
                    <ImageUpload bucket="merchant-images" path={`branding/og-${Date.now()}`} value={seoFormData.og_image} onChange={(url) => setSeoFormData({...seoFormData, og_image: url || ''})} />
                  </div>
                </div>
                <div className="grid grid-cols-4 items-center gap-4">
                  <Label className="text-right">OG Title</Label>
                  <Input className="col-span-3" placeholder="Biarkan kosong untuk pakai judul utama" value={seoFormData.og_title} onChange={(e) => setSeoFormData({...seoFormData, og_title: e.target.value})} />
                </div>
              </div>
            </div>
          </div>
          <div className="flex justify-end gap-3 mt-4">
            <Button variant="outline" onClick={() => setSeoDialogOpen(false)}>Batal</Button>
            <Button onClick={handleSaveSeo} disabled={saving === 'seo'}>
              {saving === 'seo' && <Loader2 className="h-4 w-4 animate-spin mr-2" />}
              Simpan SEO
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
