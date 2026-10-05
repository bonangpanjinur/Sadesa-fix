import heroVillage from '@/assets/hero-village.webp';
import villageBojong from '@/assets/village-bojong.webp';
import villageSukamaju from '@/assets/village-sukamaju.webp';
import type { BannerSlide } from './HeroCarousel';

// Local, compressed content keeps the first viewport useful when the optional
// promotion query is slow or has no active rows.
export const DEFAULT_HERO_SLIDES: BannerSlide[] = [
  {
    id: 'default-food',
    title: 'Rasa lokal, langsung dari desa',
    subtitle: 'Temukan kuliner dan produk UMKM pilihan di sekitar Anda.',
    image: heroVillage,
    linkUrl: '/products?type=kuliner',
  },
  {
    id: 'default-ride',
    title: 'Perjalanan lebih dekat dengan Ojek Desa',
    subtitle: 'Pesan perjalanan dan layanan antar dengan mudah.',
    image: villageBojong,
    linkUrl: '/ride',
  },
  {
    id: 'default-village',
    title: 'Jelajahi potensi desa Indonesia',
    subtitle: 'Dukung ekonomi lokal lewat pengalaman dan produk autentik.',
    image: villageSukamaju,
    linkUrl: '/tourism',
  },
];
