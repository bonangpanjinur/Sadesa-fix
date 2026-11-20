import { useState, useRef, useEffect } from 'react';
import { Upload, Loader2, CheckCircle, XCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { uploadFile, deleteFile, validateFile, compressImage } from '@/lib/storage';
import { getPaymentProofSignedUrl } from '@/lib/paymentProof';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { reportObservability } from '@/lib/observability';
import { sha256Hex } from '@/lib/guestCheckout';

interface PaymentProofUploadProps {
  orderId: string;
  currentProofUrl?: string | null;
  onUploaded: (url: string) => void;
  disabled?: boolean;
  guestAccessToken?: string;
  isRejected?: boolean;
}

export function PaymentProofUpload({ orderId, currentProofUrl, onUploaded, disabled = false, guestAccessToken, isRejected = false }: PaymentProofUploadProps) {
  const [isUploading, setIsUploading] = useState(false);
  const [proofUrl, setProofUrl] = useState<string | null>(currentProofUrl || null);
  const [displayUrl, setDisplayUrl] = useState<string | null>(null);
  const [previewUnavailable, setPreviewUnavailable] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    let active = true;
    setPreviewUnavailable(false);
    setDisplayUrl(null);
    if (proofUrl) {
      getPaymentProofSignedUrl(proofUrl).then((u) => {
        if (active) {
          setDisplayUrl(u);
          setPreviewUnavailable(!u);
        }
      }).catch((err) => {
        reportObservability('upload', 'payment_proof_preview_failed', 'warn', { hasOrderId: Boolean(orderId) }, err);
        if (active) setPreviewUnavailable(true);
      });
    } else {
      setDisplayUrl(null);
      setPreviewUnavailable(false);
    }
    return () => { active = false; };
  }, [orderId, proofUrl]);

  const handleFile = async (file: File) => {
    const error = validateFile(file, 5);
    if (error) {
      reportObservability('upload', 'payment_proof_validation_failed', 'warn', { hasOrderId: Boolean(orderId) }, new Error(error));
      toast.error(error);
      return;
    }

    setIsUploading(true);
    try {
      const compressedFile = await compressImage(file);
      const tokenHash = guestAccessToken ? await sha256Hex(guestAccessToken) : null;
      const result = await uploadFile({
        bucket: 'payment-proofs',
        path: tokenHash ? `orders/${orderId}/${tokenHash}` : `orders/${orderId}`,
        file: compressedFile,
      });

      if (result.error) {
        reportObservability('upload', 'payment_proof_storage_failed', 'error', { hasOrderId: Boolean(orderId) }, new Error(result.error));
        toast.error(result.error);
        return;
      }

      if (!result.path) {
        const message = 'Bukti pembayaran diproses, tetapi lokasi file tidak ditemukan. Silakan coba lagi.';
        reportObservability('upload', 'payment_proof_storage_incomplete', 'error', { hasOrderId: Boolean(orderId) });
        toast.error(message);
        return;
      }

      // Store the bucket-relative object path. The bucket is private, so the
      // merchant/admin must resolve it through a signed URL instead of
      // relying on a public URL that may stop working after bucket hardening.
      const storedProofPath = result.path;
      const { error: updateError } = guestAccessToken
        ? await supabase.rpc('guest_submit_payment_proof', {
            p_order_id: orderId,
            p_guest_access_token: guestAccessToken,
            p_payment_proof_url: storedProofPath,
          })
        : await supabase.rpc('buyer_submit_payment_proof', {
            p_order_id: orderId,
            p_payment_proof_url: storedProofPath,
          });

      if (updateError) {
        await deleteFile('payment-proofs', result.path);
        reportObservability('upload', 'payment_proof_order_update_failed', 'error', { hasOrderId: Boolean(orderId) }, updateError);
        toast.error('Gagal menyimpan bukti pembayaran');
        return;
      }

      setProofUrl(storedProofPath);
      onUploaded(storedProofPath);
      reportObservability('upload', 'payment_proof_uploaded', 'info', { hasOrderId: Boolean(orderId) });
      toast.success('Bukti pembayaran berhasil diupload');
    } catch (err) {
      reportObservability('upload', 'payment_proof_upload_failed', 'error', { hasOrderId: Boolean(orderId) }, err);
      toast.error('Gagal mengupload bukti pembayaran');
    } finally {
      setIsUploading(false);
    }
  };

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) handleFile(file);
    if (inputRef.current) inputRef.current.value = '';
  };

  return (
    <div className="space-y-3">
      <input
        ref={inputRef}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        onChange={handleInputChange}
        disabled={disabled || isUploading}
        className="hidden"
      />

      {proofUrl ? (
        <div className="space-y-3">
          <div className="relative rounded-lg overflow-hidden border border-border">
            {displayUrl ? (
              <img src={displayUrl} alt="Bukti pembayaran" className="w-full h-48 object-cover" />
            ) : (
              <div className="flex h-48 items-center justify-center bg-muted px-6 text-center text-sm text-muted-foreground">
                {previewUnavailable ? 'Pratinjau bukti belum tersedia. Coba lagi.' : 'Memuat pratinjau bukti pembayaran...'}
              </div>
            )}
            <div className="absolute top-2 left-2">
              <div className={cn('flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium text-white', isRejected ? 'bg-destructive/90' : 'bg-success/90')}>
                {isRejected ? <XCircle className="h-3 w-3" /> : <CheckCircle className="h-3 w-3" />}
                {isRejected ? 'Ditolak — unggah ulang' : 'Terupload'}
              </div>
            </div>
          </div>
          {!disabled && (
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="w-full"
              onClick={() => inputRef.current?.click()}
              disabled={isUploading}
            >
              {isUploading ? (
                <Loader2 className="h-4 w-4 mr-2 animate-spin" />
              ) : (
                <Upload className="h-4 w-4 mr-2" />
              )}
              Ganti Bukti Pembayaran
            </Button>
          )}
        </div>
      ) : (
        <div
          onClick={() => !disabled && !isUploading && inputRef.current?.click()}
          className={cn(
            'border-2 border-dashed rounded-lg p-6 text-center cursor-pointer transition-all',
            'hover:border-primary/50 hover:bg-primary/5',
            disabled && 'opacity-50 cursor-not-allowed',
          )}
        >
          {isUploading ? (
            <div className="flex flex-col items-center gap-2">
              <Loader2 className="h-8 w-8 animate-spin text-primary" />
              <p className="text-sm text-muted-foreground">Mengupload...</p>
            </div>
          ) : (
            <div className="flex flex-col items-center gap-2">
              <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center">
                <Upload className="h-6 w-6 text-primary" />
              </div>
              <p className="text-sm font-medium">Upload Bukti Pembayaran</p>
              <p className="text-xs text-muted-foreground">
                Foto struk transfer / screenshot pembayaran
              </p>
              <p className="text-xs text-muted-foreground">JPG, PNG, WebP • Maks. 5MB</p>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
