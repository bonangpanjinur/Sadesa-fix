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
    <nav ref={ref} className="fixed bottom-3 left-3 right-3 z-30 mx-auto flex max-w-[456px] justify-around rounded-[1.25rem] border border-white/80 bg-card/95 p-1.5 shadow-[0_10px_30px_-12px_hsl(var(--foreground)/0.35)] backdrop-blur-xl">
      {navItems.map(({ path, icon: Icon, label }) => {
        const isActive = location.pathname === path;
        const badgeCount = getBadgeCount(path);

        return (
          <Link
            key={path}
            to={path}
            className={cn(
              'group relative flex min-w-12 flex-1 flex-col items-center gap-0.5 rounded-[0.9rem] px-1 py-1.5 transition-all duration-200',
              'text-[10px] font-medium',
              isActive
                ? 'bg-primary/10 text-primary shadow-sm ring-1 ring-primary/10'
                : 'text-muted-foreground hover:bg-secondary/70 hover:text-primary'
            )}
            aria-current={isActive ? 'page' : undefined}
          >
            <div className={cn(
              'pointer-events-none absolute -top-1 left-1/2 h-0.5 -translate-x-1/2 rounded-full bg-primary transition-all duration-300',
              isActive ? 'w-7 opacity-100' : 'w-0 opacity-0'
            )} />
            <span className={cn(
              'flex h-7 w-11 items-center justify-center rounded-xl transition-all duration-200',
              isActive ? 'bg-primary/10' : 'group-hover:bg-secondary'
            )}>
              <Icon className={cn(
                'h-[1.3rem] w-[1.3rem] stroke-[2.15] transition-transform duration-200',
                isActive && 'scale-110'
              )} />
            </span>
            <span className={cn('leading-tight', isActive && 'font-semibold')}>{label}</span>
            {badgeCount > 0 && (
              <span className="absolute right-1 top-0 flex h-4 min-w-4 items-center justify-center rounded-full bg-destructive px-1 text-[8px] font-bold text-destructive-foreground shadow-sm">
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
