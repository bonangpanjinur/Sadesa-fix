import React, { useEffect, useRef, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { Home, Receipt, User, Search } from 'lucide-react';
import { useCart } from '@/contexts/CartContext';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { cn } from '@/lib/utils';
import { useChatUnread } from '@/hooks/useChatUnread';
import { FloatingCartButton } from './FloatingCartButton';

const navItems = [
  { path: '/', icon: Home, label: 'Beranda' },
  { path: '/products', icon: Search, label: 'Jelajah' },
  { path: '/orders', icon: Receipt, label: 'Pesanan' },
  { path: '/account', icon: User, label: 'Akun' },
];

export const BottomNav = React.forwardRef<HTMLElement, React.HTMLAttributes<HTMLElement>>(function BottomNav(_props, ref) {
  const location = useLocation();
  const { getItemCount } = useCart();
  const { user } = useAuth();
  const itemCount = getItemCount();
  const { unreadCount: chatUnread, realtimeStatus: chatRealtimeStatus } = useChatUnread();
  const [unreadCount, setUnreadCount] = useState(0);
  const [activeOrders, setActiveOrders] = useState(0);
  const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null);

  useEffect(() => {
    if (!user) {
      setUnreadCount(0);
      setActiveOrders(0);
      return;
    }

    const fetchBadges = async () => {
      const [notifRes, ordersRes] = await Promise.all([
        supabase
          .from('notifications')
          .select('*', { count: 'exact', head: true })
          .eq('user_id', user.id)
          .eq('is_read', false),
        supabase
          .from('orders')
          .select('*', { count: 'exact', head: true })
          .eq('buyer_id', user.id)
          .in('status', ['NEW', 'PENDING_PAYMENT', 'PENDING_CONFIRMATION', 'PROCESSED', 'ASSIGNED', 'PICKED_UP', 'DELIVERING', 'SENT', 'DELIVERED']),
      ]);
      setUnreadCount(notifRes.count || 0);
      setActiveOrders(ordersRes.count || 0);
    };

    fetchBadges();

    // P1.2: Real-time badge via SSE — subscribe ke notifications table
    // Tidak perlu polling 30s lagi — update instan saat notif masuk
    const channel = supabase
      .channel(`bottomnav-notif-${user.id}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'notifications', filter: `user_id=eq.${user.id}` },
        () => {
          setUnreadCount((prev) => prev + 1);
        }
      )
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'notifications', filter: `user_id=eq.${user.id}` },
        () => {
          // Tandai baca → refresh counter
          supabase
            .from('notifications')
            .select('*', { count: 'exact', head: true })
            .eq('user_id', user.id)
            .eq('is_read', false)
            .then(({ count }) => setUnreadCount(count || 0));
        }
      )
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'orders', filter: `buyer_id=eq.${user.id}` },
        (payload) => {
          const updatedOrder = payload.new as { status?: string };
          const activeStatuses = ['NEW', 'PENDING_PAYMENT', 'PENDING_CONFIRMATION', 'PROCESSED', 'ASSIGNED', 'PICKED_UP', 'DELIVERING', 'SENT', 'DELIVERED'];
          if (activeStatuses.includes(updatedOrder.status)) {
            fetchBadges();
          } else {
            setActiveOrders((prev) => Math.max(0, prev - 1));
          }
        }
      )
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'orders', filter: `buyer_id=eq.${user.id}` },
        () => {
          setActiveOrders((prev) => prev + 1);
        }
      )
      .subscribe();

    channelRef.current = channel;

    return () => {
      if (channelRef.current) {
        supabase.removeChannel(channelRef.current);
        channelRef.current = null;
      }
    };
  }, [user]);

  const getBadgeCount = (path: string) => {
    if (path === '/orders') return activeOrders;
    if (path === '/account') return unreadCount + chatUnread;
    return 0;
  };

  return (
    <>
      <FloatingCartButton />
      <nav ref={ref} aria-label="Navigasi utama" className="safe-area-bottom fixed bottom-0 left-0 right-0 z-30 mx-auto flex max-w-[480px] justify-around rounded-t-[1.25rem] border border-b-0 border-slate-100 bg-white/95 px-2 py-1.5 shadow-[0_12px_30px_-14px_rgba(20,45,35,0.28)] backdrop-blur-xl sm:bottom-3 sm:left-3 sm:right-3 sm:rounded-[1.25rem] sm:border-b">
        {navItems.map(({ path, icon: Icon, label }) => {
        const isActive = location.pathname === path;
        const badgeCount = getBadgeCount(path);

        return (
          <Link
            key={path}
            to={path}
            className={cn(
              'group relative flex min-w-0 flex-1 items-center justify-center gap-1.5 rounded-[0.8rem] px-1.5 py-2 transition-all duration-200',
              'text-[10px] font-medium whitespace-nowrap',
              isActive
                ? 'bg-[#eaf5e1] text-[#015730] shadow-sm ring-1 ring-[#cfe5c1]'
                : 'text-slate-500 hover:bg-[#f0f8e9] hover:text-[#015730]'
            )}
            aria-current={isActive ? 'page' : undefined}
          >
            <div className={cn(
              'pointer-events-none absolute -top-1 left-1/2 h-1 -translate-x-1/2 rounded-full bg-[#44a31b] transition-all duration-300',
              isActive ? 'w-7 opacity-100' : 'w-0 opacity-0'
            )} />
            <span className={cn(
              'flex h-5 w-5 shrink-0 items-center justify-center rounded-md transition-all duration-200',
              isActive ? 'bg-white/90' : 'group-hover:bg-[#e0f0d5]'
            )}>
              <Icon className={cn(
                'h-4 w-4 stroke-[2.15] transition-transform duration-200',
                isActive && 'scale-110'
              )} />
            </span>
            <span className={cn('leading-tight', isActive && 'font-semibold')}>{label}</span>
            {badgeCount > 0 && (
              <span className="absolute right-1 top-0 flex h-4 min-w-4 items-center justify-center rounded-full bg-[#E31019] px-1 text-[8px] font-bold text-white shadow-sm">
                {badgeCount > 9 ? '9+' : badgeCount}
              </span>
            )}
          </Link>
        );
        })}
      </nav>
    </>
  );
});
BottomNav.displayName = 'BottomNav';
