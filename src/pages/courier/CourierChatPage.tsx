import { useCallback, useEffect, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { OrderChat, ChatType } from '@/components/chat/OrderChat';
import { CourierLayout } from '@/components/courier/CourierLayout';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { MessageCircle, User, Store, ShoppingBag } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';
import { id as idLocale } from 'date-fns/locale';
import { useSearchParams } from 'react-router-dom';

interface ChatThread {
  orderId: string;
  conversationId: string | null;
  otherUserId: string;
  otherUserName: string;
  lastMessage: string;
  lastMessageAt: string;
  unreadCount: number;
  chatType: ChatType;
  productName?: string;
  productImage?: string | null;
}

export default function CourierChatPage() {
  const { user } = useAuth();
  const [searchParams] = useSearchParams();
  const [threads, setThreads] = useState<ChatThread[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'all' | 'buyer_courier' | 'merchant_courier'>('all');
  const [selectedThread, setSelectedThread] = useState<ChatThread | null>(null);

  const fetchThreads = useCallback(async () => {
    if (!user) return;
    try {
      const { data: memberships, error: membershipError } = await supabase
        .from('chat_participants')
        .select('conversation_id, last_read_at, role')
        .eq('user_id', user.id)
        .eq('role', 'courier')
        .is('left_at', null);
      if (membershipError) throw membershipError;
      const conversationIds = [...new Set((memberships || []).map((row) => row.conversation_id))];
      const lastReadAtByConversation = new Map(
        (memberships || []).map((row) => [row.conversation_id, row.last_read_at ? new Date(row.last_read_at).getTime() : 0]),
      );
      if (conversationIds.length === 0) { setThreads([]); setLoading(false); return; }
      const { data: messages } = await supabase
        .from('chat_messages')
        .select('*')
        .in('conversation_id', conversationIds)
        .is('deleted_at', null)
        .in('chat_type', ['buyer_courier', 'merchant_courier'])
        .order('created_at', { ascending: false })
        .limit(500);

      if (!messages || messages.length === 0) { setThreads([]); setLoading(false); return; }

      const threadMap = new Map<string, ChatThread>();
      for (const msg of messages) {
        const key = msg.conversation_id || `${msg.order_id}-${msg.chat_type}`;
        if (!threadMap.has(key)) {
          const otherUserId = msg.sender_id === user.id ? msg.receiver_id : msg.sender_id;
          threadMap.set(key, {
            orderId: msg.order_id,
            conversationId: msg.conversation_id || null,
            otherUserId,
            otherUserName: '',
            lastMessage: msg.message,
            lastMessageAt: msg.created_at,
            unreadCount: 0,
            chatType: (msg.chat_type || 'buyer_courier') as ChatType,
          });
        }
        const lastReadAt = msg.conversation_id ? lastReadAtByConversation.get(msg.conversation_id) || 0 : 0;
        if (msg.receiver_id === user.id && (
          msg.conversation_id ? new Date(msg.created_at).getTime() > lastReadAt : !msg.is_read
        )) {
          threadMap.get(key)!.unreadCount++;
        }
      }

      const otherParticipants = await supabase
        .from('chat_participants')
        .select('conversation_id, user_id')
        .in('conversation_id', conversationIds)
        .neq('user_id', user.id)
        .is('left_at', null);
      const otherUserByConversation = new Map(
        (otherParticipants.data || []).map((row) => [row.conversation_id, row.user_id]),
      );
      for (const thread of threadMap.values()) {
        if (thread.conversationId) thread.otherUserId = otherUserByConversation.get(thread.conversationId) || thread.otherUserId;
      }

      const userIds = [...new Set([...threadMap.values()].map(t => t.otherUserId))];
      const [{ data: profiles }, { data: merchants }, { data: couriers }] = await Promise.all([
        supabase.from('profiles').select('user_id, full_name').in('user_id', userIds),
        supabase.from('merchants').select('user_id, name').in('user_id', userIds),
        supabase.from('couriers').select('user_id, name').in('user_id', userIds),
      ]);

      for (const thread of threadMap.values()) {
        const profile = (profiles || []).find(p => p.user_id === thread.otherUserId);
        const merchant = (merchants || []).find(m => m.user_id === thread.otherUserId);
        const courier = (couriers || []).find(c => c.user_id === thread.otherUserId);
        thread.otherUserName = profile?.full_name || merchant?.name || courier?.name || (thread.chatType === 'merchant_courier' ? 'Penjual' : 'Pembeli');
      }

      // Fetch order items for product info
      const orderIds = [...new Set([...threadMap.values()].map(t => t.orderId))];
      if (orderIds.length > 0) {
        const { data: orderItems } = await supabase
          .from('order_items')
          .select('order_id, product_name, product_id')
          .in('order_id', orderIds);

        const productIds = [...new Set((orderItems || []).map(i => i.product_id).filter(Boolean))] as string[];
        let imageMap: Record<string, string | null> = {};
        if (productIds.length > 0) {
          const { data: products } = await supabase
            .from('products')
            .select('id, image_url')
            .in('id', productIds);
          if (products) {
            imageMap = Object.fromEntries(products.map(p => [p.id, p.image_url]));
          }
        }

        for (const thread of threadMap.values()) {
          const firstItem = (orderItems || []).find(i => i.order_id === thread.orderId);
          if (firstItem) {
            thread.productName = firstItem.product_name;
            thread.productImage = firstItem.product_id ? (imageMap[firstItem.product_id] || null) : null;
          }
        }
      }

      setThreads(Array.from(threadMap.values()));
    } catch (error) {
      console.error('Error fetching threads:', error);
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    if (!user) return;
    fetchThreads();

    const channel = supabase
      .channel(`courier-chats-${user.id}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'chat_messages', filter: `receiver_id=eq.${user.id}` }, fetchThreads)
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [user, fetchThreads]);

  useEffect(() => {
    const conversationId = searchParams.get('conversationId');
    const orderId = searchParams.get('orderId');
    if ((!conversationId && !orderId) || selectedThread || threads.length === 0) return;
    const match = threads.find((thread) => conversationId
      ? thread.conversationId === conversationId
      : thread.orderId === orderId);
    if (match) setSelectedThread(match);
  }, [searchParams, selectedThread, threads]);

  const filteredThreads = activeTab === 'all' ? threads : threads.filter(t => t.chatType === activeTab);

  return (
    <CourierLayout title="Chat" subtitle="Percakapan dengan pembeli & penjual">
      <Tabs
        defaultValue="all"
        onValueChange={(value) => {
          if (value === 'all' || value === 'buyer_courier' || value === 'merchant_courier') setActiveTab(value);
        }}
      >
        <div className="mb-4 rounded-xl bg-card p-1.5 shadow-sm">
          <TabsList className="grid h-auto w-full grid-cols-3 gap-1 bg-transparent p-0">
            <TabsTrigger value="all" className="min-h-11 rounded-lg text-xs data-[state=active]:bg-primary data-[state=active]:text-primary-foreground">Semua</TabsTrigger>
            <TabsTrigger value="buyer_courier" className="min-h-11 rounded-lg text-xs data-[state=active]:bg-primary data-[state=active]:text-primary-foreground">
              <User className="h-3 w-3 mr-1" /> Pembeli
            </TabsTrigger>
            <TabsTrigger value="merchant_courier" className="min-h-11 rounded-lg text-xs data-[state=active]:bg-primary data-[state=active]:text-primary-foreground">
              <Store className="h-3 w-3 mr-1" /> Penjual
            </TabsTrigger>
          </TabsList>
        </div>
      </Tabs>

      {loading ? (
        <div className="flex items-center justify-center py-20">
          <div className="animate-spin rounded-full h-10 w-10 border-2 border-primary border-t-transparent" />
        </div>
      ) : filteredThreads.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <MessageCircle className="h-16 w-16 text-muted-foreground/30 mb-4" />
          <p className="text-muted-foreground">Belum ada percakapan</p>
          <p className="text-xs text-muted-foreground mt-1">Chat akan muncul saat ada pesanan aktif</p>
        </div>
      ) : (
        <div className="space-y-2">
          {filteredThreads.map(thread => (
            <Card key={`${thread.orderId}-${thread.chatType}`} className="cursor-pointer hover:bg-accent/50 transition" onClick={() => setSelectedThread(thread)}>
              <CardContent className="flex min-h-[76px] items-center gap-3 p-3 sm:p-4">
                <div className="w-10 h-10 rounded-lg bg-muted overflow-hidden flex-shrink-0">
                  {thread.productImage ? (
                    <img src={thread.productImage} alt={thread.productName || ''} className="w-full h-full object-cover" />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center">
                      <ShoppingBag className="h-5 w-5 text-muted-foreground" />
                    </div>
                  )}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-medium text-sm truncate">{thread.otherUserName}</span>
                    {thread.unreadCount > 0 && (
                      <Badge variant="destructive" className="text-[10px] px-1.5 py-0">{thread.unreadCount}</Badge>
                    )}
                  </div>
                  {thread.productName && (
                    <p className="text-[11px] text-primary/80 truncate">{thread.productName}</p>
                  )}
                  <p className="text-xs text-muted-foreground truncate">{thread.lastMessage}</p>
                </div>
                <p className="hidden shrink-0 text-[10px] text-muted-foreground sm:block">
                  {formatDistanceToNow(new Date(thread.lastMessageAt), { locale: idLocale, addSuffix: true })}
                </p>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {selectedThread && (
        <OrderChat
          orderId={selectedThread.orderId}
          conversationId={selectedThread.conversationId || undefined}
          otherUserId={selectedThread.otherUserId}
          otherUserName={selectedThread.otherUserName}
          chatType={selectedThread.chatType}
          isOpen={!!selectedThread}
          onClose={() => setSelectedThread(null)}
        />
      )}
    </CourierLayout>
  );
}
