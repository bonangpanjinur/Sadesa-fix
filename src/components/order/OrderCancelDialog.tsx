import { useState } from 'react';
import { AlertTriangle } from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';

interface OrderCancelDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  orderId: string;
  onCancelled: () => void;
  isDirectCourier?: boolean;
}

const cancelReasons = [
  'Berubah pikiran',
  'Ingin mengubah pesanan',
  'Menemukan harga lebih murah',
  'Waktu pengiriman terlalu lama',
  'Lainnya',
];

export function OrderCancelDialog({ 
  open, 
  onOpenChange, 
  orderId, 
  onCancelled,
  isDirectCourier = false,
}: OrderCancelDialogProps) {
  const { user } = useAuth();
  const [reason, setReason] = useState('');
  const [customReason, setCustomReason] = useState('');
  const [loading, setLoading] = useState(false);

  const handleCancel = async () => {
    if (!user || !reason) {
      toast.error('Pilih alasan pembatalan');
      return;
    }

    const finalReason = reason === 'Lainnya' ? customReason : reason;
    if (!finalReason.trim()) {
      toast.error('Berikan alasan pembatalan');
      return;
    }

    setLoading(true);

    try {
      const { error } = await supabase.rpc('buyer_cancel_order' as never, {
        p_order_id: orderId,
        p_reason: finalReason.trim(),
      } as never);

      if (error) throw error;

      toast.success('Pesanan berhasil dibatalkan');
      onCancelled();
      onOpenChange(false);
    } catch (error) {
      console.error('Error cancelling order:', error);
      toast.error('Gagal membatalkan pesanan');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <AlertTriangle className="h-5 w-5 text-destructive" />
            {isDirectCourier ? 'Batalkan Pengiriman' : 'Batalkan Pesanan'}
          </DialogTitle>
          <DialogDescription>
            {isDirectCourier
              ? 'Pengiriman dapat dibatalkan selama kurir belum mengambil barang. Setelah pickup, gunakan bantuan/refund.'
              : 'Apakah Anda yakin ingin membatalkan pesanan ini? Tindakan ini tidak dapat dibatalkan.'}
          </DialogDescription>
        </DialogHeader>

        <div className="py-4 space-y-4">
          <div className="space-y-2">
            <Label>Alasan Pembatalan *</Label>
            <RadioGroup value={reason} onValueChange={setReason}>
              {cancelReasons.map((r) => (
                <div key={r} className="flex items-center space-x-2">
                  <RadioGroupItem value={r} id={r} />
                  <Label htmlFor={r} className="font-normal cursor-pointer">
                    {r}
                  </Label>
                </div>
              ))}
            </RadioGroup>
          </div>

          {reason === 'Lainnya' && (
            <div className="space-y-2">
              <Label>Jelaskan alasan Anda</Label>
              <Textarea
                value={customReason}
                onChange={(e) => setCustomReason(e.target.value)}
                placeholder="Tulis alasan pembatalan..."
                rows={3}
              />
            </div>
          )}
        </div>

        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Kembali
          </Button>
          <Button 
            variant="destructive" 
            onClick={handleCancel}
            disabled={loading || !reason}
          >
            {loading ? 'Membatalkan...' : 'Ya, Batalkan Pesanan'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
