import { useState } from 'react';
import { AlertTriangle, Volume2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { useAuth } from '@/contexts/AuthContext';
import { useAudioPermission } from '@/hooks/useAudioPermission';

export function AudioPermissionModal() {
  const [unsupportedDismissed, setUnsupportedDismissed] = useState(false);
  const {
    user,
    isMerchant,
    isCourier,
    loading: authLoading,
    rolesLoading,
    merchantRoleRecoveryLoading,
  } = useAuth();
  const {
    isSupported,
    needsPermission,
    isActivating,
    error,
    activate,
  } = useAudioPermission();

  const isOrderOperator = Boolean(user)
    && (isMerchant || isCourier)
    && !authLoading
    && !rolesLoading
    && !merchantRoleRecoveryLoading;
  const open = isOrderOperator && (isSupported ? needsPermission : !unsupportedDismissed);

  return (
    <Dialog open={open} onOpenChange={(nextOpen) => {
      if (!nextOpen && !isSupported) setUnsupportedDismissed(true);
    }}>
      <DialogContent
        className="z-[100] max-w-[calc(100%-2rem)] rounded-2xl sm:max-w-md"
        onEscapeKeyDown={(event) => { if (isSupported) event.preventDefault(); }}
        onPointerDownOutside={(event) => { if (isSupported) event.preventDefault(); }}
        onInteractOutside={(event) => { if (isSupported) event.preventDefault(); }}
      >
        <DialogHeader className="items-center text-center sm:text-center">
          <div className="mb-2 flex h-16 w-16 items-center justify-center rounded-2xl bg-primary/10 text-primary">
            {isSupported ? <Volume2 className="h-8 w-8" aria-hidden="true" /> : <AlertTriangle className="h-8 w-8" aria-hidden="true" />}
          </div>
          <DialogTitle>{isSupported ? 'Aktifkan Alarm Pesanan' : 'Audio Tidak Tersedia'}</DialogTitle>
          <DialogDescription>
            {isSupported
              ? 'Audio di Chrome tidak memiliki halaman izin seperti GPS. Tombol ini adalah langkah aktivasinya: klik untuk mengaktifkan dan menguji suara. Jendela ini tetap terbuka sampai audio aktif.'
              : 'Browser ini tidak mendukung Web Audio API. Gunakan Chrome versi terbaru atau browser modern lainnya.'}
          </DialogDescription>
        </DialogHeader>

        {isSupported && (
          <details className="rounded-xl border px-3 py-2 text-sm">
            <summary className="cursor-pointer font-medium">Suara tes tidak terdengar?</summary>
            <ul className="mt-2 list-disc space-y-1 pl-5 text-xs text-muted-foreground">
              <li>Di Chrome desktop, buka ikon pengaturan situs di samping alamat web, lalu pastikan Suara diizinkan dan tab tidak dibisukan.</li>
              <li>Di Android, buka Chrome ⋮ → Setelan → Setelan situs → Suara, lalu izinkan suara. Periksa juga volume media dan mode senyap.</li>
            </ul>
          </details>
        )}

        {isSupported && (
          <p className="text-center text-xs text-muted-foreground">
            Saat aplikasi ditutup, alarm memerlukan notifikasi Push yang diizinkan. Bunyi push diatur oleh Chrome dan perangkat.
          </p>
        )}

        {error && (
          <p role="alert" className="rounded-xl bg-destructive/10 px-3 py-2 text-center text-xs text-destructive">
            {error}
          </p>
        )}

        {isSupported && (
          <DialogFooter className="sm:justify-center">
            <Button type="button" className="min-h-11 w-full rounded-xl font-bold sm:w-auto sm:min-w-56" onClick={() => void activate()} disabled={isActivating}>
              {isActivating ? 'MENGAKTIFKAN...' : 'AKTIFKAN & UJI SUARA'}
            </Button>
          </DialogFooter>
        )}
      </DialogContent>
    </Dialog>
  );
}
