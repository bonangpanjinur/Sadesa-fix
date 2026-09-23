import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { ShoppingCart, MapPin, ChevronRight, LocateFixed } from 'lucide-react';
import { NotificationDropdown } from '@/components/notifications/NotificationDropdown';
import { useWhitelabel } from '@/hooks/useWhitelabel';
import { useCart } from '@/contexts/CartContext';
import { Button } from '@/components/ui/button';
import { useUserLocation } from '@/hooks/useUserLocation';

export function Header() {
  const { settings } = useWhitelabel();
  const navigate = useNavigate();
  const { location: userLocation, loading: locationLoading } = useUserLocation();
  const { getItemCount } = useCart();
  const cartCount = getItemCount();
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
        onClick={() => navigate('/addresses?select=1')}
        className="group mt-2 flex min-h-11 w-full items-center gap-2 rounded-2xl border border-orange-100 bg-white px-3 py-2 text-left shadow-[0_8px_20px_-18px_hsl(4_78%_47%_/_0.8)] transition hover:border-primary/30"
        aria-label="Pilih lokasi pengantaran"
      >
        <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary"><MapPin className="h-4 w-4" /></span>
        <span className="min-w-0 flex-1">
          <span className="block text-[10px] font-bold uppercase tracking-[0.12em] text-muted-foreground">Alamat pengantaran</span>
          <span className="block truncate text-xs font-bold leading-tight text-foreground">
            {locationLoading ? 'Mencari lokasi...' : selectedAddress?.address || userLocation?.district || 'Pilih alamat pengantaran'}
          </span>
        </span>
        {!selectedAddress && !userLocation && !locationLoading && <span className="hidden items-center gap-1 text-[9px] font-bold text-primary sm:flex"><LocateFixed className="h-3 w-3" />Pilih</span>}
        <ChevronRight className="ml-auto h-3.5 w-3.5 shrink-0 text-primary transition-transform group-hover:translate-x-0.5" />
      </button>

    </header>
  );
}
