import type { ChatConnectionState } from '@/lib/chat/types';

export function ChatConnectionStatus({ status }: { status: ChatConnectionState }) {
  if (status === 'subscribed' || status === 'idle') return null;
  const labels: Record<string, string> = { loading: 'Memuat percakapan…', reconnecting: 'Menghubungkan kembali…', offline: 'Offline — pesan baru mungkin tertunda', closed: 'Percakapan ditutup', expired: 'Percakapan kedaluwarsa' };
  return <div role="status" className="border-b bg-muted/60 px-3 py-2 text-center text-xs text-muted-foreground">{labels[status] || 'Status chat tidak tersedia'}</div>;
}
