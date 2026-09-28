import { FormEvent, useEffect, useRef, useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { ShoppingCart, MapPin, ChevronDown, LocateFixed, Search, X } from 'lucide-react';
import { NotificationDropdown } from '@/components/notifications/NotificationDropdown';
import { useWhitelabel } from '@/hooks/useWhitelabel';
import { useCart } from '@/contexts/CartContext';
import { Button } from '@/components/ui/button';
import { useUserLocation } from '@/hooks/useUserLocation';
import { useSavedAddresses } from '@/hooks/useSavedAddresses';
import { useProfileAddress } from '@/hooks/useProfileAddress';

interface SelectedAddressSummary {
  id?: string;
  label: string;
  address: string;
  full_address?: string | null;
  address_detail?: string | null;
  village_name?: string | null;
  district_name?: string | null;
  city_name?: string | null;
}

export function Header() {
  const { settings } = useWhitelabel();
  const navigate = useNavigate();
  const route = useLocation();
  const { location: userLocation, loading: locationLoading } = useUserLocation();
  const { addresses: savedAddresses, refetch: refetchSavedAddresses } = useSavedAddresses();
  const { address: profileAddress } = useProfileAddress();
  const { getItemCount } = useCart();
  const cartCount = getItemCount();
  const [searchQuery, setSearchQuery] = useState('');
  const [searchOpen, setSearchOpen] = useState(false);
  const popupSearchRef = useRef<HTMLInputElement>(null);
  const isHome = route.pathname === '/';
  const [selectedAddress, setSelectedAddress] = useState<SelectedAddressSummary | null>(() => {
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

  useEffect(() => {
    const syncAddresses = () => { void refetchSavedAddresses(); };
    window.addEventListener('sadesa-addresses-updated', syncAddresses);
    return () => window.removeEventListener('sadesa-addresses-updated', syncAddresses);
  }, [refetchSavedAddresses]);

  useEffect(() => {
    if (!searchOpen) return;
    popupSearchRef.current?.focus();
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setSearchOpen(false);
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [searchOpen]);

  const defaultSavedAddress = savedAddresses.find((address) => address.is_default) || null;
  const firstSavedAddress = savedAddresses[0] || null;
  const selectedSavedAddress = selectedAddress?.id && selectedAddress.id !== 'profile'
    ? savedAddresses.find((address) => address.id === selectedAddress.id)
    : null;
  const manuallySelectedAddress = selectedAddress?.id === 'profile'
    ? profileAddress
    : selectedSavedAddress || (selectedAddress?.id ? null : selectedAddress);
  const activeAddress = manuallySelectedAddress || defaultSavedAddress || profileAddress || firstSavedAddress;
  const selectedAddressFallback = activeAddress && 'address' in activeAddress ? activeAddress.address : '';
  const activeAddressText = activeAddress?.full_address || [
    activeAddress?.address_detail,
    activeAddress?.village_name,
    activeAddress?.district_name,
    activeAddress?.city_name,
  ].filter(Boolean).join(', ') || selectedAddressFallback || '';

  const submitSearch = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const query = searchQuery.trim();
    setSearchOpen(false);
    navigate(query ? `/search?q=${encodeURIComponent(query)}` : '/');
  };

  return (
    <header className={`sticky top-0 border-b border-emerald-50 bg-white/95 px-4 pb-2.5 pt-2.5 backdrop-blur-xl sm:px-5 sm:pb-3 sm:pt-3 ${searchOpen ? 'z-[60]' : 'z-40'}`}>
      <div className="flex min-h-10 items-center justify-between gap-3">
        <Link to="/" className="flex min-w-0 items-center gap-2">
          <img
            src={settings.logoUrl || '/branding/sadesa-logo.webp'}
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

      <div className="mt-2 flex items-stretch gap-2">
        <button
          type="button"
          onClick={() => navigate('/addresses?select=1')}
          className={`group relative flex min-h-[3.5rem] min-w-0 flex-1 items-center gap-2 overflow-hidden rounded-[1.15rem] border border-[#e4ece1] bg-gradient-to-r from-white via-white to-[#f5faef] px-2.5 py-2 text-left shadow-[0_8px_22px_-18px_rgba(1,87,48,0.38)] transition duration-200 hover:border-[#b8d9a6] hover:shadow-[0_12px_26px_-18px_rgba(1,87,48,0.34)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#44a31b]/50`}
          aria-label="Pilih lokasi pengantaran"
        >
          <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-[0.8rem] bg-[#015730] text-white shadow-[0_5px_12px_-6px_rgba(1,87,48,0.7)] transition-transform duration-200 group-hover:scale-[1.04]"><MapPin className="h-4 w-4 fill-white/15 stroke-white" /></span>
          <span className="min-w-0 flex-1">
            <span className="mb-0.5 flex min-w-0 items-center gap-1.5 overflow-hidden text-[8px] font-bold uppercase tracking-[0.1em] text-[#557365] sm:text-[9px] sm:tracking-[0.13em]">
              <span className="truncate">Alamat pengantaran</span>
              <span className="h-1 w-1 shrink-0 rounded-full bg-[#44a31b]" />
              {activeAddress?.label && <span className="truncate normal-case tracking-normal text-[#015730]">{activeAddress.label}</span>}
            </span>
            <span className="block truncate text-[12px] font-semibold leading-snug tracking-[-0.01em] text-[#173d2c] sm:text-[13px]">
              {activeAddressText || (locationLoading ? 'Mencari lokasi...' : userLocation?.district) || 'Pilih alamat pengantaran'}
            </span>
          </span>
          {!activeAddressText && !userLocation && !locationLoading && <span className="hidden items-center gap-1 text-[9px] font-semibold text-[#557365] sm:flex"><LocateFixed className="h-3 w-3" />Pilih alamat</span>}
          <span className="ml-auto flex h-7 w-7 shrink-0 items-center justify-center rounded-full border border-[#e5eee0] bg-white/90 text-[#015730] shadow-sm transition-all group-hover:border-[#b8d9a6] group-hover:bg-[#edf7e6]">
            <ChevronDown className="h-3.5 w-3.5 transition-transform duration-200 group-hover:translate-y-0.5" />
          </span>
        </button>

        {isHome && (
          <form onSubmit={submitSearch} className="relative w-[3.5rem] shrink-0">
            <button
              type="button"
              onClick={() => setSearchOpen(true)}
              aria-label="Buka pencarian makanan, barang, jasa, atau tujuan"
              aria-expanded={searchOpen}
              aria-haspopup="dialog"
              className="flex h-[3.5rem] w-[3.5rem] items-center justify-center rounded-full border border-[#d9ebd0] bg-white text-[#015730] shadow-[0_7px_20px_-12px_rgba(1,87,48,0.25)] outline-none transition hover:border-[#44a31b] hover:bg-[#f5faef] focus-visible:border-[#44a31b] focus-visible:ring-4 focus-visible:ring-[#44a31b]/15"
            >
              <Search className="h-[19px] w-[19px]" aria-hidden="true" />
            </button>
            {searchOpen && (
              <>
                <button
                  type="button"
                  aria-label="Tutup pencarian"
                  onClick={() => setSearchOpen(false)}
                  className="fixed inset-0 z-0 h-screen w-screen cursor-default bg-slate-950/20 backdrop-blur-[2px]"
                />
                <div
                  role="dialog"
                  aria-label="Pencarian SaDesa"
                  className="absolute right-0 top-[calc(100%+0.65rem)] z-10 w-[min(92vw,28rem)] rounded-[1.35rem] border border-[#dcebd6] bg-white p-3 text-left shadow-[0_18px_50px_-20px_rgba(1,87,48,0.55)]"
                >
                  <div className="mb-2 flex items-center justify-between px-1">
                    <div>
                      <p className="text-sm font-bold text-[#173d2c]">Cari di SaDesa</p>
                      <p className="text-[11px] text-[#557365]">Temukan makanan, barang, jasa, atau tujuan</p>
                    </div>
                    <button
                      type="button"
                      onClick={() => setSearchOpen(false)}
                      className="flex h-8 w-8 items-center justify-center rounded-full text-[#557365] transition hover:bg-[#edf7e6] hover:text-[#015730]"
                      aria-label="Tutup"
                    >
                      <X className="h-4 w-4" />
                    </button>
                  </div>
                  <div className="relative">
                    <Search className="pointer-events-none absolute left-3.5 top-1/2 h-5 w-5 -translate-y-1/2 text-[#015730]" aria-hidden="true" />
                    <input
                      ref={popupSearchRef}
                      value={searchQuery}
                      onChange={(event) => setSearchQuery(event.target.value)}
                      aria-label="Masukkan pencarian"
                      placeholder="Cari makanan, barang, jasa, atau tujuan..."
                      className="h-12 w-full rounded-full border border-[#b8d9a6] bg-[#fbfef9] pl-11 pr-4 text-sm text-slate-800 outline-none ring-4 ring-[#44a31b]/10 transition focus:border-[#44a31b] focus:ring-[#44a31b]/20"
                    />
                  </div>
                  <div className="mt-3 flex flex-wrap gap-2 px-1">
                    {['Makanan', 'Belanja', 'Jasa'].map((item) => (
                      <button
                        key={item}
                        type="button"
                        onClick={() => { setSearchQuery(item); popupSearchRef.current?.focus(); }}
                        className="rounded-full border border-[#d9ebd0] bg-[#f5faef] px-3 py-1.5 text-[11px] font-semibold text-[#28633e] transition hover:border-[#44a31b] hover:bg-[#edf7e6]"
                      >
                        {item}
                      </button>
                    ))}
                  </div>
                  <button type="submit" className="mt-3 h-10 w-full rounded-full bg-[#015730] text-xs font-bold text-white transition hover:bg-[#014a29]">
                    Tampilkan hasil pencarian
                  </button>
                </div>
              </>
            )}
          </form>
        )}
      </div>

    </header>
  );
}
