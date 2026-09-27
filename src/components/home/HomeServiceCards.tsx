import { ArrowRight, Bike, ShoppingBag, UtensilsCrossed, Wrench } from 'lucide-react';
import { Link } from 'react-router-dom';
import foodImage from '@/assets/home/service-food-optimized.jpg';
import ojekImage from '@/assets/home/service-ojek-optimized.jpg';
import shoppingImage from '@/assets/home/service-shopping-optimized.jpg';
import servicesImage from '@/assets/home/service-services-optimized.jpg';

const services = [
  {
    name: 'Makanan & Minuman',
    href: '/products?type=kuliner',
    image: foodImage,
    icon: UtensilsCrossed,
    palette: {
      card: 'bg-[#fff0ef] border-[#f4c9ca]',
      wash: 'from-[#fff0ef]/98 via-[#fff0ef]/90',
      icon: 'bg-[#E31019] text-white shadow-[0_5px_14px_-5px_#E31019]',
      title: 'text-[#a70c16]',
      arrow: 'bg-[#E31019] text-white',
    },
  },
  {
    name: 'Ojek',
    href: '/ride',
    image: ojekImage,
    icon: Bike,
    palette: {
      card: 'bg-[#015730] border-[#0c7749]',
      wash: 'from-[#015730]/95 via-[#0c7749]/85',
      icon: 'bg-white text-[#015730] shadow-[0_5px_14px_-5px_#001f11]',
      title: 'text-white',
      arrow: 'bg-[#44a31b] text-white',
    },
  },
  {
    name: 'Belanja',
    href: '/products?type=belanja',
    image: shoppingImage,
    icon: ShoppingBag,
    palette: {
      card: 'bg-[#fff8dc] border-[#f1df9a]',
      wash: 'from-[#fff8dc]/98 via-[#fff8dc]/90',
      icon: 'bg-[#d99a00] text-white shadow-[0_5px_14px_-5px_#d99a00]',
      title: 'text-[#8a5a00]',
      arrow: 'bg-[#d99a00] text-white',
    },
  },
  {
    name: 'Jasa',
    href: '/services',
    image: servicesImage,
    icon: Wrench,
    palette: {
      card: 'bg-[#eaf5df] border-[#cde5b5]',
      wash: 'from-[#eaf5df]/98 via-[#eaf5df]/90',
      icon: 'bg-[#015730] text-white shadow-[0_5px_14px_-5px_#015730]',
      title: 'text-[#015730]',
      arrow: 'bg-[#44a31b] text-white',
    },
  },
];

export function HomeServiceCards() {
  return (
    <section className="mx-4 mt-1" aria-label="Pilih layanan SaDesa">
      <div className="grid gap-3" style={{ gridTemplateColumns: 'repeat(2, minmax(0, 1fr))' }}>
        {services.map(({ name, href, image, icon: Icon, palette }) => (
          <Link
            key={name}
            to={href}
            className={`group relative isolate flex h-[92px] min-h-0 flex-row items-center overflow-hidden rounded-[1.15rem] border shadow-[0_12px_25px_-16px_rgba(1,87,48,0.42)] transition duration-200 hover:-translate-y-0.5 hover:shadow-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#44a31b] active:scale-[0.98] ${palette.card}`}
          >
            <img src={image} alt="" aria-hidden="true" className="absolute inset-0 z-0 h-full w-full object-cover object-right transition-transform duration-500 group-hover:scale-[1.04]" />
            <span className={`pointer-events-none absolute inset-0 z-10 bg-gradient-to-r ${palette.wash} to-transparent`} />
            <span className={`relative z-20 ml-3 flex h-9 w-9 shrink-0 items-center justify-center rounded-full ring-2 ring-white/75 sm:ml-4 ${palette.icon}`}>
              <Icon className="h-4 w-4 stroke-[2.1]" aria-hidden="true" />
            </span>
            <span className="relative z-20 min-w-0 flex-1 px-2 text-left sm:px-3">
              <span className={`block font-serif text-[13px] font-bold leading-[1.1] tracking-[-0.02em] sm:text-sm ${palette.title}`}>{name}</span>
            </span>
            <span className={`relative z-20 mr-2 flex h-6 w-6 shrink-0 items-center justify-center rounded-full shadow-sm ring-1 ring-white/50 transition-transform group-hover:translate-x-0.5 sm:mr-3 ${palette.arrow}`}>
              <ArrowRight className="h-3.5 w-3.5" aria-hidden="true" />
            </span>
          </Link>
        ))}
      </div>
    </section>
  );
}
