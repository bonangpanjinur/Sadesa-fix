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
    <header className="sticky top-0 z-40 space-y-2.5 border-b border-border/40 bg-card/95 px-4 pb-3 pt-2.5 backdrop-blur-xl sm:px-5 sm:pb-3.5 sm:pt-3">
      <div className="flex min-h-10 min-w-0 items-center justify-between gap-2">
        <Link to="/" className="flex min-w-0 shrink items-center gap-2 sm:gap-3">
          {settings.logoUrl ? (
            <img 
              src={settings.logoUrl} 
              alt={settings.siteName} 
              className="h-8 w-8 rounded-lg object-cover shadow-sm sm:h-9 sm:w-9"
            />
          ) : (
            <img
              src="/branding/sadesa-logo.png"
              alt={settings.siteName}
              className="h-8 w-8 rounded-lg object-cover shadow-sm sm:h-9 sm:w-9"
            />
          )}
          <div className="min-w-0">
            <p className="mb-0.5 truncate text-[8px] font-bold uppercase tracking-[0.15em] text-primary">
              Ekosistem UMKM
            </p>
            <h1 className="truncate font-heading text-[1.05rem] font-bold leading-none text-foreground">
              {settings.siteName}
            </h1>
          </div>
        </Link>
        
         <div className="flex shrink-0 items-center gap-0.5 sm:gap-1">
          <Button
            variant="ghost"
            size="icon"
            onClick={handleChatNavigation}
            className="relative h-8 w-8 rounded-lg text-muted-foreground sm:h-9 sm:w-9"
            aria-label="Chat"
          >
            <MessageCircle className="h-[17px] w-[17px] text-muted-foreground" />
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
            className="relative h-8 w-8 rounded-lg text-muted-foreground sm:h-9 sm:w-9"
            aria-label="Keranjang"
          >
            <ShoppingCart className="h-[17px] w-[17px] text-muted-foreground" />
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
        className="group flex w-full items-center gap-2.5 rounded-xl border border-primary/10 bg-primary/[0.045] px-3 py-2 text-left transition hover:border-primary/20 hover:bg-primary/[0.08]"
        aria-label="Pilih lokasi pengantaran"
      >
        <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
          <MapPin className="h-3.5 w-3.5" />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block text-[8px] font-semibold uppercase tracking-[0.12em] text-muted-foreground">Antar ke</span>
          <span className="mt-0.5 block truncate text-[11px] font-bold leading-tight text-foreground">
            {locationLoading ? 'Mencari lokasi...' : userLocation?.district || 'Pilih lokasi pengantaran'}
          </span>
        </span>
        <ChevronRight className="h-3.5 w-3.5 shrink-0 text-primary transition-transform group-hover:translate-x-0.5" />
      </button>

      {/* Search Bar - Main pages */}
      {showSearchBar && (
        <form onSubmit={handleSearch} className="group relative">
          <Search className="absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground transition-colors group-focus-within:text-primary" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Cari makanan, restoran, atau produk..."
            aria-label="Cari makanan, restoran, atau produk"
            className="h-11 w-full rounded-xl border border-transparent bg-[hsl(var(--brand-light))] pl-11 pr-4 text-xs outline-none transition placeholder:text-muted-foreground/75 focus:border-primary/30 focus:bg-card focus:ring-4 focus:ring-primary/10"
          />
        </form>
      )}
    </header>
  );
}
