import { Bike, ShoppingBag, UtensilsCrossed, Wrench } from 'lucide-react';
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
      icon: 'bg-[#E31019] text-white shadow-[0_5px_14px_-5px_#E31019]',
      title: 'text-[#a70c16]',
    },
  },
  {
    name: 'Ojek',
    href: '/ride',
    image: ojekImage,
    icon: Bike,
    palette: {
      card: 'bg-[#015730] border-[#0c7749]',
      icon: 'bg-white text-[#015730] shadow-[0_5px_14px_-5px_#001f11]',
      title: 'text-[#015730]',
    },
  },
  {
    name: 'Belanja',
    href: '/products?type=belanja',
    image: shoppingImage,
    icon: ShoppingBag,
    palette: {
      card: 'bg-[#fff8dc] border-[#f1df9a]',
      icon: 'bg-[#d99a00] text-white shadow-[0_5px_14px_-5px_#d99a00]',
      title: 'text-[#8a5a00]',
    },
  },
  {
    name: 'Jasa',
    href: '/services',
    image: servicesImage,
    icon: Wrench,
    palette: {
      card: 'bg-[#eaf5df] border-[#cde5b5]',
      icon: 'bg-[#015730] text-white shadow-[0_5px_14px_-5px_#015730]',
      title: 'text-[#015730]',
    },
  },
];

export function HomeServiceCards() {
  return (
    <section className="mx-4 mt-1" aria-label="Pilih layanan SaDesa">
      <div className="grid grid-cols-4 gap-2">
        {services.map(({ name, href, image, icon: Icon, palette }) => (
          <Link
            key={name}
            to={href}
            className="group flex min-w-0 flex-col items-center gap-1 rounded-xl px-1 py-1 transition duration-200 hover:-translate-y-0.5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#44a31b] active:scale-[0.98]"
          >
            <span className={`relative flex h-14 w-14 items-center justify-center overflow-hidden rounded-[1rem] border shadow-[0_5px_12px_-7px_rgba(1,87,48,0.45)] ${palette.card}`}>
              <img src={image} alt="" aria-hidden="true" className="h-full w-full object-cover transition-transform duration-500 group-hover:scale-[1.08]" />
              <span className={`absolute bottom-1 right-1 flex h-5 w-5 items-center justify-center rounded-full ring-2 ring-white/80 ${palette.icon}`}>
                <Icon className="h-3 w-3 stroke-[2.2]" aria-hidden="true" />
              </span>
            </span>
            <span className={`w-full text-center text-[10px] font-semibold leading-tight ${palette.title}`}>{name}</span>
          </Link>
        ))}
      </div>
    </section>
  );
}
