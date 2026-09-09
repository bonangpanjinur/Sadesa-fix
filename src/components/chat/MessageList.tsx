import { useEffect, useRef } from 'react';
import { cn } from '@/lib/utils';
import { messageDisplayBody } from '@/lib/chat/retention';
import type { ConversationMessage } from '@/lib/chat/types';
import { MessageStatus } from './MessageStatus';

export function MessageList({ messages, currentUserId, onRetry }: { messages: ConversationMessage[]; currentUserId?: string; onRetry?: (message: ConversationMessage) => void }) {
  const endRef = useRef<HTMLDivElement>(null); useEffect(() => { endRef.current?.scrollIntoView({ behavior: 'smooth' }); }, [messages.length]);
  return <div className="flex-1 space-y-2 overflow-y-auto p-4" aria-live="polite">{messages.length === 0 ? <p className="py-12 text-center text-sm text-muted-foreground">Belum ada pesan. Mulai percakapan sekarang.</p> : messages.map((message) => { const own = message.sender_id === currentUserId; const deleted = Boolean(message.deleted_at || message.soft_delete_at && new Date(message.soft_delete_at) <= new Date()); return <div key={message.id} className={cn('flex', own ? 'justify-end' : 'justify-start')}><div className={cn('max-w-[82%] rounded-2xl px-3 py-2 text-sm', own ? 'bg-primary text-primary-foreground' : 'bg-muted', deleted && 'italic opacity-70')}><p>{messageDisplayBody(message)}</p><div className="mt-1 flex justify-end gap-2"><span className="text-[10px] opacity-70">{new Date(message.created_at).toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' })}</span>{own && <MessageStatus status={message.deliveryStatus} onRetry={() => onRetry?.(message)} />}</div></div></div>; })}<div ref={endRef} /></div>;
}
