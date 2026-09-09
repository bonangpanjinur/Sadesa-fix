import { useCallback, useEffect, useState } from 'react';
import { listChatInbox } from '@/lib/chat/repository';
import type { ChatInboxItem } from '@/lib/chat/types';

export function useChatInbox() {
  const [items, setItems] = useState<ChatInboxItem[]>([]); const [loading, setLoading] = useState(true); const [error, setError] = useState<string | null>(null);
  const refresh = useCallback(async () => { setLoading(true); const result = await listChatInbox(); setItems(result.items); setError(result.error?.message || null); setLoading(false); }, []);
  useEffect(() => { void refresh(); }, [refresh]);
  return { items, loading, error, refresh };
}
