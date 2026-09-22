import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Camera, ImagePlus, Send, X } from 'lucide-react';
import { CHAT_MAX_MESSAGE_LENGTH, validateMessageBody } from '@/lib/chat/retention';

const IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
const MAX_IMAGE_SIZE = 5 * 1024 * 1024;

export function MessageComposer({ onSend, disabled, onTyping }: { onSend: (text: string, image?: File) => Promise<void> | void; disabled?: boolean; onTyping?: (typing: boolean) => void }) {
  const [value, setValue] = useState('');
  const [image, setImage] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [fileError, setFileError] = useState<string | null>(null);
  const validation = value ? validateMessageBody(value) : null;

  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview); }, [preview]);

  const send = async () => {
    if (validation || (!value.trim() && !image) || disabled) return;
    await onSend(value.trim(), image || undefined);
    setValue('');
    setImage(null);
    if (preview) URL.revokeObjectURL(preview);
    setPreview(null);
    onTyping?.(false);
  };

  const chooseImage = (file?: File) => {
    if (!file) return;
    if (!IMAGE_TYPES.includes(file.type)) { setFileError('Format gambar harus JPG, PNG, WebP, atau GIF.'); return; }
    if (file.size > MAX_IMAGE_SIZE) { setFileError('Ukuran gambar maksimal 5 MB.'); return; }
    if (preview) URL.revokeObjectURL(preview);
    setImage(file);
    setPreview(URL.createObjectURL(file));
    setFileError(null);
  };

  const clearImage = () => {
    if (preview) URL.revokeObjectURL(preview);
    setImage(null);
    setPreview(null);
    setFileError(null);
  };

  return <div className="border-t p-3">
    {preview && <div className="mb-2 flex items-center gap-2 rounded-lg bg-muted p-2"><img src={preview} alt="Pratinjau gambar" className="h-12 w-12 rounded object-cover" /><span className="min-w-0 flex-1 truncate text-xs">{image?.name}</span><Button type="button" variant="ghost" size="icon" className="h-7 w-7" onClick={clearImage} aria-label="Hapus gambar"><X className="h-4 w-4" /></Button></div>}
    <div className="flex items-end gap-2">
      <input id="conversation-camera-capture" type="file" accept="image/*" capture="environment" className="sr-only" onChange={(event) => { chooseImage(event.target.files?.[0]); event.currentTarget.value = ''; }} />
      <input id="conversation-gallery-upload" type="file" accept={IMAGE_TYPES.join(',')} className="sr-only" onChange={(event) => { chooseImage(event.target.files?.[0]); event.currentTarget.value = ''; }} />
      <Button type="button" variant="outline" size="icon" aria-label="Ambil foto dengan kamera" title="Ambil foto dengan kamera" disabled={disabled} onClick={() => document.getElementById('conversation-camera-capture')?.click()}><Camera className="h-4 w-4" /></Button>
      <Button type="button" variant="outline" size="icon" aria-label="Pilih gambar dari galeri" title="Pilih gambar dari galeri" disabled={disabled} onClick={() => document.getElementById('conversation-gallery-upload')?.click()}><ImagePlus className="h-4 w-4" /></Button>
      <Textarea aria-label="Tulis pesan" value={value} maxLength={CHAT_MAX_MESSAGE_LENGTH} disabled={disabled} placeholder="Tulis pesan…" rows={1} onChange={(event) => { setValue(event.target.value); onTyping?.(Boolean(event.target.value)); }} onKeyDown={(event) => { if (event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); void send(); } }} />
      <Button type="button" size="icon" aria-label="Kirim pesan" disabled={disabled || Boolean(validation) || (!value.trim() && !image)} onClick={() => void send()}><Send className="h-4 w-4" /></Button>
    </div>
    <div className="mt-1 flex justify-between text-[10px] text-muted-foreground"><span>{fileError || validation || 'Enter untuk kirim · Shift+Enter untuk baris baru'}</span><span>{value.length}/{CHAT_MAX_MESSAGE_LENGTH}</span></div>
  </div>;
}
