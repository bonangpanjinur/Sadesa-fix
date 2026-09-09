import { Button } from '@/components/ui/button';
import type { MessageDeliveryStatus } from '@/lib/chat/types';

export function MessageStatus({ status, onRetry }: { status?: MessageDeliveryStatus; onRetry?: () => void }) {
  if (status === 'sending') return <span className="text-[10px] text-muted-foreground">Mengirim…</span>;
  if (status === 'failed') return <span className="flex items-center gap-1 text-[10px] text-destructive"><span>Gagal</span>{onRetry && <Button type="button" variant="link" size="sm" className="h-auto p-0 text-[10px]" onClick={onRetry}>Coba lagi</Button>}</span>;
  return status === 'sent' ? <span className="text-[10px] text-muted-foreground">Terkirim</span> : null;
}
