import { useState } from 'react';
import { Link, useNavigate, useLocation } from 'react-router-dom';
import { Search, ShoppingCart, MapPin, ChevronRight } from 'lucide-react';
import { NotificationDropdown } from '@/components/notifications/NotificationDropdown';
import { useWhitelabel } from '@/hooks/useWhitelabel';
import { useCart } from '@/contexts/CartContext';
import { Button } from '@/components/ui/button';
import { useUserLocation } from '@/hooks/useUserLocation';
import { getTimeAwareSearchPlaceholder } from '@/lib/timeAwareSearch';

export function Header() {
  const { settings } = useWhitelabel();
  const navigate = useNavigate();
  const location = useLocation();
  const [searchQuery, setSearchQuery] = useState('');
  const { location: userLocation, loading: locationLoading } = useUserLocation();
  const showSearchBar = location.pathname === '/';
  const { getItemCount } = useCart();
  const cartCount = getItemCount();

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    if (searchQuery.trim()) {
      navigate(`/search?q=${encodeURIComponent(searchQuery.trim())}`);
      setSearchQuery('');
    }
  };

  return (
    <header className="sticky top-0 z-40 border-b border-orange-100/80 bg-[hsl(36_45%_98%_/_0.96)] px-4 pb-3 pt-3 backdrop-blur-xl sm:px-5 sm:pb-3.5 sm:pt-3.5">
      <div className="flex min-h-9 items-center justify-between gap-3">
        <Link to="/" className="flex min-w-0 items-center gap-2">
          <img
            src={settings.logoUrl || '/branding/sadesa-logo.png'}
            alt={settings.siteName}
            className="h-10 w-auto max-w-[150px] object-contain"
          />
        </Link>

        <div className="flex shrink-0 items-center gap-0.5">
          <Button
            variant="ghost"
            size="icon"
            onClick={() => navigate('/cart')}
            className="relative h-8 w-8 rounded-lg text-muted-foreground"
            aria-label="Keranjang"
          >
            <ShoppingCart className="h-[17px] w-[17px]" />
            {cartCount > 0 && (
              <span className="absolute right-0.5 top-0.5 flex h-3.5 min-w-3.5 items-center justify-center rounded-full bg-primary px-0.5 text-[7px] font-bold text-primary-foreground">
                {cartCount > 9 ? '9+' : cartCount}
              </span>
            )}
          </Button>
          <NotificationDropdown />
        </div>
      </div>

      <button
        type="button"
        onClick={() => navigate('/addresses')}
        className="group flex min-h-7 w-full items-center gap-2 px-0.5 py-1 text-left transition"
        aria-label="Pilih lokasi pengantaran"
      >
        <MapPin className="h-3.5 w-3.5 shrink-0 text-primary" />
        <span className="text-[8px] font-bold uppercase tracking-[0.12em] text-muted-foreground">Antar ke</span>
        <span className="truncate text-[11px] font-bold leading-tight text-foreground">
          {locationLoading ? 'Mencari lokasi...' : userLocation?.district || 'Pilih lokasi pengantaran'}
        </span>
        <ChevronRight className="ml-auto h-3.5 w-3.5 shrink-0 text-primary transition-transform group-hover:translate-x-0.5" />
      </button>

      {showSearchBar && (
        <form onSubmit={handleSearch} className="group relative mt-1">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground transition-colors group-focus-within:text-primary" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder={getTimeAwareSearchPlaceholder()}
            aria-label="Cari makanan, restoran, atau produk"
            className="h-11 w-full rounded-2xl border border-orange-100 bg-white pl-10 pr-4 text-xs shadow-[0_8px_24px_-18px_hsl(4_78%_47%_/_0.6)] outline-none transition placeholder:text-muted-foreground/70 focus:border-primary/30 focus:ring-4 focus:ring-primary/10"
          />
        </form>
      )}
    </header>
  );
}
