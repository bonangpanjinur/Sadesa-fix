import { ArrowRight, Bike, ShoppingBag, UtensilsCrossed, Wrench } from 'lucide-react';
import { Link } from 'react-router-dom';
import foodImage from '@/assets/home/service-food-optimized.jpg';
import ojekImage from '@/assets/home/service-ojek-optimized.jpg';
import shoppingImage from '@/assets/home/service-shopping-optimized.jpg';
import servicesImage from '@/assets/home/service-services-optimized.jpg';

const services = [
  {
    name: 'Makanan & Minuman',
    description: 'Pesan favorit dari warung sekitar',
    href: '/products?type=kuliner',
    image: foodImage,
    icon: UtensilsCrossed,
    palette: {
      card: 'bg-[#fff0ef] border-[#f4c9ca]',
      wash: 'from-[#fff0ef]/98 via-[#fff0ef]/90',
      icon: 'bg-[#E31019] text-white shadow-[0_5px_14px_-5px_#E31019]',
      title: 'text-[#a70c16]',
      description: 'text-[#70353a]',
      arrow: 'bg-[#E31019] text-white',
    },
  },
  {
    name: 'Ojek',
    description: 'Pergi ke mana saja dengan cepat',
    href: '/ride',
    image: ojekImage,
    icon: Bike,
    palette: {
      card: 'bg-[#015730] border-[#0c7749]',
      wash: 'from-[#015730]/95 via-[#0c7749]/85',
      icon: 'bg-white text-[#015730] shadow-[0_5px_14px_-5px_#001f11]',
      title: 'text-white',
      description: 'text-white/90',
      arrow: 'bg-[#44a31b] text-white',
    },
  },
  {
    name: 'Belanja',
    description: 'Kebutuhan harian dan produk lokal',
    href: '/products?type=belanja',
    image: shoppingImage,
    icon: ShoppingBag,
    palette: {
      card: 'bg-[#fff0ef] border-[#f4c9ca]',
      wash: 'from-[#fff0ef]/98 via-[#fff0ef]/90',
      icon: 'bg-[#E31019] text-white shadow-[0_5px_14px_-5px_#E31019]',
      title: 'text-[#a70c16]',
      description: 'text-[#70353a]',
      arrow: 'bg-[#E31019] text-white',
    },
  },
  {
    name: 'Jasa',
    description: 'Temukan jasa warga tepercaya',
    href: '/services',
    image: servicesImage,
    icon: Wrench,
    palette: {
      card: 'bg-[#eaf5df] border-[#cde5b5]',
      wash: 'from-[#eaf5df]/98 via-[#eaf5df]/90',
      icon: 'bg-[#015730] text-white shadow-[0_5px_14px_-5px_#015730]',
      title: 'text-[#015730]',
      description: 'text-[#315c44]',
      arrow: 'bg-[#44a31b] text-white',
    },
  },
];

export function HomeServiceCards() {
  return (
    <section className="mx-4 mt-1" aria-label="Pilih layanan SaDesa">
      <div className="grid gap-3" style={{ gridTemplateColumns: 'repeat(2, minmax(0, 1fr))' }}>
        {services.map(({ name, description, href, image, icon: Icon, palette }) => (
          <Link
            key={name}
            to={href}
            className={`group relative isolate flex aspect-[1.42/1] min-h-[128px] flex-col overflow-hidden rounded-[1.3rem] border shadow-[0_12px_25px_-16px_rgba(1,87,48,0.42)] transition duration-200 hover:-translate-y-0.5 hover:shadow-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#44a31b] active:scale-[0.98] ${palette.card}`}
          >
            <img src={image} alt="" aria-hidden="true" className="absolute inset-0 z-0 h-full w-full object-cover object-right transition-transform duration-500 group-hover:scale-[1.04]" />
            <span className={`pointer-events-none absolute inset-0 z-10 bg-gradient-to-r ${palette.wash} to-transparent`} />
            <span className={`relative z-20 ml-3 mt-3 flex h-10 w-10 items-center justify-center rounded-full ring-2 ring-white/75 sm:ml-4 sm:mt-4 ${palette.icon}`}>
              <Icon className="h-[1.15rem] w-[1.15rem] stroke-[2.1]" aria-hidden="true" />
            </span>
            <span className="relative z-20 mt-auto block max-w-[76%] pb-3 pl-3 pr-1 text-left sm:pb-4 sm:pl-4">
              <span className={`block font-serif text-[15px] font-bold leading-[1.05] tracking-[-0.025em] sm:text-base ${palette.title}`}>{name}</span>
              <span className={`mt-1 block text-[10px] leading-[1.25] sm:text-[11px] ${palette.description}`}>{description}</span>
            </span>
            <span className={`absolute bottom-3 right-3 z-20 flex h-7 w-7 items-center justify-center rounded-full shadow-sm ring-1 ring-white/50 transition-transform group-hover:translate-x-0.5 sm:bottom-4 sm:right-4 ${palette.arrow}`}>
              <ArrowRight className="h-4 w-4" aria-hidden="true" />
            </span>
          </Link>
        ))}
      </div>
    </section>
  );
}
