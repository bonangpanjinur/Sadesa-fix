import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Send } from 'lucide-react';
import { CHAT_MAX_MESSAGE_LENGTH, validateMessageBody } from '@/lib/chat/retention';

export function MessageComposer({ onSend, disabled, onTyping }: { onSend: (text: string) => Promise<void> | void; disabled?: boolean; onTyping?: (typing: boolean) => void }) {
  const [value, setValue] = useState(''); const validation = value ? validateMessageBody(value) : null;
  const send = async () => { if (validation || !value.trim() || disabled) return; await onSend(value.trim()); setValue(''); onTyping?.(false); };
  return <div className="border-t p-3"><div className="flex items-end gap-2"><Textarea aria-label="Tulis pesan" value={value} maxLength={CHAT_MAX_MESSAGE_LENGTH} disabled={disabled} placeholder="Tulis pesan…" rows={1} onChange={(event) => { setValue(event.target.value); onTyping?.(Boolean(event.target.value)); }} onKeyDown={(event) => { if (event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); void send(); } }} /> <Button type="button" size="icon" aria-label="Kirim pesan" disabled={disabled || Boolean(validation) || !value.trim()} onClick={() => void send()}><Send className="h-4 w-4" /></Button></div><div className="mt-1 flex justify-between text-[10px] text-muted-foreground"><span>{validation || 'Enter untuk kirim · Shift+Enter untuk baris baru'}</span><span>{value.length}/{CHAT_MAX_MESSAGE_LENGTH}</span></div></div>;
}
