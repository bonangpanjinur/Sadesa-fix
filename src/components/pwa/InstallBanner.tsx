import { useEffect, useState } from 'react';
import { Download, Smartphone } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { usePWA } from '@/hooks/usePWA';
import { Link, useLocation } from 'react-router-dom';

const DISMISS_KEY = 'pwa-install-dismissed';
const DISMISS_HOURS = 24;
const PROMPT_DELAY_MS = 15000;

function isDismissedRecently(): boolean {
  try {
    const dismissedAt = localStorage.getItem(DISMISS_KEY);
    if (!dismissedAt) return false;
    const dismissedTime = new Date(dismissedAt).getTime();
    if (!Number.isFinite(dismissedTime)) return false;
    return (Date.now() - dismissedTime) / (1000 * 60 * 60) < DISMISS_HOURS;
  } catch {
    return false;
  }
}

export function InstallBanner() {
  const { canInstall, isInstalled, installApp } = usePWA();
  const location = useLocation();
  const [dismissed, setDismissed] = useState(isDismissedRecently);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    // Discovery dan checkout membutuhkan first visit yang tidak terinterupsi.
    // Opsi install tetap tersedia dari halaman /install dan navigasi aplikasi.
    const isFocusedFlow = ['/products', '/cart', '/checkout', '/orders'].some((path) => location.pathname.startsWith(path));
    if (isInstalled || dismissed || location.pathname === '/install' || isFocusedFlow) return;

    // Give the first screen and first meaningful interaction priority, then
    // remind users who have not installed the PWA yet.
    const timer = window.setTimeout(() => setOpen(true), PROMPT_DELAY_MS);
    return () => window.clearTimeout(timer);
  }, [dismissed, isInstalled, location.pathname]);

  useEffect(() => {
    if (isInstalled) setOpen(false);
  }, [isInstalled]);

  const handleDismiss = () => {
    setOpen(false);
    setDismissed(true);
    try {
      localStorage.setItem(DISMISS_KEY, new Date().toISOString());
    } catch {
      // The current visit is still dismissed when storage is unavailable.
    }
  };

  const handleInstall = async () => {
    const success = await installApp();
    if (success) {
      setOpen(false);
      setDismissed(false);
      try {
        localStorage.removeItem(DISMISS_KEY);
      } catch {
        // Ignore storage errors; PWAProvider will update isInstalled.
      }
    }
  };

  if (isInstalled || location.pathname === '/install') return null;

  return (
    <Dialog open={open} onOpenChange={(nextOpen) => {
      if (!nextOpen) handleDismiss();
      else setOpen(true);
    }}>
      <DialogContent className="w-[calc(100%-2rem)] rounded-2xl sm:max-w-md">
        <DialogHeader>
          <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-primary/10 sm:mx-0">
            <Smartphone className="h-7 w-7 text-primary" aria-hidden="true" />
          </div>
          <DialogTitle className="pt-2">Install Aplikasi SaDesa</DialogTitle>
          <DialogDescription>
            Akses lebih cepat dari homescreen, tetap nyaman saat koneksi tidak stabil,
            dan dapatkan pengalaman aplikasi yang lebih ringan.
          </DialogDescription>
        </DialogHeader>
        <DialogFooter className="gap-2 sm:gap-2">
          {canInstall ? (
            <Button onClick={handleInstall} className="w-full sm:w-auto">
              <Download className="mr-2 h-4 w-4" aria-hidden="true" />
              Install Sekarang
            </Button>
          ) : (
            <Button asChild className="w-full sm:w-auto">
              <Link to="/install" onClick={() => setOpen(false)}>Cara Install</Link>
            </Button>
          )}
          <Button type="button" variant="ghost" onClick={handleDismiss} className="w-full sm:w-auto">
            Nanti
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
