import { FormEvent, useEffect, useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { ShoppingCart, MapPin, ChevronDown, LocateFixed, Search } from 'lucide-react';
import { NotificationDropdown } from '@/components/notifications/NotificationDropdown';
import { useWhitelabel } from '@/hooks/useWhitelabel';
import { useCart } from '@/contexts/CartContext';
import { Button } from '@/components/ui/button';
import { useUserLocation } from '@/hooks/useUserLocation';

export function Header() {
  const { settings } = useWhitelabel();
  const navigate = useNavigate();
  const route = useLocation();
  const { location: userLocation, loading: locationLoading } = useUserLocation();
  const { getItemCount } = useCart();
  const cartCount = getItemCount();
  const [searchQuery, setSearchQuery] = useState('');
  const isHome = route.pathname === '/';
  const [selectedAddress, setSelectedAddress] = useState<{ label: string; address: string } | null>(() => {
    try {
      const saved = localStorage.getItem('sadesa-selected-address');
      return saved ? JSON.parse(saved) : null;
    } catch {
      return null;
    }
  });

  useEffect(() => {
    const syncSelectedAddress = () => {
      try {
        const saved = localStorage.getItem('sadesa-selected-address');
        setSelectedAddress(saved ? JSON.parse(saved) : null);
      } catch {
        setSelectedAddress(null);
      }
    };
    window.addEventListener('sadesa-address-selected', syncSelectedAddress);
    window.addEventListener('storage', syncSelectedAddress);
    return () => {
      window.removeEventListener('sadesa-address-selected', syncSelectedAddress);
      window.removeEventListener('storage', syncSelectedAddress);
    };
  }, []);

  const submitSearch = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const query = searchQuery.trim();
    navigate(query ? `/products?q=${encodeURIComponent(query)}` : '/products');
  };

  return (
    <header className="sticky top-0 z-40 border-b border-emerald-50 bg-white/95 px-4 pb-3 pt-3 backdrop-blur-xl sm:px-5 sm:pb-3.5 sm:pt-3.5">
      <div className="flex min-h-10 items-center justify-between gap-3">
        <Link to="/" className="flex min-w-0 items-center gap-2">
          <img
            src={settings.logoUrl || '/branding/sadesa-logo.png'}
            alt={settings.siteName}
            className="h-11 w-auto max-w-[172px] object-contain"
          />
        </Link>

        <div className="flex shrink-0 items-center gap-0.5">
          <Button
            variant="ghost"
            size="icon"
            onClick={() => navigate('/cart')}
            className="relative h-10 w-10 rounded-full border border-[#d2e9c3] bg-[#edf7e6] text-[#015730] hover:bg-[#dff1d4]"
            aria-label="Keranjang"
          >
            <ShoppingCart className="h-[19px] w-[19px]" />
            {cartCount > 0 && (
              <span className="absolute -right-0.5 -top-0.5 flex h-5 min-w-5 items-center justify-center rounded-full bg-[#E31019] px-1 text-[10px] font-bold text-white ring-2 ring-white">
                {cartCount > 9 ? '9+' : cartCount}
              </span>
            )}
          </Button>
          <NotificationDropdown />
        </div>
      </div>

      <button
        type="button"
        onClick={() => navigate('/addresses?select=1')}
        className="group mt-3 flex min-h-[3.75rem] w-full items-center gap-3 rounded-[1.5rem] border border-[#dbeed1] bg-[#f2f8ee] px-4 py-2.5 text-left transition hover:border-[#44a31b]/50 hover:bg-[#eaf5e1]"
        aria-label="Pilih lokasi pengantaran"
      >
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[#44a31b] text-white shadow-sm"><MapPin className="h-[1.15rem] w-[1.15rem] fill-[#015730] stroke-white" /></span>
        <span className="min-w-0 flex-1">
          <span className="block text-[11px] font-medium text-slate-500">Alamat Pengantaran</span>
          <span className="block truncate text-sm font-bold leading-tight text-slate-900">
            {locationLoading ? 'Mencari lokasi...' : selectedAddress?.address || userLocation?.district || 'Pilih alamat pengantaran'}
          </span>
        </span>
        {!selectedAddress && !userLocation && !locationLoading && <span className="hidden items-center gap-1 text-[9px] font-bold text-emerald-700 sm:flex"><LocateFixed className="h-3 w-3" />Pilih</span>}
        <ChevronDown className="ml-auto h-4 w-4 shrink-0 text-slate-600 transition-transform group-hover:translate-y-0.5" />
      </button>

      {isHome && (
        <form onSubmit={submitSearch} className="relative mt-3">
          <Search className="pointer-events-none absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-[#015730]" aria-hidden="true" />
          <input
            value={searchQuery}
            onChange={(event) => setSearchQuery(event.target.value)}
            aria-label="Cari makanan, barang, jasa, atau tujuan"
            placeholder="Cari makanan, barang, jasa, atau tujuan..."
            className="h-[3.55rem] w-full rounded-full border border-[#d9ebd0] bg-white pl-12 pr-5 text-sm text-slate-800 shadow-[0_7px_20px_-12px_rgba(1,87,48,0.25)] outline-none transition placeholder:text-slate-500 focus:border-[#44a31b] focus:ring-4 focus:ring-[#44a31b]/15"
          />
        </form>
      )}

    </header>
  );
}
