import { useState, useEffect, useCallback } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Bell, CheckCheck, Heart, Package, Wallet, ShieldCheck, Info, AlertTriangle, XCircle, CheckCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
  DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu';
import { ScrollArea } from '@/components/ui/scroll-area';
import { cn } from '@/lib/utils';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { formatDistanceToNow } from 'date-fns';
import { id } from 'date-fns/locale';
import { resolveNotificationLink } from '@/lib/notificationRouting';
import { playOrderNotificationSound } from '@/lib/orderNotificationSound';

interface Notification {
  id: string;
  title: string;
  message: string;
  type: string;
  link: string | null;
  deep_link?: string | null;
  conversation_id?: string | null;
  message_id?: string | null;
  is_read: boolean;
  created_at: string;
  data?: unknown;
}

export function NotificationDropdown() {
  const { user, roles } = useAuth();
  const userId = user?.id;
  const navigate = useNavigate();
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const [open, setOpen] = useState(false);

  const refreshNotifications = useCallback(async () => {
    if (!userId) return;
    const { data, error } = await supabase
      .from('notifications')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(20);
    if (error) {
      console.error('[notifications] refresh failed', {
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
        userId,
      });
      return;
    }
    setNotifications(data || []);
    setUnreadCount((data || []).filter(n => !n.is_read).length);
  }, [userId]);

  useEffect(() => {
    if (!userId) return;

    const fetchNotifications = async () => {
      const { data, error } = await supabase
        .from('notifications')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', { ascending: false })
        .limit(20);

      if (error) {
        console.error('[notifications] fetch failed', {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          userId,
        });
        return;
      }

      if (data) {
        setNotifications(data);
        setUnreadCount(data.filter(n => !n.is_read).length);
      }
    };

    fetchNotifications();

    let disposed = false;
    let retryTimer: number | undefined;
    let retryAttempt = 0;
    let channel: ReturnType<typeof supabase.channel> | null = null;

    const subscribe = () => {
      if (disposed) return;
      // Never reuse a fixed channel name. Multiple layouts can mount this
      // component at once; Supabase closes the older channel on a collision.
      const channelName = `notifications-${userId}-${Math.random().toString(36).slice(2)}`;
      const nextChannel = supabase
        .channel(channelName)
        .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'notifications', filter: `user_id=eq.${userId}` },
          (payload) => {
            const n = payload.new as Notification;
            setNotifications(prev => {
              if (prev.some(item => item.id === n.id)) return prev;
              const next = [n, ...prev].slice(0, 20);
              setUnreadCount(next.filter(item => !item.is_read).length);
              return next;
            });
            // Ride requests are inserted by the database trigger. This is the
            // actual event that the driver sees in the bell, so ring here too.
            if (n.type === 'ride' || /ojek/i.test(n.title || '') || /ojek/i.test(n.message || '')) {
              void playOrderNotificationSound('courier');
            }
          }
        )
        .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'notifications', filter: `user_id=eq.${userId}` },
          (payload) => {
            const updated = payload.new as Notification;
            setNotifications(prev => {
              const next = prev.map(n => (n.id === updated.id ? updated : n));
              setUnreadCount(next.filter(n => !n.is_read).length);
              return next;
            });
          }
        )
        .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'chat_messages', filter: `receiver_id=eq.${userId}` }, () => {
          void refreshNotifications();
        });
      channel = nextChannel;

      nextChannel.subscribe((status, error) => {
        if (disposed || channel !== nextChannel) return;
        if (status === 'SUBSCRIBED') {
          if (retryTimer !== undefined) window.clearTimeout(retryTimer);
          retryTimer = undefined;
          retryAttempt = 0;
          return;
        }
        console.warn('[notifications] realtime status', { channelName, status, error: error?.message });
        if ((status === 'CLOSED' || status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') && retryTimer === undefined) {
          const retryDelayMs = Math.min(2000 * 2 ** retryAttempt, 30_000);
          retryAttempt += 1;
          retryTimer = window.setTimeout(() => {
            retryTimer = undefined;
            if (disposed || channel !== nextChannel) return;
            channel = null;
            void supabase.removeChannel(nextChannel);
            subscribe();
          }, retryDelayMs);
        }
      });
    };

    subscribe();
    return () => {
      disposed = true;
      if (retryTimer) window.clearTimeout(retryTimer);
      retryTimer = undefined;
      if (channel) void supabase.removeChannel(channel);
    };
  }, [userId, refreshNotifications]);

  // Realtime can be delayed or unavailable on some browsers/proxies. Refresh
  // when the dropdown opens and periodically while the user is signed in so a
  // missed INSERT event cannot hide a new chat notification.
  useEffect(() => {
    if (!userId || !open) return;
    void refreshNotifications();
    const timer = window.setInterval(() => void refreshNotifications(), 15000);
    return () => window.clearInterval(timer);
  }, [open, userId, refreshNotifications]);

  const markAsRead = async (notifId: string) => {
    await supabase.from('notifications').update({ is_read: true, read_at: new Date().toISOString() }).eq('id', notifId);
    setNotifications(prev => prev.map(n => (n.id === notifId ? { ...n, is_read: true } : n)));
    setUnreadCount(prev => Math.max(0, prev - 1));
  };

  const markAllAsRead = async () => {
    if (!user) return;
    await supabase.from('notifications').update({ is_read: true, read_at: new Date().toISOString() }).eq('user_id', user.id).eq('is_read', false);
    setNotifications(prev => prev.map(n => ({ ...n, is_read: true })));
    setUnreadCount(0);
  };

  const getIcon = (type: string) => {
    switch (type) {
      case 'order': return <Package className="h-4 w-4 text-primary" />;
      case 'favorite': return <Heart className="h-4 w-4 text-destructive" />;
      case 'withdrawal': return <Wallet className="h-4 w-4 text-amber-500" />;
      case 'verification': return <ShieldCheck className="h-4 w-4 text-blue-500" />;
      case 'success': return <CheckCircle className="h-4 w-4 text-green-500" />;
      case 'warning': return <AlertTriangle className="h-4 w-4 text-amber-500" />;
      case 'error': return <XCircle className="h-4 w-4 text-destructive" />;
      default: return <Info className="h-4 w-4 text-muted-foreground" />;
    }
  };

  const handleNotificationClick = (notification: Notification) => {
    if (!notification.is_read) markAsRead(notification.id);
    if (notification.link || notification.deep_link || notification.type === 'chat' || notification.conversation_id || notification.data) {
      setOpen(false);
      const dynamicLink = resolveNotificationLink(notification, roles);
      navigate(dynamicLink);
    }
  };

  if (!user) return null;

  return (
    <DropdownMenu open={open} onOpenChange={setOpen}>
      <DropdownMenuTrigger asChild>
        <button className="relative cursor-pointer hover:scale-105 transition" aria-label="Notifications">
          <div className="w-8 h-8 bg-secondary rounded-full flex items-center justify-center text-secondary-foreground border border-border">
            <Bell className="h-4 w-4" />
          </div>
          {unreadCount > 0 && (
            <span className="absolute -top-1 -right-1 w-4 h-4 bg-destructive rounded-full border-2 border-card text-[8px] flex items-center justify-center text-destructive-foreground font-bold">
              {unreadCount > 9 ? '9+' : unreadCount}
            </span>
          )}
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="z-[2000] w-80 border border-border bg-popover shadow-xl">
        <div className="flex items-center justify-between px-3 py-2 border-b border-border">
          <span className="font-semibold text-sm">Notifikasi</span>
          {unreadCount > 0 && (
            <Button variant="ghost" size="sm" className="h-7 text-xs" onClick={markAllAsRead}>
              <CheckCheck className="h-3 w-3 mr-1" /> Tandai Semua
            </Button>
          )}
        </div>
        <ScrollArea className="h-[300px]">
          {notifications.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-8 text-muted-foreground">
              <Bell className="h-8 w-8 mb-2 opacity-50" />
              <p className="text-sm">Belum ada notifikasi</p>
            </div>
          ) : (
            notifications.map((notification) => (
              <DropdownMenuItem
                key={notification.id}
                className={cn('flex items-start gap-3 p-3 cursor-pointer', !notification.is_read && 'bg-primary/5')}
                onClick={() => handleNotificationClick(notification)}
              >
                <div className="mt-0.5">{getIcon(notification.type)}</div>
                <div className="flex-1 min-w-0">
                  <p className={cn('text-sm truncate', !notification.is_read && 'font-semibold')}>{notification.title}</p>
                  <p className="text-xs text-muted-foreground line-clamp-2">{notification.message}</p>
                  <p className="text-[10px] text-muted-foreground mt-1">
                    {formatDistanceToNow(new Date(notification.created_at), { addSuffix: true, locale: id })}
                  </p>
                </div>
                {!notification.is_read && <div className="w-2 h-2 bg-primary rounded-full mt-1.5" />}
              </DropdownMenuItem>
            ))
          )}
        </ScrollArea>
        {notifications.length > 0 && (
          <>
            <DropdownMenuSeparator />
            <div className="p-2">
              <Link to="/notifications" className="block text-center text-xs text-primary hover:underline" onClick={() => setOpen(false)}>
                Lihat Semua Notifikasi
              </Link>
            </div>
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
