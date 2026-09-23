import { Button } from '@/components/ui/button';
import type { MessageDeliveryStatus } from '@/lib/chat/types';

export function MessageStatus({ status, isRead = false, onRetry }: { status?: MessageDeliveryStatus; isRead?: boolean; onRetry?: () => void }) {
  if (status === 'sending') return <span className="text-[10px] text-muted-foreground">Mengirim…</span>;
  if (status === 'failed') return <span className="flex items-center gap-1 text-[10px] text-destructive"><span>Gagal</span>{onRetry && <Button type="button" variant="link" size="sm" className="h-auto p-0 text-[10px]" onClick={onRetry}>Coba lagi</Button>}</span>;
  return status === 'sent' ? <span aria-label={isRead ? 'Dibaca' : 'Terkirim'} title={isRead ? 'Dibaca' : 'Terkirim'} className={isRead ? 'text-[11px] font-bold text-sky-500' : 'text-[11px] font-bold text-muted-foreground'}>{isRead ? '✓✓' : '✓'}</span> : null;
}
