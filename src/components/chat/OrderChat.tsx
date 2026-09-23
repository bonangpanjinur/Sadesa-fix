import { useState, useEffect, useRef, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useChatNotification } from '@/hooks/useChatNotification';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Send, MessageCircle, X, Clock, ShoppingBag, User, Store, Truck, Volume2, VolumeX, AlertCircle, ImagePlus, Camera } from 'lucide-react';
import { cn } from '@/lib/utils';
import { format } from 'date-fns';
import { id as idLocale } from 'date-fns/locale';
import { formatPrice } from '@/lib/utils';
import {
  getOrCreateConversation,
  getOrCreateDirectConversation,
  getConversationReadAt,
  listConversationMessages,
  listOlderConversationMessages,
  markConversationRead,
  sendConversationMessage,
  subscribeToConversation,
  uploadChatImage,
  removeChatAttachment,
  getChatAttachmentUrl,
} from '@/lib/chat/repository';
import type { ChatContextType, ChatCursor } from '@/lib/chat/types';
import { useChatPresence } from '@/hooks/chat/useChatPresence';
import { useTypingIndicator } from '@/hooks/chat/useTypingIndicator';

export type ChatType =
  | 'buyer_merchant'
  | 'buyer_courier'
  | 'merchant_courier'
  | 'passenger_courier'
  | 'admin_merchant'
  | 'admin_courier'
  | 'admin_user';

interface JoinedUser {
  user_id: string | null;
}

type JoinedUserRelation = JoinedUser | JoinedUser[] | null;

const getJoinedUserId = (relation: JoinedUserRelation): string | null => Array.isArray(relation) ? relation[0]?.user_id ?? null : relation?.user_id ?? null;

interface ChatMessage {
  id: string;
  conversation_id?: string | null;
  sender_id: string;
  receiver_id: string | null;
  message: string;
  body?: string | null;
  is_read: boolean;
  created_at: string;
  auto_delete_at: string | null;
  chat_type: string | null;
  image_url: string | null;
  attachment_path?: string | null;
  client_message_id?: string | null;
  deleted_at?: string | null;
  deleted_reason?: string | null;
  soft_delete_at?: string | null;
  hard_delete_at?: string | null;
}

interface OrderInfo {
  shortId: string;
  total: number;
  items: { productName: string; quantity: number; imageUrl: string | null }[];
}

interface OrderChatProps {
  orderId?: string;
  contextType?: ChatContextType;
  conversationId?: string | null;
  rideRequestId?: string;
  merchantId?: string;
  otherUserId: string;
  otherUserName: string;
  isOpen: boolean;
  onClose: () => void;
  chatType?: ChatType;
  senderRole?: 'driver' | 'passenger';
}

const QUICK_REPLIES: Record<string, string[]> = {
  merchant_courier: ['Barang sudah siap diambil', 'Tolong hubungi saya dulu', 'Alamat pickup berubah'],
  buyer_courier: ['Sudah di mana?', 'Saya tunggu di depan rumah', 'Tolong hubungi saya'],
  buyer_merchant: ['Apakah stok masih ada?', 'Kapan pesanan saya dikirim?', 'Terima kasih!'],
  admin_merchant: ['Baik, admin.', 'Siap, akan saya tindak lanjuti.', 'Terima kasih informasinya.'],
  admin_courier: ['Baik, admin.', 'Siap, akan saya tindak lanjuti.', 'Terima kasih informasinya.'],
};

export function OrderChat({ orderId, contextType = 'order', conversationId: existingConversationId, rideRequestId, merchantId, otherUserId, otherUserName, isOpen, onClose, chatType = 'buyer_merchant', senderRole }: OrderChatProps) {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { playNotificationSound, isEnabled: isSoundEnabled, setIsEnabled: setIsSoundEnabled } = useChatNotification();
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [newMessage, setNewMessage] = useState('');
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [imageUrls, setImageUrls] = useState<Record<string, string>>({});
  const [sending, setSending] = useState(false);
  const [autoDeleteInfo, setAutoDeleteInfo] = useState<string | null>(null);
  const [senderNames, setSenderNames] = useState<Record<string, string>>({});
  const [orderInfo, setOrderInfo] = useState<OrderInfo & { 
    buyerId: string; 
    merchantId: string | null; 
    merchantUserId: string | null;
    courierId: string | null;
    courierUserId: string | null;
  } | null>(null);
  const [conversationId, setConversationId] = useState<string | null>(existingConversationId ?? null);
  const [connectionStatus, setConnectionStatus] = useState<'connected' | 'reconnecting' | 'offline'>('reconnecting');
  const [sendError, setSendError] = useState<string | null>(null);
  const [oldestCursor, setOldestCursor] = useState<ChatCursor | null>(null);
  const [hasOlderMessages, setHasOlderMessages] = useState(false);
  const [loadingOlderMessages, setLoadingOlderMessages] = useState(false);
  const presence = useChatPresence(conversationId);
  const typing = useTypingIndicator(conversationId);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const readStateTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const expectedConversationType = contextType === 'ride' ? 'passenger_courier' : chatType;

  useEffect(() => () => { if (imagePreview) URL.revokeObjectURL(imagePreview); }, [imagePreview]);

  useEffect(() => {
    let active = true;
    const resolveImages = async () => {
      const pending = messages.filter((message) => message.attachment_path && !imageUrls[message.id]);
      const resolved = await Promise.all(pending.map(async (message) => {
        const result = await getChatAttachmentUrl(message.attachment_path!);
        return result.url ? [message.id, result.url] as const : null;
      }));
      if (active && resolved.length) {
        setImageUrls((current) => ({ ...current, ...Object.fromEntries(resolved.filter(Boolean) as [string, string][]) }));
      }
    };
    void resolveImages();
    return () => { active = false; };
  }, [imageUrls, messages]);

  // Fetch order info (items + products)
  useEffect(() => {
    if (!isOpen || !orderId || contextType !== 'order') {
      setOrderInfo(null);
      return;
    }

    const fetchOrderInfo = async () => {
      // Fetch order with joined merchant and courier user_ids
      const { data: order } = await supabase
        .from('orders')
        .select(`
          id, 
          total, 
          buyer_id, 
          merchant_id, 
          courier_id,
          merchants (user_id),
          couriers (user_id)
        `)
        .eq('id', orderId)
        .maybeSingle();

      const { data: items } = await supabase
        .from('order_items')
        .select('product_name, quantity, product_id')
        .eq('order_id', orderId);

      if (!order || !items) return;

      // Fetch product images
      const productIds = items.map(i => i.product_id).filter(Boolean) as string[];
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

      // Safely extract merchant and courier user_ids from joined data
      const merchantUserId = getJoinedUserId(order.merchants as JoinedUserRelation);
      const courierUserId = getJoinedUserId(order.couriers as JoinedUserRelation);

      setOrderInfo({
        shortId: order.id.substring(0, 8).toUpperCase(),
        total: order.total,
        buyerId: order.buyer_id,
        merchantId: order.merchant_id,
        merchantUserId,
        courierId: order.courier_id,
        courierUserId,
        items: items.map(i => ({
          productName: i.product_name,
          quantity: i.quantity,
          imageUrl: i.product_id ? (imageMap[i.product_id] || null) : null,
        })),
      });
    };

    fetchOrderInfo();
  }, [contextType, isOpen, orderId]);

  // Memoize unique sender IDs to avoid re-fetching on every render
  const senderIdsKey = useMemo(() => {
    return [...new Set(messages.map(m => m.sender_id))].sort().join(',');
  }, [messages]);

  // Fetch sender names from profiles
  useEffect(() => {
    if (!isOpen || !senderIdsKey) return;

    const uniqueSenderIds = senderIdsKey.split(',').filter(Boolean);
    const missingIds = uniqueSenderIds.filter(id => !senderNames[id]);

    if (missingIds.length === 0) return;

    const fetchNames = async () => {
      const { data: profiles } = await supabase
        .from('profiles')
        .select('user_id, full_name')
        .in('user_id', missingIds);

      const { data: merchants } = await supabase
        .from('merchants')
        .select('user_id, name')
        .in('user_id', missingIds);

      const { data: couriers } = await supabase
        .from('couriers')
        .select('user_id, name')
        .in('user_id', missingIds);

      const nameMap: Record<string, string> = { ...senderNames };
      const isAdminConversation = chatType === 'admin_merchant' || chatType === 'admin_courier' || chatType === 'admin_user';

      missingIds.forEach(id => {
        const merchant = merchants?.find(m => m.user_id === id);
        const courier = couriers?.find(c => c.user_id === id);
        const profile = profiles?.find(p => p.user_id === id);

        if (isAdminConversation && profile?.full_name?.trim()) {
          // Admin identity is the profile name, even if the same account also
          // owns a merchant/courier record with a different display name.
          nameMap[id] = profile.full_name.trim();
        } else if (merchant) {
          nameMap[id] = merchant.name;
        } else if (courier) {
          nameMap[id] = courier.name;
        } else if (profile?.full_name) {
          nameMap[id] = profile.full_name;
        } else {
          nameMap[id] = 'Pengguna';
        }
      });

      setSenderNames(nameMap);
    };

    fetchNames();
  }, [chatType, isOpen, senderIdsKey, senderNames]);

  useEffect(() => {
    if (!isOpen || !user) return;

    let active = true;
    let channel: ReturnType<typeof supabase.channel> | null = null;
    setMessages([]);
    setOldestCursor(null);
    setHasOlderMessages(false);
    setLoadingOlderMessages(false);
    setAutoDeleteInfo(null);
    setSendError(null);
    setConnectionStatus('reconnecting');

    const appendMessage = (incoming: ChatMessage) => {
      if (!active || (expectedConversationType && incoming.chat_type !== expectedConversationType)) return;
      setMessages((previous) => {
        if (previous.some((message) => message.id === incoming.id)) return previous;
        return [...previous, incoming].sort((a, b) =>
          new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
        );
      });
      if (incoming.receiver_id === user.id) {
        if (incoming.conversation_id) {
          void markConversationRead(incoming.conversation_id, incoming.id);
        }
        playNotificationSound();
      }
    };

    const loadCanonicalConversation = async () => {
      // A thread selected from an inbox already has a canonical conversation.
      // Recreating a direct conversation here makes merchant replies call the
      // buyer-only direct-chat RPC and fail with 403.
      const result = existingConversationId
        ? { conversationId: existingConversationId, error: null }
        : contextType === 'direct' && merchantId
          ? await getOrCreateDirectConversation(merchantId)
          : await getOrCreateConversation({
              contextType,
              orderId: contextType === 'order' ? orderId : undefined,
              rideRequestId: contextType === 'ride' ? (rideRequestId || orderId) : undefined,
              conversationType: contextType === 'ride' ? 'passenger_courier' : chatType,
            });
      const { conversationId, error } = result;

      if (!active) return;

      if (!error && conversationId) {
        setConversationId(conversationId);
        const history = await listConversationMessages(conversationId);
        if (!active) return;
        if (!history.error) {
          const canonicalMessages = history.messages as ChatMessage[];
          setMessages(canonicalMessages);
          const refreshReadState = async () => {
            const readState = await getConversationReadAt(conversationId);
            if (!active || readState.error || !readState.readAt) return;
            setMessages((current) => current.map((message) => message.sender_id === user.id
              ? { ...message, is_read: message.is_read || message.created_at <= readState.readAt! }
              : message));
          };
          await refreshReadState();
          const oldest = canonicalMessages[0];
          setOldestCursor(oldest ? { createdAt: oldest.created_at, id: oldest.id } : null);
          setHasOlderMessages(canonicalMessages.length >= 50);
          const withDelete = canonicalMessages.find((message) => message.auto_delete_at);
          if (withDelete) setAutoDeleteInfo(withDelete.auto_delete_at);
          const lastIncoming = [...canonicalMessages]
            .reverse()
            .find((message) => message.sender_id !== user.id);
          if (lastIncoming) await markConversationRead(conversationId, lastIncoming.id);
        } else {
          setConnectionStatus('offline');
          setSendError('Riwayat chat belum dapat dimuat. Anda masih bisa mencoba mengirim pesan.');
        }

        setConnectionStatus('reconnecting');
        channel = subscribeToConversation(
          conversationId,
          (message) => {
            appendMessage(message as ChatMessage);
            setConnectionStatus('connected');
          },
          (status) => {
            if (!active) return;
            setConnectionStatus(status === 'SUBSCRIBED' ? 'connected' : 'reconnecting');
          },
          (message) => {
            if (!active) return;
            setMessages((previous) => previous.map((item) => item.id === message.id ? message as ChatMessage : item));
          },
        );
        readStateTimerRef.current = setInterval(() => {
          void getConversationReadAt(conversationId).then((readState) => {
            if (!active || readState.error || !readState.readAt) return;
            setMessages((current) => current.map((message) => message.sender_id === user.id
              ? { ...message, is_read: message.is_read || message.created_at <= readState.readAt! }
              : message));
          });
        }, 5000);
        return;
      }

      setConnectionStatus('offline');
      setSendError(error?.message || 'Chat belum tersedia. Minta admin menerapkan pembaruan database chat.');
    };

    void loadCanonicalConversation();
    return () => {
      active = false;
      if (channel) void supabase.removeChannel(channel);
      if (readStateTimerRef.current) clearInterval(readStateTimerRef.current);
      readStateTimerRef.current = null;
      setConversationId(null);
    };
  }, [chatType, contextType, isOpen, orderId, existingConversationId, rideRequestId, merchantId, user, expectedConversationType, playNotificationSound]);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const handleSend = async (messageText?: string) => {
    const text = (messageText || newMessage).trim();
    if ((!text && !imageFile) || !user || sending) return;
    typing.setIsTyping(false);

    setSending(true);
    setSendError(null);
    let uploadedPath: string | null = null;
    try {
      if (imageFile) {
        if (!['image/jpeg', 'image/png', 'image/webp', 'image/gif'].includes(imageFile.type)) {
          throw new Error('Format gambar harus JPG, PNG, WebP, atau GIF.');
        }
        if (imageFile.size > 5 * 1024 * 1024) throw new Error('Ukuran gambar maksimal 5 MB.');
      }
      const clientMessageId = crypto.randomUUID();
      if (conversationId) {
        if (imageFile) {
          const upload = await uploadChatImage(conversationId, user.id, imageFile);
          if (upload.error || !upload.path) throw upload.error || new Error('Gambar gagal diunggah.');
          uploadedPath = upload.path;
        }
        const { message, error } = await sendConversationMessage({
          contextType,
          orderId: contextType === 'order' ? orderId : undefined,
          rideRequestId: contextType === 'ride' ? (rideRequestId || orderId) : undefined,
          conversationType: contextType === 'ride' ? 'passenger_courier' : chatType,
          conversationId,
          senderId: user.id,
          receiverId: otherUserId,
          text,
          clientMessageId,
          attachmentPath: uploadedPath,
        });
        if (error) throw error;
        if (message) {
          setMessages((previous) => previous.some((item) => item.id === message.id)
            ? previous
            : [...previous, message as ChatMessage].sort((a, b) =>
              new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
            ));
        }
      } else {
        throw new Error('Chat conversation is not available');
      }
      if (!messageText) setNewMessage('');
      if (imagePreview) URL.revokeObjectURL(imagePreview);
      setImageFile(null);
      setImagePreview(null);
    } catch (error) {
      if (uploadedPath) await removeChatAttachment(uploadedPath);
      console.error('Error sending message:', error);
      const message = error instanceof Error ? error.message : '';
      setSendError(
        /FULL JOIN|0A000/i.test(message)
          ? 'Server chat belum selesai diperbarui. Minta admin menjalankan patch database chat, lalu coba lagi.'
          : message && !/Operasi chat gagal|Pesan belum terkirim/i.test(message)
            ? message
            : 'Pesan belum terkirim. Periksa koneksi lalu coba lagi.',
      );
    } finally {
      setSending(false);
    }
  };

  const getRoleInfo = (senderId: string) => {
    if (contextType === 'ride') {
      const isCurrentUser = senderId === user?.id;
      const role = isCurrentUser ? senderRole : (senderRole === 'driver' ? 'passenger' : 'driver');
      return role === 'driver'
        ? { label: 'Driver', color: 'bg-blue-100 text-blue-700', icon: <User className="h-2 w-2 mr-0.5" /> }
        : { label: 'Penumpang', color: 'bg-green-100 text-green-700', icon: <Truck className="h-2 w-2 mr-0.5" /> };
    }
    if (!orderInfo) return { label: '', color: 'bg-muted', icon: null };
    
    // Determine sender's role based on order data (matching against user_id)
    if (senderId === orderInfo.buyerId) {
      return { label: 'Pembeli', color: 'bg-blue-100 text-blue-700', icon: <User className="h-2 w-2 mr-0.5" /> };
    }
    
    // Check if sender is merchant (matching against merchant's user_id)
    if (senderId === orderInfo.merchantUserId) {
      return { label: 'Pedagang', color: 'bg-orange-100 text-orange-700', icon: <Store className="h-2 w-2 mr-0.5" /> };
    }
    
    // Check if sender is courier (matching against courier's user_id)
    if (senderId === orderInfo.courierUserId) {
      return { label: 'Kurir', color: 'bg-green-100 text-green-700', icon: <Truck className="h-2 w-2 mr-0.5" /> };
    }
    
    // Fallback for when roles are not explicitly linked yet or different user
    return { label: 'Pengguna', color: 'bg-muted text-muted-foreground', icon: null };
  };

  const loadOlderMessages = async () => {
    if (!conversationId || !oldestCursor || loadingOlderMessages || !hasOlderMessages) return;
    setLoadingOlderMessages(true);
    const result = await listOlderConversationMessages(conversationId, oldestCursor);
    if (!result.error) {
      setMessages((current) => {
        const existingIds = new Set(current.map((message) => message.id));
        return [...result.messages.filter((message) => !existingIds.has(message.id)), ...current];
      });
      const oldest = result.messages[0];
      if (oldest) setOldestCursor({ createdAt: oldest.created_at, id: oldest.id });
      if (result.messages.length < 50) setHasOlderMessages(false);
    } else {
      setSendError(result.error.message);
    }
    setLoadingOlderMessages(false);
  };

  const quickReplies = QUICK_REPLIES[contextType === 'ride' ? 'buyer_courier' : chatType] || [];

  if (!isOpen) return null;

  const firstItem = orderInfo?.items?.[0];
  const otherItemsCount = (orderInfo?.items?.length || 0) - 1;

  return (
    <div className="fixed inset-0 z-[2000] isolate flex items-end justify-center sm:items-center">
      {/* Leaflet uses pane/control z-index values up to 1000. Keep the chat in
          its own higher stacking context so map tiles and controls can never
          paint over the buyer/passenger modal. */}
      <div className="fixed inset-0 z-0 bg-black/50" onClick={onClose} />
      <div className="mobile-action-safe relative flex h-[min(92dvh,720px)] max-h-[calc(100dvh-0.5rem)] w-full max-w-md min-h-0 flex-col overflow-hidden rounded-t-2xl border border-border bg-card shadow-xl sm:h-[min(80vh,680px)] sm:max-h-[calc(100dvh-2rem)] sm:rounded-2xl">
        {/* Header */}
        <div className="flex shrink-0 items-center justify-between gap-2 border-b border-border p-3 sm:p-4">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
              <MessageCircle className="h-5 w-5 text-primary" />
            </div>
            <div className="min-w-0 flex-1">
              <h3 className="truncate text-sm font-semibold">{otherUserName}</h3>
              <p className="text-[10px] text-muted-foreground">
             {typing.typing
               ? 'Sedang mengetik…'
               : presence.online
                 ? 'Online sekarang'
                 : contextType === 'ride'
                   ? 'Perjalanan ojek'
                   : contextType === 'direct'
                     ? 'Chat langsung di SaDesa'
                     : `Order #${orderInfo?.shortId || '...'}`}
            {connectionStatus !== 'connected' && ' · Menghubungkan ulang...'}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-1">
            <Button 
              variant="ghost" 
              size="icon" 
              onClick={() => setIsSoundEnabled(!isSoundEnabled)}
              className="rounded-full"
              title={isSoundEnabled ? 'Matikan notifikasi suara' : 'Nyalakan notifikasi suara'}
            >
              {isSoundEnabled ? (
                <Volume2 className="h-5 w-5" />
              ) : (
                <VolumeX className="h-5 w-5" />
              )}
            </Button>
            <Button variant="ghost" size="icon" onClick={onClose} className="rounded-full">
              <X className="h-5 w-5" />
            </Button>
          </div>
        </div>

        {/* Order Brief */}
        {orderInfo && (
          <div className="p-3 bg-accent/30 border-b border-border flex items-center gap-3">
            <div className="w-10 h-10 rounded bg-background overflow-hidden border border-border flex-shrink-0">
              {firstItem?.imageUrl ? (
                <img src={firstItem.imageUrl} alt="" className="w-full h-full object-cover" />
              ) : (
                <div className="w-full h-full flex items-center justify-center bg-muted">
                  <ShoppingBag className="h-4 w-4 text-muted-foreground" />
                </div>
              )}
            </div>
            <button
              type="button"
              className="flex-1 min-w-0 text-left hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded"
              onClick={() => orderId && navigate(`/orders?orderId=${orderId}`)}
              aria-label="Buka pesanan terkait"
            >
              <p className="text-[11px] font-medium truncate">
                {firstItem?.productName}
                {otherItemsCount > 0 && ` +${otherItemsCount} produk lainnya`}
              </p>
              <p className="text-[10px] text-primary font-semibold">{formatPrice(orderInfo.total)}</p>
            </button>
          </div>
        )}

        {/* Messages */}
        <div className="min-h-0 min-w-0 flex-1 basis-0 space-y-4 overflow-y-auto overscroll-contain p-3 sm:p-4">
          {hasOlderMessages && (
            <div className="flex justify-center">
              <Button type="button" variant="outline" size="sm" onClick={() => void loadOlderMessages()} disabled={loadingOlderMessages}>
                {loadingOlderMessages ? 'Memuat pesan lama...' : 'Muat pesan sebelumnya'}
              </Button>
            </div>
          )}
          {autoDeleteInfo && (
            <div className="flex items-center justify-center gap-1.5 p-2 bg-warning/10 rounded-lg border border-warning/20 mb-4">
              <Clock className="h-3 w-3 text-warning" />
              <p className="text-[10px] text-warning font-medium">
                Pesan akan dihapus otomatis setelah pesanan selesai
              </p>
            </div>
          )}

          {messages.length === 0 ? (
            <div className="flex min-h-full flex-col items-center justify-center px-4 py-10 text-center text-muted-foreground">
              <MessageCircle className="h-12 w-12 opacity-20 mb-2" />
              <p className="text-xs">Belum ada pesan. Mulai percakapan sekarang!</p>
            </div>
          ) : (
            messages.map((msg, idx) => {
              const isMe = msg.sender_id === user?.id;
              const isDeleted = Boolean(msg.deleted_at || (msg.soft_delete_at && new Date(msg.soft_delete_at) <= new Date()));
              const roleInfo = getRoleInfo(msg.sender_id);
              const showDate = idx === 0 || 
                format(new Date(messages[idx-1].created_at), 'yyyy-MM-dd') !== format(new Date(msg.created_at), 'yyyy-MM-dd');
              
              return (
                <div key={msg.id} className="space-y-2">
                  {showDate && (
                    <div className="flex justify-center my-4">
                      <span className="text-[10px] bg-muted px-2 py-0.5 rounded-full text-muted-foreground">
                        {format(new Date(msg.created_at), 'd MMMM yyyy', { locale: idLocale })}
                      </span>
                    </div>
                  )}
                  <div className={cn("flex flex-col", isMe ? "items-end" : "items-start")}>
                    <div className="flex items-center gap-1.5 mb-1 px-1">
                      <span className="text-[10px] font-semibold text-muted-foreground">
                        {isMe ? 'Anda' : (chatType === 'admin_merchant' || chatType === 'admin_courier' || chatType === 'admin_user' ? (senderNames[msg.sender_id] || otherUserName || 'Admin SaDesa') : (senderNames[msg.sender_id] || otherUserName))}
                      </span>
                      <span className={cn("text-[9px] px-1.5 py-0.5 rounded flex items-center font-bold uppercase tracking-wider", roleInfo.color)}>
                        {roleInfo.icon}
                        {roleInfo.label}
                      </span>
                    </div>
                    <div className={cn(
                      "max-w-[85%] px-3 py-2 rounded-2xl text-sm shadow-sm",
                      isMe ? "bg-primary text-primary-foreground rounded-tr-none" : "bg-muted rounded-tl-none"
                    )}>
                       {!isDeleted && msg.attachment_path && imageUrls[msg.id] && (
                         <a href={imageUrls[msg.id]} target="_blank" rel="noreferrer" className="mb-1 block overflow-hidden rounded-lg">
                           <img src={imageUrls[msg.id]} alt="Gambar yang dikirim" className="max-h-64 w-full object-cover" loading="lazy" />
                         </a>
                       )}
                       {isDeleted ? <div className="italic opacity-70">Pesan dihapus</div> : ((msg.body || (!msg.attachment_path && msg.message)) && <div>{msg.body || msg.message}</div>)}
                      <div className={cn(
                        "text-[9px] mt-1 flex items-center justify-end gap-1 opacity-70",
                        isMe ? "text-primary-foreground" : "text-muted-foreground"
                      )}>
                        {format(new Date(msg.created_at), 'HH:mm')}
                        {isMe && (
                          <span className="text-[10px] font-bold">
                            {msg.is_read ? '✓✓' : '✓'}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                </div>
              );
            })
          )}
          <div ref={messagesEndRef} />
        </div>

        {/* Footer */}
        <div className="shrink-0 rounded-b-2xl border-t border-border bg-background p-3 sm:p-4">
          {sendError && (
            <div className="mb-3 flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/10 p-2.5 text-xs text-destructive">
              <AlertCircle className="h-4 w-4 mt-0.5 flex-shrink-0" />
              <span>{sendError}</span>
            </div>
          )}
          {quickReplies.length > 0 && (
            <div className="flex max-w-full gap-2 overflow-x-auto pb-3 no-scrollbar">
              {quickReplies.map((reply) => (
                <Button
                  key={reply}
                  variant="outline"
                  size="sm"
                  className="text-[10px] h-7 rounded-full whitespace-nowrap bg-accent/50 hover:bg-accent"
                  onClick={() => handleSend(reply)}
                >
                  {reply}
                </Button>
              ))}
            </div>
          )}
          {imagePreview && (
            <div className="mb-3 flex items-center gap-3 rounded-xl border border-border bg-muted/50 p-2">
              <img src={imagePreview} alt="Pratinjau gambar" className="h-14 w-14 rounded-lg object-cover" />
              <span className="min-w-0 flex-1 truncate text-xs text-muted-foreground">{imageFile?.name}</span>
              <Button type="button" variant="ghost" size="icon" className="h-8 w-8" onClick={() => { if (imagePreview) URL.revokeObjectURL(imagePreview); setImageFile(null); setImagePreview(null); }} aria-label="Hapus gambar">
                <X className="h-4 w-4" />
              </Button>
            </div>
          )}
          <div className="flex items-center gap-2">
            <input
              id="chat-camera-capture"
              type="file"
              accept="image/*"
              capture="environment"
              className="sr-only"
              onChange={(event) => {
                const file = event.target.files?.[0];
                event.currentTarget.value = '';
                if (!file) return;
                if (file.size > 5 * 1024 * 1024) { setSendError('Ukuran gambar maksimal 5 MB.'); return; }
                if (!['image/jpeg', 'image/png', 'image/webp', 'image/gif'].includes(file.type)) { setSendError('Format gambar harus JPG, PNG, WebP, atau GIF.'); return; }
                if (imagePreview) URL.revokeObjectURL(imagePreview);
                setImageFile(file);
                setImagePreview(URL.createObjectURL(file));
                setSendError(null);
              }}
            />
            <input
              id="chat-gallery-upload"
              type="file"
              accept="image/jpeg,image/png,image/webp,image/gif"
              className="sr-only"
              onChange={(event) => {
                const file = event.target.files?.[0];
                event.currentTarget.value = '';
                if (!file) return;
                if (file.size > 5 * 1024 * 1024) { setSendError('Ukuran gambar maksimal 5 MB.'); return; }
                if (!['image/jpeg', 'image/png', 'image/webp', 'image/gif'].includes(file.type)) { setSendError('Format gambar harus JPG, PNG, WebP, atau GIF.'); return; }
                if (imagePreview) URL.revokeObjectURL(imagePreview);
                setImageFile(file);
                setImagePreview(URL.createObjectURL(file));
                setSendError(null);
              }}
            />
            <Button type="button" variant="outline" size="icon" className="h-10 w-10 shrink-0 rounded-full" disabled={sending} onClick={() => document.getElementById('chat-camera-capture')?.click()} aria-label="Ambil foto dengan kamera" title="Ambil foto dengan kamera">
              <Camera className="h-4 w-4" />
            </Button>
            <Button type="button" variant="outline" size="icon" className="h-10 w-10 shrink-0 rounded-full" disabled={sending} onClick={() => document.getElementById('chat-gallery-upload')?.click()} aria-label="Pilih gambar dari galeri" title="Pilih gambar dari galeri">
              <ImagePlus className="h-4 w-4" />
            </Button>
            <Input
              placeholder="Ketik pesan..."
              value={newMessage}
              onChange={(e) => {
                setNewMessage(e.target.value);
                typing.setIsTyping(Boolean(e.target.value.trim()));
              }}
              onKeyDown={(e) => e.key === 'Enter' && handleSend()}
              className="flex-1 h-10 rounded-full bg-muted border-none focus-visible:ring-primary"
            />
            <Button 
              size="icon" 
              className="rounded-full h-10 w-10 shrink-0" 
              disabled={(!newMessage.trim() && !imageFile) || sending}
              onClick={() => handleSend()}
            >
              <Send className="h-4 w-4" />
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
