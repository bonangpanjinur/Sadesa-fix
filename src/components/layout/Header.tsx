import { useState } from 'react';
import { Link, useNavigate, useLocation } from 'react-router-dom';
import { Search, ShoppingCart, MessageCircle } from 'lucide-react';
import { NotificationDropdown } from '@/components/notifications/NotificationDropdown';
import { InstallButton } from '@/components/pwa/InstallButton';
import { useWhitelabel } from '@/hooks/useWhitelabel';
import { useCart } from '@/contexts/CartContext';
import { useChatUnread } from '@/hooks/useChatUnread';
import { isRealtimeFailure } from '@/lib/realtimeTelemetry';
import { LanguageSwitcher } from '@/components/common/LanguageSwitcher';

export function Header() {
  const { settings } = useWhitelabel();
  const navigate = useNavigate();
  const location = useLocation();
  const [searchQuery, setSearchQuery] = useState('');
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
    <header className="sticky top-0 z-40 space-y-3 border-b border-border/60 bg-card/95 px-4 pb-4 pt-3 backdrop-blur-xl sm:space-y-4 sm:px-5 sm:pb-5 sm:pt-4">
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
            <p className="mb-0.5 truncate text-[8px] font-bold uppercase tracking-wide text-primary sm:mb-1 sm:text-[9px]">
              Ekosistem UMKM
            </p>
            <h1 className="truncate font-heading text-base font-bold leading-none text-foreground sm:text-lg">
              {settings.siteName}
            </h1>
          </div>
        </Link>
        
         <div className="flex shrink-0 items-center gap-0.5 sm:gap-1">
          <InstallButton />
          <button
            onClick={handleChatNavigation}
             className="relative flex h-9 w-9 items-center justify-center rounded-xl text-muted-foreground transition hover:bg-secondary hover:text-primary sm:h-10 sm:w-10"
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
          </button>
          <button
            onClick={() => navigate('/cart')}
             className="relative flex h-9 w-9 items-center justify-center rounded-xl text-muted-foreground transition hover:bg-secondary hover:text-primary sm:h-10 sm:w-10"
            aria-label="Keranjang"
          >
            <ShoppingCart className="h-[18px] w-[18px] text-muted-foreground" />
            {cartCount > 0 && (
              <span className="absolute top-1 right-1 w-4 h-4 bg-primary rounded-full text-[8px] flex items-center justify-center text-primary-foreground font-bold">
                {cartCount > 9 ? '9+' : cartCount}
              </span>
            )}
          </button>
          <LanguageSwitcher />
          <NotificationDropdown />
        </div>
      </div>

      {/* Search Bar - Main pages */}
      {showSearchBar && (
        <form onSubmit={handleSearch} className="group relative">
          <Search className="absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground transition-colors group-focus-within:text-primary" />
           <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Cari hasil desa terbaik..."
            aria-label="Cari hasil desa terbaik"
            className="h-12 w-full rounded-2xl border border-transparent bg-secondary pl-12 pr-4 text-sm outline-none transition placeholder:text-muted-foreground focus:border-primary/30 focus:bg-card focus:ring-2 focus:ring-primary/10"
          />
        </form>
      )}
    </header>
  );
}
