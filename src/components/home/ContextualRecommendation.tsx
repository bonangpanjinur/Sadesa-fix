import { Coffee, IceCreamBowl, Moon, Utensils, X, ChevronRight, MapPin, Store, UserRound } from 'lucide-react';
import { Link } from 'react-router-dom';
import { useEffect, useState } from 'react';
import type { LucideIcon } from 'lucide-react';
import type { Product } from '@/types';
import { findNearestOpenMerchant, formatDistance, type NearestOpenMerchant } from '@/lib/nearestOpenMerchant';
import { calculateDistance } from '@/hooks/useUserLocation';
import type { MerchantAd } from '@/lib/promotions';
import { supabase } from '@/integrations/supabase/client';

interface RecommendationContent {
  icon: LucideIcon;
  eyebrow: string;
  title: string;
  description: string;
  cta: string;
  tone: string;
  iconTone: string;
}

interface CustomRecommendationConfig {
  enabled: boolean;
  target: 'courier' | 'merchant';
  eyebrow: string;
  title: string;
  description: string;
  cta: string;
  linkUrl: string;
}

function getRecommendation(hour: number): RecommendationContent {
  if (hour >= 5 && hour < 10) {
    return {
      icon: Coffee,
      eyebrow: 'Rekomendasi pagi',
      title: 'Waktunya sarapan',
      description: 'Menu hangat dari sekitar kamu, mulai dari Rp10.000.',
      cta: 'Lihat menu sarapan',
      tone: 'from-amber-50 via-orange-50 to-white',
      iconTone: 'bg-amber-100 text-amber-700',
    };
  }

  if (hour >= 10 && hour < 12) {
    return {
      icon: IceCreamBowl,
      eyebrow: 'Rekomendasi siang',
      title: 'Camilan sebelum makan siang?',
      description: 'Temukan minuman segar dan camilan terdekat.',
      cta: 'Cari camilan',
      tone: 'from-orange-50 via-rose-50 to-white',
      iconTone: 'bg-orange-100 text-orange-700',
    };
  }

  if (hour >= 12 && hour < 15) {
    return {
      icon: Utensils,
      eyebrow: 'Rekomendasi siang',
      title: 'Sudah waktunya makan siang',
      description: 'Pilih paket hemat yang siap diantar ke lokasi kamu.',
      cta: 'Lihat makan siang',
      tone: 'from-yellow-50 via-amber-50 to-white',
      iconTone: 'bg-yellow-100 text-yellow-700',
    };
  }

  if (hour >= 15 && hour < 18) {
    return {
      icon: IceCreamBowl,
      eyebrow: 'Rekomendasi sore',
      title: 'Teman sore hari',
      description: 'Es kopi, jus, dan camilan pilihan untuk menemani aktivitasmu.',
      cta: 'Lihat pilihan sore',
      tone: 'from-rose-50 via-orange-50 to-white',
      iconTone: 'bg-rose-100 text-rose-700',
    };
  }

  return {
    icon: Moon,
    eyebrow: 'Rekomendasi malam',
    title: hour >= 21 ? 'Lapar malam?' : 'Makan malam lebih praktis',
    description: hour >= 21 ? 'Cari makanan yang masih buka di dekat kamu.' : 'Temukan menu favorit untuk makan bersama keluarga.',
    cta: hour >= 21 ? 'Lihat yang masih buka' : 'Lihat menu malam',
    tone: 'from-indigo-50 via-violet-50 to-white',
    iconTone: 'bg-indigo-100 text-indigo-700',
  };
}

interface ContextualRecommendationProps {
  products?: Product[];
  sponsoredAds?: MerchantAd[];
  userLocation?: { lat: number; lng: number } | null;
  onDismiss?: () => void;
}

export function ContextualRecommendation({ products = [], sponsoredAds = [], userLocation, onDismiss }: ContextualRecommendationProps) {
  const [customContent, setCustomContent] = useState<CustomRecommendationConfig | null>(null);

  useEffect(() => {
    let active = true;
    supabase
      .from('app_settings')
      .select('value')
      .eq('key', 'homepage_recommendation_banner')
      .maybeSingle()
      .then(({ data }) => {
        if (!active || !data?.value || typeof data.value !== 'object' || Array.isArray(data.value)) return;
        const value = data.value as Record<string, unknown>;
        if (typeof value.title === 'string' && typeof value.description === 'string') {
          setCustomContent({
            enabled: value.enabled !== false,
            target: value.target === 'merchant' ? 'merchant' : 'courier',
            eyebrow: typeof value.eyebrow === 'string' ? value.eyebrow : 'Bergabung bersama kami',
            title: value.title,
            description: value.description,
            cta: typeof value.cta === 'string' && value.cta ? value.cta : 'Daftar sekarang',
            linkUrl: typeof value.linkUrl === 'string' && value.linkUrl ? value.linkUrl : '/register/courier',
          });
        }
      }, () => undefined);
    return () => { active = false; };
  }, []);

  const defaultContent = getRecommendation(new Date().getHours());
  const activeCustomContent = customContent?.enabled ? customContent : null;
  const content: RecommendationContent = activeCustomContent
    ? {
        ...defaultContent,
        icon: activeCustomContent.target === 'merchant' ? Store : UserRound,
        eyebrow: activeCustomContent.eyebrow,
        title: activeCustomContent.title,
        description: activeCustomContent.description,
        cta: activeCustomContent.cta,
        tone: activeCustomContent.target === 'merchant' ? 'from-emerald-50 via-teal-50 to-white' : 'from-sky-50 via-blue-50 to-white',
        iconTone: activeCustomContent.target === 'merchant' ? 'bg-emerald-100 text-emerald-700' : 'bg-sky-100 text-sky-700',
      }
    : defaultContent;
  const nearestMerchant: NearestOpenMerchant | null = findNearestOpenMerchant(products, userLocation);
  const sponsoredAd = userLocation
    ? [...sponsoredAds]
      .sort((a, b) => calculateDistance(userLocation.lat, userLocation.lng, a.locationLat, a.locationLng) - calculateDistance(userLocation.lat, userLocation.lng, b.locationLat, b.locationLng))[0]
    : sponsoredAds[0];
  const Icon = content.icon;
  const operationalDescription = activeCustomContent
    ? activeCustomContent.description
    : sponsoredAd
    ? `${sponsoredAd.merchantName} sedang buka · ${formatDistance(calculateDistance(userLocation?.lat ?? 0, userLocation?.lng ?? 0, sponsoredAd.locationLat, sponsoredAd.locationLng))}`
    : nearestMerchant
    ? `${nearestMerchant.merchantName} sedang buka · ${formatDistance(nearestMerchant.distanceKm)} dari kamu.`
    : userLocation
      ? 'Belum ada kuliner yang buka saat ini. Coba lihat semua merchant atau pesan untuk nanti.'
      : content.description;

  return (
    <section className={`relative mx-4 mt-3 overflow-hidden rounded-xl border border-orange-100 bg-gradient-to-r ${content.tone} px-3 py-2.5 shadow-[0_12px_28px_-22px_hsl(4_78%_47%_/_0.55)]`} aria-label="Rekomendasi sesuai waktu">
      <div className="pointer-events-none absolute -right-5 -top-8 h-20 w-20 rounded-full bg-white/70" />
      <div className="relative flex items-center gap-3">
        <div className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-xl ${content.iconTone}`} aria-hidden="true">
          <Icon className="h-5 w-5" />
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-[9px] font-bold uppercase tracking-[0.14em] text-primary">{activeCustomContent ? content.eyebrow : sponsoredAd ? 'Sponsor lokal' : content.eyebrow}</p>
          <h2 className="mt-0.5 truncate text-[13px] font-extrabold leading-tight text-foreground">{activeCustomContent ? content.title : sponsoredAd ? sponsoredAd.title : content.title}</h2>
          <p className="mt-0.5 flex items-center gap-1 truncate text-[10px] text-muted-foreground">
            {!activeCustomContent && (sponsoredAd || nearestMerchant) && <MapPin className="h-3 w-3 shrink-0 text-primary" aria-hidden="true" />}
            <span className="truncate">{activeCustomContent ? operationalDescription : sponsoredAd?.description || operationalDescription}</span>
          </p>
        </div>
        <Link
          to={activeCustomContent?.linkUrl || sponsoredAd?.linkUrl || '/products'}
          className="flex shrink-0 items-center gap-0.5 rounded-full bg-white/80 px-2.5 py-2 text-[9px] font-bold text-primary shadow-sm transition hover:bg-white active:scale-95"
          aria-label={activeCustomContent ? activeCustomContent.cta : content.cta}
        >
          <span className="hidden min-[390px]:inline">{activeCustomContent ? activeCustomContent.cta : content.cta}</span>
          <ChevronRight className="h-3.5 w-3.5" />
        </Link>
        {onDismiss && (
          <button type="button" onClick={onDismiss} className="absolute -right-1 -top-2 rounded-full p-1 text-muted-foreground/60 hover:text-foreground" aria-label="Tutup rekomendasi">
            <X className="h-3 w-3" />
          </button>
        )}
      </div>
    </section>
  );
}
