import { Button } from '@/components/ui/button';
import { ArrowLeft, X } from 'lucide-react';

export function ConversationHeader({ title, subtitle, onClose, onBack }: { title: string; subtitle?: string; onClose?: () => void; onBack?: () => void }) {
  return <header className="flex items-center gap-2 border-b p-3"><Button variant="ghost" size="icon" aria-label="Kembali" onClick={onBack || onClose}><ArrowLeft className="h-4 w-4" /></Button><div className="min-w-0 flex-1"><h2 className="truncate font-semibold">{title}</h2>{subtitle && <p className="truncate text-xs text-muted-foreground">{subtitle}</p>}</div>{onClose && <Button variant="ghost" size="icon" aria-label="Tutup chat" onClick={onClose}><X className="h-4 w-4" /></Button>}</header>;
}
