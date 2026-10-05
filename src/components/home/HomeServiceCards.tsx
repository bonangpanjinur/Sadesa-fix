import { Coffee, ShoppingBag, UtensilsCrossed } from 'lucide-react';
import { Link } from 'react-router-dom';

const services = [
  {
    name: 'Makanan',
    href: '/products?type=makanan',
    icon: UtensilsCrossed,
    palette: {
      icon: 'bg-[#E31019] text-white shadow-[0_6px_14px_-6px_#E31019]',
      title: 'text-[#a70c16]',
    },
  },
  {
    name: 'Minuman',
    href: '/products?type=minuman',
    icon: Coffee,
    palette: {
      icon: 'bg-[#015730] text-white shadow-[0_6px_14px_-6px_#015730]',
      title: 'text-[#015730]',
    },
  },
  {
    name: 'Belanja',
    href: '/products?type=kelontongan',
    icon: ShoppingBag,
    palette: {
      icon: 'bg-[#d99a00] text-white shadow-[0_6px_14px_-6px_#d99a00]',
      title: 'text-[#8a5a00]',
    },
  },
];

export function HomeServiceCards() {
  return (
    <section className="mx-4" aria-labelledby="home-services-title">
      <div className="mb-3">
        <h2 id="home-services-title" className="font-heading text-base font-extrabold tracking-tight text-[#173d2c]">
          Kategori utama
        </h2>
        <p className="mt-1 text-xs leading-relaxed text-[#557365]">
          Makanan lokal, minuman, dan kebutuhan harian dalam satu tempat.
        </p>
      </div>
      <div className="grid grid-cols-3 gap-2.5">
        {services.map(({ name, href, icon: Icon, palette }) => (
          <Link
            key={name}
            to={href}
            className="group flex min-h-[5.75rem] min-w-0 flex-col items-center justify-center gap-2 rounded-2xl border border-[#e7eee3] bg-white px-2 py-2.5 text-center shadow-[0_8px_20px_-18px_rgba(1,87,48,0.5)] transition duration-200 hover:-translate-y-0.5 hover:border-[#b8d9a6] hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#44a31b] active:scale-[0.98]"
          >
            <span className={`flex h-10 w-10 items-center justify-center rounded-[0.9rem] ${palette.icon}`}>
              <Icon className="h-[18px] w-[18px] stroke-[2.1] transition-transform duration-200 group-hover:scale-110" aria-hidden="true" />
            </span>
            <span className={`w-full text-[11px] font-bold leading-tight sm:text-xs ${palette.title}`}>{name}</span>
          </Link>
        ))}
      </div>
    </section>
  );
}
