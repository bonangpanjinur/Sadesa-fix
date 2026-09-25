import { useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { Upload, X, Image as ImageIcon } from 'lucide-react';

const MIN_REFUND_REASON_LENGTH = 10;
const MAX_REFUND_REASON_LENGTH = 4000;

interface RefundRequestDialogProps {
  orderId: string;
  orderTotal: number;
  merchantId: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSuccess: () => void;
}

export function RefundRequestDialog({
  orderId,
  orderTotal,
  merchantId: _merchantId,
  open,
  onOpenChange,
  onSuccess,
}: RefundRequestDialogProps) {
  const [reason, setReason] = useState('');
  const [amount, setAmount] = useState(orderTotal.toString());
  const [loading, setLoading] = useState(false);
  const [images, setImages] = useState<File[]>([]);
  const [previews, setPreviews] = useState<string[]>([]);

  const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files) {
      const newFiles = Array.from(e.target.files).filter((file) => {
        if (!file.type.startsWith('image/') || file.size > 5 * 1024 * 1024) {
          toast.error(`${file.name} harus berupa gambar maksimal 5 MB`);
          return false;
        }
        return true;
      }).slice(0, Math.max(0, 4 - images.length));
      if (newFiles.length === 0) return;
      setImages(prev => [...prev, ...newFiles]);
      
      const newPreviews = newFiles.map(file => URL.createObjectURL(file));
      setPreviews(prev => [...prev, ...newPreviews]);
    }
  };

  const removeImage = (index: number) => {
    setImages(prev => prev.filter((_, i) => i !== index));
    setPreviews(prev => prev.filter((_, i) => i !== index));
  };

  const handleSubmit = async () => {
    const trimmedReason = reason.trim();
    if (trimmedReason.length < MIN_REFUND_REASON_LENGTH) {
      toast.error(`Alasan refund minimal ${MIN_REFUND_REASON_LENGTH} karakter`);
      return;
    }

    try {
      setLoading(true);
      
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('User not authenticated');
      const refundAmount = Number.parseInt(amount.replace(/\D/g, ''), 10);
      if (!Number.isInteger(refundAmount) || refundAmount <= 0 || refundAmount > orderTotal) {
        throw new Error('Jumlah refund tidak valid');
      }

      // Upload images if any
      const evidenceUrls: string[] = [];
      for (const file of images) {
        const fileExt = file.name.split('.').pop()?.toLowerCase() || 'jpg';
        const filePath = `refund-evidence/${user.id}/${orderId}/${crypto.randomUUID()}.${fileExt}`;

        const { error: uploadError } = await supabase.storage
          .from('public_assets')
          .upload(filePath, file);

        if (uploadError) throw uploadError;

        const { data: { publicUrl } } = supabase.storage
          .from('public_assets')
          .getPublicUrl(filePath);
        
        evidenceUrls.push(publicUrl);
      }

      const { error } = await supabase.rpc('create_refund_request' as never, {
        p_order_id: orderId,
        p_amount: refundAmount,
        p_reason: trimmedReason,
        p_evidence_urls: evidenceUrls,
      } as never);

      if (error) throw error;

      toast.success('Permintaan refund berhasil dikirim');
      onSuccess();
      onOpenChange(false);
      // Reset form
      setReason('');
      setAmount(orderTotal.toString());
      setImages([]);
      setPreviews([]);
    } catch (error) {
      console.error('Error submitting refund:', error);
      toast.error('Gagal mengirim permintaan refund');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Ajukan Refund</DialogTitle>
          <DialogDescription>
            Pesanan #{orderId.slice(0, 8).toUpperCase()}
          </DialogDescription>
        </DialogHeader>
        
        <div className="space-y-4 py-4">
          <div className="space-y-2">
            <Label htmlFor="amount">Jumlah Refund (Rp)</Label>
            <Input
              id="amount"
              type="number"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              max={orderTotal}
            />
            <p className="text-[10px] text-muted-foreground">Maksimal: Rp {orderTotal.toLocaleString('id-ID')}</p>
          </div>

          <div className="space-y-2">
            <Label htmlFor="reason">Alasan Refund</Label>
            <Textarea
              id="reason"
              placeholder="Jelaskan alasan Anda meminta pengembalian dana..."
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              minLength={MIN_REFUND_REASON_LENGTH}
              maxLength={MAX_REFUND_REASON_LENGTH}
              rows={3}
            />
            <p className="text-[10px] text-muted-foreground">
              Minimal {MIN_REFUND_REASON_LENGTH} karakter ({reason.length}/{MAX_REFUND_REASON_LENGTH})
            </p>
          </div>

          <div className="space-y-2">
            <Label>Bukti Foto (Opsional)</Label>
            <div className="grid grid-cols-4 gap-2">
              {previews.map((url, i) => (
                <div key={i} className="relative aspect-square rounded-md overflow-hidden border border-border">
                  <img src={url} alt="Preview" className="w-full h-full object-cover" />
                  <button
                    onClick={() => removeImage(i)}
                    className="absolute top-1 right-1 bg-destructive text-white rounded-full p-0.5"
                  >
                    <X className="h-3 w-3" />
                  </button>
                </div>
              ))}
              {previews.length < 4 && (
                <label className="aspect-square rounded-md border-2 border-dashed border-muted-foreground/25 flex flex-col items-center justify-center cursor-pointer hover:bg-muted/50 transition-colors">
                  <Upload className="h-5 w-5 text-muted-foreground" />
                  <span className="text-[10px] text-muted-foreground mt-1">Upload</span>
                  <input type="file" accept="image/*" className="hidden" onChange={handleImageChange} multiple />
                </label>
              )}
            </div>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Batal
          </Button>
          <Button onClick={handleSubmit} disabled={loading}>
            {loading ? 'Mengirim...' : 'Kirim Permintaan'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
