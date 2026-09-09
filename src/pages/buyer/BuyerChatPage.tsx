import { useCallback, useEffect, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { OrderChat, ChatType } from '@/components/chat/OrderChat';
import { BottomNav } from '@/components/layout/BottomNav';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { MessageCircle, Store, Truck, ArrowLeft, ShoppingBag, WifiOff } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { formatDistanceToNow } from 'date-fns';
import { id as idLocale } from 'date-fns/locale';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { safeGoBack } from '@/lib/utils';
import { logRealtimeStatus, isRealtimeFailure, type RealtimeStatus } from '@/lib/realtimeTelemetry';

interface ChatThread {
  orderId: string | null;
  merchantId: string | null;
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

export default function BuyerChatPage() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [threads, setThreads] = useState<ChatThread[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'all' | 'buyer_merchant' | 'buyer_courier'>('all');
  const [selectedThread, setSelectedThread] = useState<ChatThread | null>(null);
  const [realtimeStatus, setRealtimeStatus] = useState<RealtimeStatus>('idle');

  const fetchThreads = useCallback(async () => {
    if (!user) return;
    try {
      const { data: memberships } = await supabase
        .from('chat_participants')
        .select('conversation_id, last_read_at, role')
        .eq('user_id', user.id)
        .eq('role', 'buyer')
        .is('left_at', null);
      const lastReadAtByConversation = new Map(
        (memberships || []).map((row) => [row.conversation_id, row.last_read_at ? new Date(row.last_read_at).getTime() : 0]),
      );
      const buyerConversationIds = [...new Set((memberships || []).map((row) => row.conversation_id))];
      if (buyerConversationIds.length === 0) { setThreads([]); setLoading(false); return; }
      const { data: messages } = await supabase
        .from('chat_messages')
        .select('*')
        .in('conversation_id', buyerConversationIds)
        .is('deleted_at', null)
        .in('chat_type', ['buyer_merchant', 'buyer_courier'])
        .order('created_at', { ascending: false });

      if (!messages || messages.length === 0) { setThreads([]); setLoading(false); return; }

      const threadMap = new Map<string, ChatThread>();
      for (const msg of messages) {
        const key = msg.conversation_id || `${msg.order_id}-${msg.chat_type}`;
        if (!threadMap.has(key)) {
          const otherUserId = msg.sender_id === user.id ? msg.receiver_id : msg.sender_id;
          threadMap.set(key, {
            orderId: msg.order_id,
            merchantId: null,
            conversationId: msg.conversation_id,
            otherUserId,
            otherUserName: '',
            lastMessage: msg.message,
            lastMessageAt: msg.created_at,
            unreadCount: 0,
            chatType: (msg.chat_type || 'buyer_merchant') as ChatType,
          });
        }
        const lastReadAt = msg.conversation_id ? lastReadAtByConversation.get(msg.conversation_id) || 0 : 0;
        if (msg.receiver_id === user.id && (
          msg.conversation_id ? new Date(msg.created_at).getTime() > lastReadAt : !msg.is_read
        )) {
          threadMap.get(key)!.unreadCount++;
        }
      }

      const directConversationIds = [...threadMap.values()]
        .map((thread) => thread.conversationId)
        .filter((conversationId): conversationId is string => Boolean(conversationId));
      const merchantIds = new Set<string>();
      if (directConversationIds.length > 0) {
        const { data: conversations } = await supabase
          .from('chat_conversations')
          .select('id, merchant_id')
          .in('id', directConversationIds);
        const merchantByConversation = new Map(
          (conversations || []).map((conversation) => [conversation.id, conversation.merchant_id]),
        );
        for (const thread of threadMap.values()) {
          if (thread.conversationId) {
            const merchantId = merchantByConversation.get(thread.conversationId) || null;
            thread.merchantId = merchantId;
            if (merchantId) merchantIds.add(merchantId);
          }
        }
      }

      // Fetch names
      const userIds = [...new Set([...threadMap.values()].map(t => t.otherUserId))];
      const [{ data: profiles }, { data: merchantsByUser }, { data: merchantsById }, { data: couriers }] = await Promise.all([
        supabase.from('profiles').select('user_id, full_name').in('user_id', userIds),
        supabase.from('merchants').select('id, user_id, name').in('user_id', userIds),
        merchantIds.size > 0
          ? supabase.from('merchants').select('id, user_id, name').in('id', [...merchantIds])
          : Promise.resolve({ data: [] }),
        supabase.from('couriers').select('user_id, name').in('user_id', userIds),
      ]);

      for (const thread of threadMap.values()) {
        const profile = (profiles || []).find(p => p.user_id === thread.otherUserId);
        const merchant = [...(merchantsByUser || []), ...(merchantsById || [])]
          .find(m => m.user_id === thread.otherUserId || m.id === thread.merchantId);
        const courier = (couriers || []).find(c => c.user_id === thread.otherUserId);
        // Buyer-facing chat identifies a merchant by the store name, never by
        // the owner's profile/account name.
        thread.otherUserName = thread.chatType === 'buyer_merchant'
          ? merchant?.name?.trim() || profile?.full_name?.trim() || 'Penjual'
          : profile?.full_name?.trim() || courier?.name?.trim() || 'Kurir';
      }

      // Fetch order items for product info
      const orderIds = [...new Set([...threadMap.values()].map(t => t.orderId).filter(Boolean))] as string[];
      if (orderIds.length > 0) {
        const { data: orderItems } = await supabase
          .from('order_items')
          .select('order_id, product_name, product_id')
          .in('order_id', orderIds);

        // Get product images
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

        // Assign first item info to each thread
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

    let active = true;
    const channelName = `buyer-chats-${user.id}-${Math.random().toString(36).slice(2)}`;
    const channel = supabase
      .channel(channelName)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'chat_messages' }, () => {
        if (active) fetchThreads();
      });

    channel.subscribe((status, err) => {
      const normalized = logRealtimeStatus(channelName, status, err);
      if (active) setRealtimeStatus(normalized);
    });

    return () => {
      active = false;
      try { channel.unsubscribe(); } catch { /* noop */ }
      supabase.removeChannel(channel);
    };
  }, [user, fetchThreads]);

  useEffect(() => {
    const conversationId = searchParams.get('conversationId');
    if (!conversationId || selectedThread || threads.length === 0) return;
    const match = threads.find((thread) => thread.conversationId === conversationId);
    if (match) setSelectedThread(match);
  }, [searchParams, selectedThread, threads]);

  const filtered = activeTab === 'all' ? threads : threads.filter(t => t.chatType === activeTab);

  return (
    <div className="min-h-screen bg-background pb-20">
      <div className="bg-primary px-5 pt-12 pb-6">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" className="text-primary-foreground" onClick={() => safeGoBack(navigate)}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <h1 className="text-xl font-bold text-primary-foreground">Chat Saya</h1>
        </div>
      </div>

      <div className="container max-w-md mx-auto px-4 -mt-3">
        {isRealtimeFailure(realtimeStatus) && (
          <div className="mb-3 flex items-start gap-2 rounded-xl border border-destructive/30 bg-destructive/10 p-3">
            <WifiOff className="h-4 w-4 text-destructive mt-0.5 flex-shrink-0" />
            <div className="text-xs">
              <p className="font-medium text-destructive">Chat realtime terputus ({realtimeStatus})</p>
              <p className="text-muted-foreground">Pesan baru mungkin tertunda. Detail penyebab tercatat di console browser.</p>
            </div>
            <Button size="sm" variant="outline" className="ml-auto text-xs h-7" onClick={() => window.location.reload()}>
              Coba lagi
            </Button>
          </div>
        )}
        <Tabs
          defaultValue="all"
          onValueChange={(value) => {
            if (value === 'all' || value === 'buyer_merchant' || value === 'buyer_courier') setActiveTab(value);
          }}
        >
          <div className="bg-card rounded-xl shadow-sm p-1.5 mb-4">
            <TabsList className="w-full bg-transparent h-auto p-0 gap-1">
              <TabsTrigger value="all" className="flex-1 rounded-lg text-xs data-[state=active]:bg-primary data-[state=active]:text-primary-foreground">
                Semua
              </TabsTrigger>
              <TabsTrigger value="buyer_merchant" className="flex-1 rounded-lg text-xs data-[state=active]:bg-primary data-[state=active]:text-primary-foreground">
                <Store className="h-3 w-3 mr-1" /> Penjual
              </TabsTrigger>
              <TabsTrigger value="buyer_courier" className="flex-1 rounded-lg text-xs data-[state=active]:bg-primary data-[state=active]:text-primary-foreground">
                <Truck className="h-3 w-3 mr-1" /> Kurir
              </TabsTrigger>
            </TabsList>
          </div>
        </Tabs>

        {loading ? (
          <div className="flex items-center justify-center py-20">
            <div className="animate-spin rounded-full h-10 w-10 border-2 border-primary border-t-transparent" />
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20 text-center">
            <MessageCircle className="h-16 w-16 text-muted-foreground/30 mb-4" />
            <p className="text-muted-foreground">Belum ada percakapan</p>
          </div>
        ) : (
          <div className="space-y-2">
            {filtered.map(thread => (
               <Card key={thread.conversationId || `${thread.orderId}-${thread.chatType}`} className="cursor-pointer hover:bg-accent/50 transition" onClick={() => {
                 setSelectedThread(thread);
                 setThreads((current) => current.map((item) => item.conversationId === thread.conversationId ? { ...item, unreadCount: 0 } : item));
               }}>
                <CardContent className="p-4 flex items-center gap-3">
                  <div className="w-10 h-10 rounded-lg bg-muted overflow-hidden flex-shrink-0">
                    {thread.productImage ? (
                      <img src={thread.productImage} alt={thread.productName || ''} className="w-full h-full object-cover" />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center">
                        {thread.chatType === 'buyer_courier' ? <Truck className="h-5 w-5 text-muted-foreground" /> : <ShoppingBag className="h-5 w-5 text-muted-foreground" />}
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
                  <p className="text-[10px] text-muted-foreground flex-shrink-0">
                    {formatDistanceToNow(new Date(thread.lastMessageAt), { locale: idLocale, addSuffix: true })}
                  </p>
                </CardContent>
              </Card>
            ))}
          </div>
        )}
      </div>

      {selectedThread && (
        <OrderChat
          orderId={selectedThread.orderId}
          contextType={selectedThread.orderId ? 'order' : 'direct'}
          merchantId={selectedThread.merchantId || undefined}
          otherUserId={selectedThread.otherUserId}
          otherUserName={selectedThread.otherUserName}
          chatType={selectedThread.chatType}
          isOpen={!!selectedThread}
          onClose={() => setSelectedThread(null)}
        />
      )}
      <BottomNav />
    </div>
  );
}
