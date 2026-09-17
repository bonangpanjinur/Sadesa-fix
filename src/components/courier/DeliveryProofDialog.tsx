/** S4-01: Bukti kirim foto — upload private lalu transisi status via RPC. */
import { useEffect, useRef, useState } from 'react';
import { Camera, Upload, X, CheckCircle, Loader2 } from 'lucide-react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface DeliveryProofDialogProps { open: boolean; onClose: () => void; orderId: string; orderNumber: string; onConfirmed: () => void; }
const DELIVERY_PROOF_BUCKET = 'pod-images';

export function DeliveryProofDialog({ open, onClose, orderId, orderNumber, onConfirmed }: DeliveryProofDialogProps) {
  const [photo, setPhoto] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [notes, setNotes] = useState('');
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const cameraRef = useRef<HTMLInputElement>(null);

  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview); }, [preview]);
  const handleFile = (file: File) => {
    if (!file.type.startsWith('image/')) return toast.error('Hanya file gambar yang diizinkan');
    if (file.size > 5 * 1024 * 1024) return toast.error('Ukuran foto maksimal 5MB');
    setPhoto(file); setPreview(URL.createObjectURL(file));
  };
  const clearPhoto = () => { setPhoto(null); if (preview) URL.revokeObjectURL(preview); setPreview(null); };

  const handleSubmit = async () => {
    if (!photo) return toast.error('Harap ambil/upload foto bukti pengiriman');
    setUploading(true);
    try {
      const path = `${orderId}/${crypto.randomUUID()}-${photo.name.replace(/[^a-zA-Z0-9._-]/g, '_')}`;
      const { error: uploadError } = await supabase.storage.from(DELIVERY_PROOF_BUCKET).upload(path, photo, { contentType: photo.type, upsert: false });
      if (uploadError) throw uploadError;
      const { error } = await supabase.rpc('courier_complete_delivery' as never, {
        p_order_id: orderId, p_proof_path: path, p_notes: notes.trim() || null,
      } as never);
      if (error) {
        await supabase.storage.from(DELIVERY_PROOF_BUCKET).remove([path]);
        throw error;
      }
      toast.success(`Pengiriman #${orderNumber} berhasil diselesaikan`);
      onConfirmed(); onClose(); clearPhoto(); setNotes('');
    } catch (error) {
      toast.error(`Gagal menyelesaikan pengiriman: ${error instanceof Error ? error.message : 'Coba lagi'}`);
    } finally { setUploading(false); }
  };

  return <Dialog open={open} onOpenChange={onClose}><DialogContent className="max-w-sm">
    <DialogHeader><DialogTitle className="flex items-center gap-2"><Camera className="h-5 w-5 text-primary" /> Bukti Pengiriman</DialogTitle></DialogHeader>
    <div className="space-y-4">
      <p className="text-sm text-muted-foreground">Upload foto bukti pengiriman barang <strong>#{orderNumber}</strong>.</p>
      {preview ? <div className="relative"><img src={preview} alt="Preview bukti pengiriman" className="w-full h-48 object-cover rounded-lg border" /><Button variant="destructive" size="icon" className="absolute top-2 right-2 h-7 w-7" onClick={clearPhoto}><X className="h-4 w-4" /></Button></div> : <div className="grid grid-cols-2 gap-2"><Button variant="outline" className="h-24 flex-col gap-2" onClick={() => cameraRef.current?.click()}><Camera className="h-8 w-8 text-primary" /><span className="text-xs">Ambil Foto</span></Button><Button variant="outline" className="h-24 flex-col gap-2" onClick={() => fileRef.current?.click()}><Upload className="h-8 w-8 text-muted-foreground" /><span className="text-xs">Pilih File</span></Button></div>}
      <input ref={cameraRef} type="file" accept="image/*" capture="environment" className="hidden" onChange={e => e.target.files?.[0] && handleFile(e.target.files[0])} />
      <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={e => e.target.files?.[0] && handleFile(e.target.files[0])} />
      <div><Label className="text-sm">Catatan (opsional)</Label><Textarea placeholder="Misal: Diterima oleh satpam atau ditinggal di depan pintu" value={notes} onChange={e => setNotes(e.target.value)} className="mt-1 resize-none" rows={2} /></div>
    </div>
    <DialogFooter><Button variant="outline" onClick={onClose} disabled={uploading}>Batal</Button><Button onClick={handleSubmit} disabled={!photo || uploading}>{uploading ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" />Mengupload...</> : <><CheckCircle className="h-4 w-4 mr-2" />Konfirmasi Terkirim</>}</Button></DialogFooter>
  </DialogContent></Dialog>;
}
