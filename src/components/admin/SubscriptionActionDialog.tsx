import { Ban, RotateCcw } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';

type SubscriptionActionKind = 'SUSPEND' | 'CANCEL';

interface SubscriptionActionDialogProps {
  open: boolean;
  action: SubscriptionActionKind;
  merchantName: string;
  reason: string;
  busy: boolean;
  onReasonChange: (reason: string) => void;
  onOpenChange: (open: boolean) => void;
  onConfirm: () => void;
}

export function SubscriptionActionDialog({
  open,
  action,
  merchantName,
  reason,
  busy,
  onReasonChange,
  onOpenChange,
  onConfirm,
}: SubscriptionActionDialogProps) {
  const isCancel = action === 'CANCEL';
  const actionLabel = isCancel ? 'Batalkan langganan' : 'Tangguhkan akses';

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{actionLabel} POS {merchantName}</DialogTitle>
          <DialogDescription>
            {isCancel
              ? 'Langganan akan dibatalkan dan akses operasional POS dihentikan. Tindakan ini tercatat pada riwayat langganan.'
              : 'Akses POS akan ditangguhkan sementara. Alasan akan tercatat pada riwayat langganan.'}
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-2 py-2">
          <Label htmlFor="subscription-action-reason">Alasan (wajib)</Label>
          <Textarea
            id="subscription-action-reason"
            value={reason}
            onChange={(event) => onReasonChange(event.target.value)}
            placeholder={isCancel ? 'Masukkan alasan pembatalan...' : 'Masukkan alasan penangguhan...'}
            rows={4}
            maxLength={500}
            disabled={busy}
          />
          <p className="text-xs text-muted-foreground">Maksimal 500 karakter.</p>
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)} disabled={busy}>
            Batal
          </Button>
          <Button
            type="button"
            variant="destructive"
            onClick={onConfirm}
            disabled={busy || !reason.trim()}
          >
            {busy
              ? 'Memproses...'
              : <>{isCancel ? <RotateCcw className="mr-2 h-4 w-4" /> : <Ban className="mr-2 h-4 w-4" />}{actionLabel}</>}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
