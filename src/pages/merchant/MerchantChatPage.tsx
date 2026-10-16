import { useCallback, useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { MerchantLayout } from '@/components/merchant/MerchantLayout';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { useMerchantGuard } from '@/hooks/useMerchantGuard';
import { OrderChat, ChatType } from '@/components/chat/OrderChat';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { MessageCircle, AlertCircle, Clock, User, Truck, ShoppingBag } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';
import { id as idLocale } from 'date-fns/locale';
import { createCoalescedTask } from '@/lib/createCoalescedTask';

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
  autoDeleteAt: string | null;
  productName?: string;
  productImage?: string | null;
}

export default function MerchantChatPage() {
  const { user } = useAuth();
  const { merchantId: guardMerchantId, loading: guardLoading } = useMerchantGuard();
  const [searchParams] = useSearchParams();
  const [merchantId, setMerchantId] = useState<string | null>(null);
  const [threads, setThreads] = useState<ChatThread[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedThread, setSelectedThread] = useState<ChatThread | null>(null);
  const [activeTab, setActiveTab] = useState<'all' | 'buyer_merchant' | 'merchant_courier'>('all');
  const navigate = useNavigate();

  useEffect(() => {
    if (guardMerchantId) {
      setMerchantId(guardMerchantId);
    }
  }, [guardMerchantId]);

  // Auto-open chat from orderId query param (notification quick action)
  useEffect(() => {
    const orderId = searchParams.get('orderId');
    const conversationId = searchParams.get('conversationId');
    if ((orderId || conversationId) && threads.length > 0 && !selectedThread) {
      const match = threads.find(t => conversationId
        ? t.conversationId === conversationId
        : t.orderId === orderId);
      if (match) {
        setSelectedThread(match);
      }
    }
  }, [searchParams, threads, selectedThread]);

  const fetchThreads = useCallback(async () => {
    if (!merchantId || !user) return;

    try {
      // Start from memberships so buyer-created frontend conversations are
      // visible to the merchant before the merchant sends a reply.
      const { data: memberships } = await supabase
        .from('chat_participants')
        .select('conversation_id, last_read_at, role')
        .eq('user_id', user.id)
        .eq('role', 'merchant')
        .is('left_at', null);
      const conversationIds = [...new Set((memberships || []).map((row) => row.conversation_id))];
      const lastReadAtByConversation = new Map(
        (memberships || []).map((row) => [row.conversation_id, row.last_read_at ? new Date(row.last_read_at).getTime() : 0]),
      );
      if (conversationIds.length === 0) { setThreads([]); setLoading(false); return; }

      const { data: messages } = await supabase
        .from('chat_messages')
        .select('conversation_id, order_id, chat_type, sender_id, receiver_id, message, created_at, is_read, deleted_at, auto_delete_at')
        .in('conversation_id', conversationIds)
        .is('deleted_at', null)
        .in('chat_type', ['buyer_merchant', 'merchant_courier', 'admin_merchant'])
        .order('created_at', { ascending: false })
        .limit(500);

      if (!messages || messages.length === 0) { setThreads([]); setLoading(false); return; }

      const threadMap = new Map<string, ChatThread>();
      for (const msg of messages) {
        const key = msg.conversation_id || `${msg.order_id}-${msg.chat_type}`;
        if (!threadMap.has(key)) {
          const otherUserId = msg.sender_id === user!.id ? msg.receiver_id : msg.sender_id;
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
            autoDeleteAt: msg.auto_delete_at,
          });
        }
        const lastReadAt = msg.conversation_id ? lastReadAtByConversation.get(msg.conversation_id) || 0 : 0;
        if (msg.sender_id !== user!.id && new Date(msg.created_at).getTime() > lastReadAt) {
          threadMap.get(key)!.unreadCount++;
        }
      }

      const directConversationIds = [...threadMap.values()]
        .map((thread) => thread.conversationId)
        .filter((conversationId): conversationId is string => Boolean(conversationId));
      if (directConversationIds.length > 0) {
        const { data: conversations } = await supabase
          .from('chat_conversations')
          .select('id, merchant_id, buyer_user_id, order_id')
          .in('id', directConversationIds);
        const conversationById = new Map((conversations || []).map((conversation) => [conversation.id, conversation]));
        for (const thread of threadMap.values()) {
          if (thread.conversationId) {
            const conversation = conversationById.get(thread.conversationId);
            thread.merchantId = conversation?.merchant_id || null;
            // Direct conversations carry the canonical buyer identity. This
            // prevents the merchant name from being shown as the chat partner.
            if (thread.chatType === 'buyer_merchant' && conversation?.buyer_user_id) {
              thread.otherUserId = conversation.buyer_user_id;
            }
          }
        }
      }

      const conversationIdsWithThreads = [...threadMap.values()]
        .map((thread) => thread.conversationId)
        .filter((conversationId): conversationId is string => Boolean(conversationId));
      const { data: conversationParticipants } = await supabase
        .from('chat_participants')
        .select('conversation_id, user_id')
        .in('conversation_id', conversationIdsWithThreads)
        .neq('user_id', user.id)
        .is('left_at', null);
      const participantByConversation = new Map(
        (conversationParticipants || []).map((participant) => [participant.conversation_id, participant.user_id]),
      );
      for (const thread of threadMap.values()) {
        const participantId = thread.conversationId ? participantByConversation.get(thread.conversationId) : null;
        if (participantId) thread.otherUserId = participantId;
      }

      const userIds = [...new Set([...threadMap.values()].map(t => t.otherUserId))];
      const [{ data: profiles }, { data: merchants }, { data: couriers }] = await Promise.all([
        supabase.rpc('get_chat_participant_profiles' as never, { p_user_ids: userIds } as never),
        supabase.from('merchants').select('user_id, name').in('user_id', userIds),
        supabase.from('couriers').select('user_id, name').in('user_id', userIds),
      ]);

      for (const thread of threadMap.values()) {
        const profile = (profiles || []).find(p => p.user_id === thread.otherUserId);
        const merchant = (merchants || []).find(m => m.user_id === thread.otherUserId);
        const courier = (couriers || []).find(c => c.user_id === thread.otherUserId);
        if (thread.chatType === 'admin_merchant') {
          thread.otherUserName = profile?.full_name?.trim() || 'Admin';
        } else if (thread.chatType === 'buyer_merchant') {
          thread.otherUserName = profile?.full_name?.trim() || merchant?.name?.trim() || 'Pembeli';
        } else {
          thread.otherUserName = courier?.name?.trim() || merchant?.name?.trim() || 'Kurir';
        }
      }

      // Fetch order items for product info
      const orderIds = [...new Set([...threadMap.values()].map(t => t.orderId).filter(Boolean))] as string[];
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
  }, [merchantId, user]);

  useEffect(() => {
    if (!merchantId || !user) return;
    const refreshInbox = createCoalescedTask(fetchThreads, 300);
    refreshInbox.runNow();

    const channel = supabase
      .channel(`merchant-chats-${user.id}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'chat_messages', filter: `receiver_id=eq.${user.id}` }, refreshInbox.trigger)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'chat_messages', filter: `sender_id=eq.${user.id}` }, refreshInbox.trigger)
      .subscribe();

    return () => { refreshInbox.dispose(); supabase.removeChannel(channel); };
  }, [merchantId, user, fetchThreads]);

  if (loading) {
    return (
      <MerchantLayout title="Chat" subtitle="Percakapan dengan pembeli & kurir">
        <div className="flex items-center justify-center py-20">
          <div className="animate-spin rounded-full h-10 w-10 border-2 border-primary border-t-transparent" />
        </div>
      </MerchantLayout>
    );
  }

  if (!merchantId) {
    return (
      <MerchantLayout title="Chat" subtitle="Percakapan dengan pembeli & kurir">
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <AlertCircle className="h-12 w-12 text-muted-foreground mb-4" />
          <p className="text-muted-foreground">Toko tidak ditemukan</p>
        </div>
      </MerchantLayout>
    );
  }

  const filtered = activeTab === 'all' ? threads : threads.filter(t => t.chatType === activeTab);

  return (
    <MerchantLayout title="Chat" subtitle="Percakapan dengan pembeli & kurir">
      <Tabs
        defaultValue="all"
        onValueChange={(value) => {
          if (value === 'all' || value === 'buyer_merchant' || value === 'merchant_courier') setActiveTab(value);
        }}
      >
        <div className="bg-card rounded-xl shadow-sm p-1.5 mb-4">
          <TabsList className="w-full bg-transparent h-auto p-0 gap-1">
            <TabsTrigger value="all" className="flex-1 rounded-lg text-xs data-[state=active]:bg-primary data-[state=active]:text-primary-foreground">Semua</TabsTrigger>
            <TabsTrigger value="buyer_merchant" className="flex-1 rounded-lg text-xs data-[state=active]:bg-primary data-[state=active]:text-primary-foreground">
              <User className="h-3 w-3 mr-1" /> Pembeli
            </TabsTrigger>
            <TabsTrigger value="merchant_courier" className="flex-1 rounded-lg text-xs data-[state=active]:bg-primary data-[state=active]:text-primary-foreground">
              <Truck className="h-3 w-3 mr-1" /> Kurir
            </TabsTrigger>
          </TabsList>
        </div>
      </Tabs>

      {filtered.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <MessageCircle className="h-16 w-16 text-muted-foreground/30 mb-4" />
          <p className="text-muted-foreground">Belum ada percakapan</p>
          <p className="text-xs text-muted-foreground mt-1">Chat akan muncul saat pembeli/kurir mengirim pesan</p>
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
                      <ShoppingBag className="h-5 w-5 text-muted-foreground" />
                    </div>
                  )}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-medium text-sm truncate">{thread.otherUserName}</span>
                    <Badge variant="outline" className="text-[10px] px-1.5 py-0">
                      {thread.chatType === 'merchant_courier'
                        ? 'Kurir'
                        : thread.chatType === 'admin_merchant' ? 'Admin' : 'Pembeli'}
                    </Badge>
                    {thread.unreadCount > 0 && (
                      <Badge variant="destructive" className="text-[10px] px-1.5 py-0">{thread.unreadCount}</Badge>
                    )}
                  </div>
                  {thread.productName && (
                    <button
                      type="button"
                      className="block max-w-full text-left text-[11px] text-primary/80 truncate hover:underline"
                      onClick={(event) => {
                        event.stopPropagation();
                        if (thread.orderId) navigate(`/merchant/orders?orderId=${thread.orderId}`);
                      }}
                      disabled={!thread.orderId}
                    >
                      {thread.productName}
                    </button>
                  )}
                  <p className="text-xs text-muted-foreground truncate">{thread.lastMessage}</p>
                </div>
                <div className="text-right flex-shrink-0">
                  <p className="text-[10px] text-muted-foreground">
                    {formatDistanceToNow(new Date(thread.lastMessageAt), { locale: idLocale, addSuffix: true })}
                  </p>
                  {thread.autoDeleteAt && (
                    <div className="flex items-center gap-0.5 text-[10px] text-warning mt-0.5">
                      <Clock className="h-2.5 w-2.5" /><span>Auto-hapus</span>
                    </div>
                  )}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {selectedThread && (
        <OrderChat
          orderId={selectedThread.orderId}
          conversationId={selectedThread.conversationId}
           contextType={selectedThread.orderId ? 'order' : 'direct'}
           merchantId={selectedThread.merchantId || undefined}
          otherUserId={selectedThread.otherUserId}
          otherUserName={selectedThread.otherUserName}
          chatType={selectedThread.chatType}
          isOpen={!!selectedThread}
          onClose={() => {
            setSelectedThread(null);
            navigate('/merchant/chat', { replace: true });
          }}
        />
      )}
    </MerchantLayout>
  );
}
