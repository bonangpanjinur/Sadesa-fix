import { useCallback, useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { MessageCircle, User, Loader2 } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';
import { id as idLocale } from 'date-fns/locale';
import { DesaLayout } from '@/components/desa/DesaLayout';
import { OrderChat, type ChatType } from '@/components/chat/OrderChat';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';

interface DesaChatThread {
  conversationId: string;
  orderId: string | null;
  otherUserId: string;
  otherUserName: string;
  lastMessage: string;
  lastMessageAt: string;
  unreadCount: number;
  chatType: ChatType;
}

export default function DesaChatPage() {
  const { user } = useAuth();
  const [searchParams] = useSearchParams();
  const [threads, setThreads] = useState<DesaChatThread[]>([]);
  const [selectedThread, setSelectedThread] = useState<DesaChatThread | null>(null);
  const [loading, setLoading] = useState(true);

  const fetchThreads = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    try {
      const { data: memberships } = await supabase
        .from('chat_participants')
        .select('conversation_id, last_read_at')
        .eq('user_id', user.id)
        .eq('role', 'admin_desa')
        .is('left_at', null);
      const conversationIds = [...new Set((memberships || []).map((row) => row.conversation_id))];
      if (conversationIds.length === 0) {
        setThreads([]);
        return;
      }

      const lastReadAt = new Map(
        (memberships || []).map((row) => [row.conversation_id, row.last_read_at ? new Date(row.last_read_at).getTime() : 0]),
      );
      const { data: messages } = await supabase
        .from('chat_messages')
        .select('id, conversation_id, order_id, sender_id, receiver_id, message, body, chat_type, created_at, is_read')
        .in('conversation_id', conversationIds)
        .is('deleted_at', null)
        .order('created_at', { ascending: false });
      const threadMap = new Map<string, DesaChatThread>();
      for (const message of messages || []) {
        if (!message.conversation_id || threadMap.has(message.conversation_id)) continue;
        const otherUserId = message.sender_id === user.id ? message.receiver_id : message.sender_id;
        if (!otherUserId) continue;
        const readAt = lastReadAt.get(message.conversation_id) || 0;
        const unreadCount = (messages || []).filter((item) =>
          item.conversation_id === message.conversation_id &&
          item.receiver_id === user.id &&
          (!item.is_read || new Date(item.created_at).getTime() > readAt),
        ).length;
        threadMap.set(message.conversation_id, {
          conversationId: message.conversation_id,
          orderId: message.order_id,
          otherUserId,
          otherUserName: 'Pengguna',
          lastMessage: message.body || message.message || 'Pesan baru',
          lastMessageAt: message.created_at,
          unreadCount,
          chatType: (message.chat_type || 'buyer_merchant') as ChatType,
        });
      }

      const otherUserIds = [...new Set([...threadMap.values()].map((thread) => thread.otherUserId))];
      if (otherUserIds.length > 0) {
        const [{ data: profiles }, { data: merchants }, { data: couriers }] = await Promise.all([
          supabase.from('profiles').select('user_id, full_name').in('user_id', otherUserIds),
          supabase.from('merchants').select('user_id, name').in('user_id', otherUserIds),
          supabase.from('couriers').select('user_id, name').in('user_id', otherUserIds),
        ]);
        for (const thread of threadMap.values()) {
          const profile = (profiles || []).find((item) => item.user_id === thread.otherUserId);
          const merchant = (merchants || []).find((item) => item.user_id === thread.otherUserId);
          const courier = (couriers || []).find((item) => item.user_id === thread.otherUserId);
          thread.otherUserName = merchant?.name || courier?.name || profile?.full_name || 'Pengguna';
        }
      }
      setThreads([...threadMap.values()]);
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    void fetchThreads();
    if (!user) return;
    const channel = supabase
      .channel(`desa-chat-${user.id}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'chat_messages' }, () => void fetchThreads())
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [fetchThreads, user]);

  useEffect(() => {
    const conversationId = searchParams.get('conversationId') || searchParams.get('conversation');
    if (!conversationId || selectedThread || threads.length === 0) return;
    const match = threads.find((thread) => thread.conversationId === conversationId);
    if (match) setSelectedThread(match);
  }, [searchParams, selectedThread, threads]);

  return (
    <DesaLayout title="Chat" subtitle="Percakapan dengan warga dan pelaku usaha">
      {loading ? (
        <div className="flex items-center justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-primary" /></div>
      ) : threads.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 text-center text-muted-foreground">
          <MessageCircle className="h-14 w-14 mb-4 opacity-30" />
          <p className="font-medium">Belum ada percakapan</p>
          <p className="text-xs mt-1">Percakapan dengan admin desa akan muncul di sini</p>
        </div>
      ) : (
        <div className="space-y-2">
          {threads.map((thread) => (
            <Card key={thread.conversationId} className="cursor-pointer hover:bg-accent/50 transition" onClick={() => setSelectedThread(thread)}>
              <CardContent className="p-4 flex items-center gap-3">
                <div className="h-10 w-10 rounded-full bg-primary/10 flex items-center justify-center"><User className="h-5 w-5 text-primary" /></div>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2"><span className="font-medium truncate">{thread.otherUserName}</span>{thread.unreadCount > 0 && <Badge variant="destructive">{thread.unreadCount}</Badge>}</div>
                  <p className="text-xs text-muted-foreground truncate">{thread.lastMessage}</p>
                </div>
                <span className="text-[10px] text-muted-foreground whitespace-nowrap">{formatDistanceToNow(new Date(thread.lastMessageAt), { addSuffix: true, locale: idLocale })}</span>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
      {selectedThread && (
        <OrderChat
          orderId={selectedThread.orderId || undefined}
          conversationId={selectedThread.conversationId}
          contextType={selectedThread.orderId ? 'order' : 'direct'}
          otherUserId={selectedThread.otherUserId}
          otherUserName={selectedThread.otherUserName}
          chatType={selectedThread.chatType}
          isOpen
          onClose={() => setSelectedThread(null)}
        />
      )}
    </DesaLayout>
  );
}
