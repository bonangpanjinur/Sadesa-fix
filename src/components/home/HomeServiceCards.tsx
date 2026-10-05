import { useQuery } from '@tanstack/react-query';
import { ChevronRight } from 'lucide-react';
import { Link } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import {
  EMPTY_HOMEPAGE_SERVICE_CARD_IMAGE_OVERRIDES,
  HOMEPAGE_SERVICE_CARDS,
  parseHomepageServiceCardImageOverrides,
} from '@/lib/homeServiceCards';

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
    <section className="mx-4" aria-label="Kategori utama">
      <div className="grid grid-cols-3 gap-2.5">
        {HOMEPAGE_SERVICE_CARDS.map((card) => (
          <Link
            key={card.id}
            to={card.href}
            aria-label={card.title}
            className="group relative aspect-[1.12/1] min-w-0 overflow-hidden rounded-2xl bg-secondary shadow-sm transition duration-200 hover:-translate-y-0.5 hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary active:scale-[0.98]"
          >
            <img
              src={imageOverrides[card.id] || card.fallbackImage}
              alt={card.imageAlt}
              loading={card.id === 'food' ? 'eager' : 'lazy'}
              decoding="async"
              className="absolute inset-0 h-full w-full object-cover object-right transition-transform duration-300 group-hover:scale-[1.03]"
            />
            <span aria-hidden="true" className="absolute inset-0 bg-gradient-to-t from-black/65 via-black/10 to-transparent" />
            <span className="absolute bottom-3 left-3 right-10 text-left text-sm font-extrabold leading-tight text-white drop-shadow sm:text-base">
              {card.title}
            </span>
            <span aria-hidden="true" className="absolute bottom-2.5 right-2.5 flex h-8 w-8 items-center justify-center rounded-full bg-white text-primary shadow-sm transition-transform group-hover:translate-x-0.5">
              <ChevronRight className="h-5 w-5" />
            </span>
          </Link>
        ))}
      </div>
    </section>
  );
}
