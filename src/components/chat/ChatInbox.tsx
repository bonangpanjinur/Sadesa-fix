import { MessageCircle } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { formatDistanceToNow } from 'date-fns';
import { id as idLocale } from 'date-fns/locale';
import { useChatInbox } from '@/hooks/chat/useChatInbox';
import type { ChatInboxItem } from '@/lib/chat/types';

export function ChatInbox({ onSelect, filter }: { onSelect: (item: ChatInboxItem) => void; filter?: string }) {
  const { items, loading, error } = useChatInbox(); const filtered = filter ? items.filter((item) => item.conversation_type === filter) : items;
  if (loading) return <div className="py-16 text-center text-sm text-muted-foreground">Memuat percakapan…</div>;
  if (error) return <div role="alert" className="py-16 text-center text-sm text-destructive">{error}</div>;
  if (!filtered.length) return <div className="flex flex-col items-center py-16 text-center text-muted-foreground"><MessageCircle className="mb-3 h-12 w-12 opacity-30" /><p>Belum ada percakapan</p><p className="text-xs">Percakapan yang dapat Anda akses akan muncul di sini.</p></div>;
  return <div className="space-y-2">{filtered.map((item) => <Card key={item.id} tabIndex={0} role="button" className="cursor-pointer transition hover:bg-accent/50" onClick={() => onSelect(item)} onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') onSelect(item); }}><CardContent className="flex items-center gap-3 p-4"><MessageCircle className="h-5 w-5 text-primary" /><div className="min-w-0 flex-1"><div className="flex gap-2"><span className="truncate text-sm font-medium">{item.other_user_name}</span>{Boolean(item.unread_count) && <Badge variant="destructive">{item.unread_count}</Badge>}</div><p className="truncate text-xs text-muted-foreground">{item.last_message_preview}</p></div>{item.last_message_at && <time className="text-[10px] text-muted-foreground">{formatDistanceToNow(new Date(item.last_message_at), { locale: idLocale, addSuffix: true })}</time>}</CardContent></Card>)}</div>;
}
