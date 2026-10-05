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
import { useAudioPermission } from '@/hooks/useAudioPermission';

export function AudioPermissionModal() {
  const [unsupportedDismissed, setUnsupportedDismissed] = useState(false);
  const {
    isSupported,
    needsPermission,
    isActivating,
    error,
    activate,
  } = useAudioPermission();

  const open = isSupported ? needsPermission : !unsupportedDismissed;

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
          <DialogTitle>{isSupported ? 'Aktifkan Audio' : 'Audio Tidak Tersedia'}</DialogTitle>
          <DialogDescription>
            {isSupported
              ? 'Aktifkan audio agar notifikasi suara aplikasi dapat digunakan.'
              : 'Browser ini tidak mendukung Web Audio API. Gunakan Chrome versi terbaru atau browser modern lainnya.'}
          </DialogDescription>
        </DialogHeader>

        {error && (
          <p role="alert" className="rounded-xl bg-destructive/10 px-3 py-2 text-center text-xs text-destructive">
            {error}
          </p>
        )}

        {isSupported && (
          <DialogFooter className="sm:justify-center">
            <Button type="button" className="min-h-11 w-full rounded-xl font-bold sm:w-auto sm:min-w-56" onClick={() => void activate()} disabled={isActivating}>
              {isActivating ? 'MENGAKTIFKAN...' : 'AKTIFKAN AUDIO'}
            </Button>
          </DialogFooter>
        )}
      </DialogContent>
    </Dialog>
  );
}
