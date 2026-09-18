import { Coffee, IceCreamBowl, Moon, Utensils, X, ChevronRight, MapPin } from 'lucide-react';
import { Link } from 'react-router-dom';
import type { LucideIcon } from 'lucide-react';
import type { Product } from '@/types';
import { findNearestOpenMerchant, formatDistance, type NearestOpenMerchant } from '@/lib/nearestOpenMerchant';

interface RecommendationContent {
  icon: LucideIcon;
  eyebrow: string;
  title: string;
  description: string;
  cta: string;
  tone: string;
  iconTone: string;
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
  userLocation?: { lat: number; lng: number } | null;
  onDismiss?: () => void;
}

export function ContextualRecommendation({ products = [], userLocation, onDismiss }: ContextualRecommendationProps) {
  const content = getRecommendation(new Date().getHours());
  const nearestMerchant: NearestOpenMerchant | null = findNearestOpenMerchant(products, userLocation);
  const Icon = content.icon;
  const operationalDescription = nearestMerchant
    ? `${nearestMerchant.merchantName} sedang buka · ${formatDistance(nearestMerchant.distanceKm)} dari kamu.`
    : userLocation
      ? 'Belum ada merchant kuliner yang sedang buka di sekitar kamu.'
      : content.description;

  return (
    <section className={`relative mx-4 mt-4 overflow-hidden rounded-2xl border border-orange-100 bg-gradient-to-r ${content.tone} px-3.5 py-3 shadow-[0_12px_28px_-22px_hsl(4_78%_47%_/_0.55)]`} aria-label="Rekomendasi sesuai waktu">
      <div className="pointer-events-none absolute -right-5 -top-8 h-20 w-20 rounded-full bg-white/70" />
      <div className="relative flex items-center gap-3">
        <div className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-xl ${content.iconTone}`} aria-hidden="true">
          <Icon className="h-5 w-5" />
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-[9px] font-bold uppercase tracking-[0.14em] text-primary">{content.eyebrow}</p>
          <h2 className="mt-0.5 truncate text-[13px] font-extrabold leading-tight text-foreground">{content.title}</h2>
          <p className="mt-0.5 flex items-center gap-1 truncate text-[10px] text-muted-foreground">
            {nearestMerchant && <MapPin className="h-3 w-3 shrink-0 text-primary" aria-hidden="true" />}
            <span className="truncate">{operationalDescription}</span>
          </p>
        </div>
        <Link
          to="/products"
          className="flex shrink-0 items-center gap-0.5 rounded-full bg-white/80 px-2.5 py-2 text-[9px] font-bold text-primary shadow-sm transition hover:bg-white active:scale-95"
          aria-label={content.cta}
        >
          <span className="hidden min-[390px]:inline">{content.cta}</span>
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
