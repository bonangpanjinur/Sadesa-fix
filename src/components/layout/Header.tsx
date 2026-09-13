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
    <header className="sticky top-0 z-40 border-b border-border/40 bg-card/95 px-4 pb-2.5 pt-2 backdrop-blur-xl sm:px-5 sm:pb-3 sm:pt-2.5">
      <div className="flex min-h-9 items-center justify-between gap-2">
        <Link to="/" className="flex min-w-0 items-center gap-2">
          <img
            src={settings.logoUrl || '/branding/sadesa-logo.png'}
            alt={settings.siteName}
            className="h-8 w-8 rounded-lg object-cover shadow-sm"
          />
          <h1 className="truncate font-heading text-[1.05rem] font-bold leading-none text-foreground">
            {settings.siteName}
          </h1>
        </Link>

        <div className="flex shrink-0 items-center gap-0.5">
          <Button
            variant="ghost"
            size="icon"
            onClick={handleChatNavigation}
            className="relative h-8 w-8 rounded-lg text-muted-foreground"
            aria-label="Chat"
          >
            <MessageCircle className="h-[17px] w-[17px]" />
            {chatUnread > 0 && (
              <span className="absolute right-0.5 top-0.5 flex h-3.5 min-w-3.5 items-center justify-center rounded-full bg-destructive px-0.5 text-[7px] font-bold text-destructive-foreground">
                {chatUnread > 9 ? '9+' : chatUnread}
              </span>
            )}
            {isRealtimeFailure(chatRealtimeStatus) && (
              <span
                className="absolute bottom-1 right-1 h-1.5 w-1.5 rounded-full bg-muted-foreground/70 ring-1 ring-background"
                title={`Realtime chat terputus (${chatRealtimeStatus})`}
              />
            )}
          </Button>
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
        className="group flex min-h-7 w-full items-center gap-2 rounded-lg px-0.5 py-0.5 text-left transition hover:bg-primary/[0.05]"
        aria-label="Pilih lokasi pengantaran"
      >
        <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-md bg-primary/10 text-primary">
          <MapPin className="h-3.5 w-3.5" />
        </span>
        <span className="mr-1 text-[8px] font-semibold uppercase tracking-[0.1em] text-muted-foreground">Antar ke</span>
        <span className="truncate text-[11px] font-bold leading-tight text-foreground">
          {locationLoading ? 'Mencari lokasi...' : userLocation?.district || 'Pilih lokasi pengantaran'}
        </span>
        <ChevronRight className="ml-auto h-3.5 w-3.5 shrink-0 text-primary transition-transform group-hover:translate-x-0.5" />
      </button>

      {showSearchBar && (
        <form onSubmit={handleSearch} className="group relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground transition-colors group-focus-within:text-primary" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Cari makanan, restoran, atau produk..."
            aria-label="Cari makanan, restoran, atau produk"
            className="h-10 w-full rounded-lg border border-transparent bg-[hsl(var(--brand-light))] pl-10 pr-4 text-xs outline-none transition placeholder:text-muted-foreground/75 focus:border-primary/30 focus:bg-card focus:ring-4 focus:ring-primary/10"
          />
        </form>
      )}
    </header>
  );
}
