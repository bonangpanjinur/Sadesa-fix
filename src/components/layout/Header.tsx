import { useState } from 'react';
import { Link, useNavigate, useLocation } from 'react-router-dom';
import { Search, ShoppingCart, MessageCircle, MapPin, ChevronRight } from 'lucide-react';
import { NotificationDropdown } from '@/components/notifications/NotificationDropdown';
import { useWhitelabel } from '@/hooks/useWhitelabel';
import { useCart } from '@/contexts/CartContext';
import { useChatUnread } from '@/hooks/useChatUnread';
import { isRealtimeFailure } from '@/lib/realtimeTelemetry';
import { Button } from '@/components/ui/button';
import { useUserLocation } from '@/hooks/useUserLocation';

export function Header() {
  const { settings } = useWhitelabel();
  const navigate = useNavigate();
  const location = useLocation();
  const [searchQuery, setSearchQuery] = useState('');
  const { location: userLocation, loading: locationLoading } = useUserLocation();
  // The broad marketplace search belongs to the home discovery experience.
  // Listing pages keep their own contextual search and filters below this header.
  const showSearchBar = location.pathname === '/';
  const { getItemCount } = useCart();
  const { unreadCount: chatUnread, realtimeStatus: chatRealtimeStatus } = useChatUnread();
  const cartCount = getItemCount();

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    if (searchQuery.trim()) {
      navigate(`/search?q=${encodeURIComponent(searchQuery.trim())}`);
      setSearchQuery('');
    }
  };

  const handleChatNavigation = () => {
    navigate(location.pathname.startsWith('/merchant/') ? '/merchant/chat' : '/buyer/chat');
  };

  return (
    <header className="sticky top-0 z-40 space-y-4 border-b border-border/40 bg-card/95 px-5 pb-5 pt-4 backdrop-blur-xl sm:px-6">
      <div className="flex min-w-0 items-center justify-between gap-2">
        <Link to="/" className="flex min-w-0 shrink items-center gap-2 sm:gap-3">
          {settings.logoUrl ? (
            <img 
              src={settings.logoUrl} 
              alt={settings.siteName} 
              className="h-9 w-9 rounded-xl object-cover shadow-sm sm:h-11 sm:w-11"
            />
          ) : (
            <img
              src="/branding/sadesa-logo.png"
              alt={settings.siteName}
              className="h-9 w-9 rounded-xl object-cover shadow-sm sm:h-11 sm:w-11"
            />
          )}
          <div className="min-w-0">
            <p className="mb-1 truncate text-[9px] font-bold uppercase tracking-[0.16em] text-primary">
              Ekosistem UMKM
            </p>
            <h1 className="truncate font-heading text-[1.15rem] font-bold leading-none text-foreground">
              {settings.siteName}
            </h1>
          </div>
        </Link>
        
         <div className="flex shrink-0 items-center gap-0.5 sm:gap-1">
          <Button
            variant="ghost"
            size="icon"
            onClick={handleChatNavigation}
            className="relative h-9 w-9 rounded-xl text-muted-foreground sm:h-10 sm:w-10"
            aria-label="Chat"
          >
            <MessageCircle className="h-[18px] w-[18px] text-muted-foreground" />
            {chatUnread > 0 && (
              <span className="absolute top-1 right-1 w-4 h-4 bg-destructive rounded-full text-[8px] flex items-center justify-center text-destructive-foreground font-bold">
                {chatUnread > 9 ? '9+' : chatUnread}
              </span>
            )}
            {isRealtimeFailure(chatRealtimeStatus) && (
              <span
                className="absolute bottom-1 right-1 w-2 h-2 rounded-full bg-muted-foreground/70 ring-1 ring-background"
                title={`Realtime chat terputus (${chatRealtimeStatus})`}
              />
            )}
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => navigate('/cart')}
            className="relative h-9 w-9 rounded-xl text-muted-foreground sm:h-10 sm:w-10"
            aria-label="Keranjang"
          >
            <ShoppingCart className="h-[18px] w-[18px] text-muted-foreground" />
            {cartCount > 0 && (
              <span className="absolute top-1 right-1 w-4 h-4 bg-primary rounded-full text-[8px] flex items-center justify-center text-primary-foreground font-bold">
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
        className="group flex w-full items-center gap-3 rounded-2xl border border-primary/10 bg-primary/[0.045] px-3.5 py-2.5 text-left transition hover:border-primary/20 hover:bg-primary/[0.08]"
        aria-label="Pilih lokasi pengantaran"
      >
        <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
          <MapPin className="h-4 w-4" />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block text-[9px] font-semibold uppercase tracking-[0.12em] text-muted-foreground">Antar ke</span>
          <span className="mt-0.5 block truncate text-xs font-bold text-foreground">
            {locationLoading ? 'Mencari lokasi...' : userLocation?.district || 'Pilih lokasi pengantaran'}
          </span>
        </span>
        <ChevronRight className="h-4 w-4 shrink-0 text-primary transition-transform group-hover:translate-x-0.5" />
      </button>

      {/* Search Bar - Main pages */}
      {showSearchBar && (
        <form onSubmit={handleSearch} className="group relative">
          <Search className="absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground transition-colors group-focus-within:text-primary" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Cari makanan, restoran, atau produk..."
            aria-label="Cari makanan, restoran, atau produk"
            className="h-[3.35rem] w-full rounded-[1.15rem] border border-transparent bg-[hsl(var(--brand-light))] pl-12 pr-4 text-[13px] outline-none transition placeholder:text-muted-foreground/75 focus:border-primary/30 focus:bg-card focus:ring-4 focus:ring-primary/10"
          />
        </form>
      )}
    </header>
  );
}
