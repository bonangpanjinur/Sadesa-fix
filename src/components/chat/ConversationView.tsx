import { useEffect, useMemo } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useConversation } from '@/hooks/chat/useConversation';
import { useTypingIndicator } from '@/hooks/chat/useTypingIndicator';
import type { ConversationType } from '@/lib/chat/types';
import { ChatConnectionStatus } from './ChatConnectionStatus';
import { ConversationHeader } from './ConversationHeader';
import { MessageComposer } from './MessageComposer';
import { MessageList } from './MessageList';

export function ConversationView({ title, subtitle, contextType, conversationType, orderId, rideRequestId, merchantId, receiverId, onClose }: { title: string; subtitle?: string; contextType: 'order' | 'ride' | 'direct'; conversationType: ConversationType; orderId?: string; rideRequestId?: string; merchantId?: string; receiverId: string; onClose?: () => void }) {
  const { user } = useAuth();
  const conversationOptions = useMemo(() => ({ contextType, conversationType, orderId, rideRequestId, merchantId, receiverId }), [contextType, conversationType, orderId, rideRequestId, merchantId, receiverId]);
  const chat = useConversation(conversationOptions); const typing = useTypingIndicator(chat.conversationId);
  useEffect(() => { const handler = (event: KeyboardEvent) => { if (event.key === 'Escape') onClose?.(); }; window.addEventListener('keydown', handler); return () => window.removeEventListener('keydown', handler); }, [onClose]);
  return <section className="flex h-full min-h-0 flex-col overflow-hidden rounded-xl border bg-card" aria-label={`Percakapan dengan ${title}`}><ConversationHeader title={title} subtitle={typing.typing ? 'Sedang mengetik…' : subtitle} onClose={onClose} /><ChatConnectionStatus status={chat.status} />{chat.error && <div role="alert" className="px-4 py-2 text-sm text-destructive">{chat.error}</div>}<MessageList messages={chat.messages} currentUserId={user?.id} onRetry={(message) => { if (message.body) void chat.retry(message.body); }} /><MessageComposer disabled={chat.status !== 'subscribed' || !chat.conversationId} onTyping={typing.setIsTyping} onSend={async (text) => { await chat.send(text); }} /></section>;
}
