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
      <nav ref={ref} aria-label="Navigasi utama" className="safe-area-bottom fixed bottom-3 left-3 right-3 z-30 mx-auto flex max-w-[480px] gap-1 rounded-[1.75rem] border border-white/80 bg-white/90 px-2 pt-2 shadow-[0_18px_45px_-18px_rgba(20,45,35,0.38)] backdrop-blur-2xl">
        {navItems.map(({ path, icon: Icon, label }) => {
        const isActive = location.pathname === path;
        const badgeCount = getBadgeCount(path);

        return (
          <Link
            key={path}
            to={path}
            state={path === '/' ? { skipRoleRedirect: true } : undefined}
            className={cn(
              'group relative flex min-w-12 flex-1 flex-col items-center gap-0.5 rounded-[1.25rem] px-1 py-1.5 transition-all duration-200',
              'text-[10px] font-medium',
              isActive
                ? 'bg-[#edf7e8] text-[#015730]'
                : 'text-slate-500 hover:bg-[#f5faf2] hover:text-[#015730]'
            )}
            aria-current={isActive ? 'page' : undefined}
          >
            <span className={cn(
              'flex h-7 w-10 items-center justify-center rounded-xl transition-all duration-200',
              isActive ? 'bg-white shadow-sm' : 'group-hover:bg-[#e8f4df]'
            )}>
              <Icon className={cn(
                'h-[1.05rem] w-[1.05rem] stroke-[2] transition-transform duration-200',
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
