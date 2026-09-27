import { Bike, ShoppingBag, UtensilsCrossed, Wrench } from 'lucide-react';
import { Link } from 'react-router-dom';

const services = [
  {
    name: 'Makanan & Minuman',
    href: '/products?type=kuliner',
    icon: UtensilsCrossed,
    palette: {
      icon: 'bg-[#E31019] text-white shadow-[0_6px_14px_-6px_#E31019]',
      title: 'text-[#a70c16]',
    },
  },
  {
    name: 'Ojek',
    href: '/ride',
    icon: Bike,
    palette: {
      icon: 'bg-[#015730] text-white shadow-[0_6px_14px_-6px_#015730]',
      title: 'text-[#015730]',
    },
  },
  {
    name: 'Belanja',
    href: '/products?type=belanja',
    icon: ShoppingBag,
    palette: {
      icon: 'bg-[#d99a00] text-white shadow-[0_6px_14px_-6px_#d99a00]',
      title: 'text-[#8a5a00]',
    },
  },
  {
    name: 'Jasa',
    href: '/services',
    icon: Wrench,
    palette: {
      icon: 'bg-[#44a31b] text-white shadow-[0_6px_14px_-6px_#44a31b]',
      title: 'text-[#015730]',
    },
  },
];

export function HomeServiceCards() {
  return (
    <section className="mx-4 mt-1" aria-label="Pilih layanan SaDesa">
      <div className="grid grid-cols-4 gap-2">
        {services.map(({ name, href, icon: Icon, palette }) => (
          <Link
            key={name}
            to={href}
            className="group flex min-w-0 flex-col items-center gap-1.5 rounded-xl px-1 py-1 transition duration-200 hover:-translate-y-0.5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#44a31b] active:scale-[0.98]"
          >
            <span className={`flex h-12 w-12 items-center justify-center rounded-2xl ring-4 ring-white ${palette.icon}`}>
              <Icon className="h-5 w-5 stroke-[2.1] transition-transform duration-200 group-hover:scale-110" aria-hidden="true" />
            </span>
            <span className={`w-full text-center text-[10px] font-semibold leading-tight ${palette.title}`}>{name}</span>
          </Link>
        ))}
      </div>
    </section>
  );
}
