import { useQuery } from '@tanstack/react-query';
import { Bike, ShoppingBasket, UtensilsCrossed, type LucideIcon } from 'lucide-react';
import { Link } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { getOptimizedImageSrcSet, optimizeSupabaseImage } from '@/components/ui/OptimizedImage';
import {
  EMPTY_HOMEPAGE_SERVICE_CARD_IMAGE_OVERRIDES,
  HOMEPAGE_SERVICE_CARDS,
  type HomepageServiceCardId,
  parseHomepageServiceCardImageOverrides,
} from '@/lib/homeServiceCards';

const serviceCardIcons: Record<HomepageServiceCardId, LucideIcon> = {
  food: UtensilsCrossed,
  ojek: Bike,
  shopping: ShoppingBasket,
};

function isSvgUrl(url: string) {
  return /\.svg(?:[?#]|$)/i.test(url) || url.includes('/service-icons/');
}

export function HomeServiceCards() {
  const { data: imageOverrides = EMPTY_HOMEPAGE_SERVICE_CARD_IMAGE_OVERRIDES } = useQuery({
    queryKey: ['homepage-service-card-images'],
    // This setting changes infrequently and is already invalidated by the
    // admin update flow. Avoid a refetch on every navigation back to Home.
    staleTime: 5 * 60 * 1000,
    gcTime: 15 * 60 * 1000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('app_settings')
        .select('value')
        .eq('key', 'homepage_service_card_images')
        .maybeSingle();

      if (error) {
        console.error('Error loading homepage service card images:', error);
        return { ...EMPTY_HOMEPAGE_SERVICE_CARD_IMAGE_OVERRIDES };
      }

      return parseHomepageServiceCardImageOverrides(data?.value);
    },
  });

  return (
    <section className="mx-4" aria-label="Menu utama" data-feature-tour="buyer-discover">
      <div className="grid grid-cols-3 overflow-hidden rounded-[1.8rem] border border-[#e3eee4] bg-white shadow-[0_16px_34px_-24px_rgba(1,87,48,0.4)]">
        {HOMEPAGE_SERVICE_CARDS.map((card) => {
          const Icon = serviceCardIcons[card.id];
          const imageUrl = imageOverrides[card.id];
          const svgIcon = imageUrl ? isSvgUrl(imageUrl) : false;

          return (
            <Link
              key={card.id}
              to={card.href}
              aria-label={card.title}
              className="group relative flex min-w-0 flex-col items-center justify-center gap-3 border-r border-[#e4ece5] px-2 py-5 text-center transition-colors duration-200 last:border-r-0 hover:bg-[#f7fbf6] focus-visible:z-10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#44a31b] active:bg-[#edf7e8]"
            >
              <span aria-hidden="true" className="relative flex h-[4.4rem] w-[4.4rem] shrink-0 items-center justify-center rounded-full bg-[#edf7e8] text-[#08713f] transition-transform duration-200 group-hover:scale-[1.04]">
                <Icon className="h-8 w-8 stroke-[1.8]" />
                {imageUrl && (
                  <img
                    src={svgIcon ? imageUrl : optimizeSupabaseImage(imageUrl, 240)}
                    {...(!svgIcon && { srcSet: getOptimizedImageSrcSet(imageUrl, [240, 360, 480, 640]) })}
                    sizes="4.4rem"
                    alt=""
                    loading="lazy"
                    decoding="async"
                    onError={(event) => { event.currentTarget.hidden = true; }}
                    className="absolute h-[4.4rem] w-[4.4rem] rounded-full object-contain bg-[#edf7e8] p-3"
                  />
                )}
              </span>
              <span className="min-h-[2.5rem] text-[13px] font-bold leading-tight tracking-[-0.02em] text-[#153c2c] sm:text-sm">
                {card.title}
              </span>
            </Link>
          );
        })}
      </div>
    </section>
  );
}
