import React, { useEffect, useRef, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { Home, Compass, Receipt, User, Store } from 'lucide-react';
import { useCart } from '@/contexts/CartContext';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { cn } from '@/lib/utils';
import { useChatUnread } from '@/hooks/useChatUnread';

const navItems = [
  { path: '/', icon: Home, label: 'Beranda' },
  { path: '/explore', icon: Compass, label: 'Jelajah' },
  { path: '/shops', icon: Store, label: 'Toko' },
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
    <nav ref={ref} className="fixed bottom-3 left-3 right-3 z-30 mx-auto flex max-w-[456px] justify-around rounded-lg border border-border/70 bg-card/95 px-2 py-2 shadow-lg backdrop-blur-xl">
      {navItems.map(({ path, icon: Icon, label }) => {
        const isActive = location.pathname === path;
        const badgeCount = getBadgeCount(path);

        return (
          <Link
            key={path}
            to={path}
            className={cn(
              'relative flex min-w-12 flex-col items-center rounded-md px-2 py-1 transition-all',
              'text-[10px] font-medium',
              isActive ? 'bg-primary/10 text-primary' : 'text-muted-foreground hover:bg-secondary hover:text-primary'
            )}
          >
            <div className={cn(
              'absolute -top-2 left-1/2 h-[3px] -translate-x-1/2 rounded-full transition-all duration-300',
              isActive ? 'w-5 bg-primary' : 'w-0 bg-transparent'
            )} />
            <Icon className={cn(
              "h-5 w-5 mb-0.5 transition-transform duration-200",
              isActive && "scale-110"
            )} />
            <span className={cn(isActive && "font-semibold")}>{label}</span>
            {badgeCount > 0 && (
              <span className="absolute -top-0 right-1 w-4 h-4 bg-destructive rounded-full text-[8px] flex items-center justify-center text-destructive-foreground font-bold">
                {badgeCount > 9 ? '9+' : badgeCount}
              </span>
            )}
          </Link>
        );
      })}
    </nav>
  );
});
BottomNav.displayName = 'BottomNav';
