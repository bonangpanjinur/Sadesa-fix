import { useEffect, useState } from 'react';
import { Download, Smartphone } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { usePWA } from '@/hooks/usePWA';
import { Link, useLocation } from 'react-router-dom';

const DISMISS_KEY = 'pwa-install-dismissed';
const DISMISS_HOURS = 24;
const PROMPT_DELAY_MS = 45000;

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

    // Let visitors explore first; the reminder below is non-modal and does not
    // block the storefront or take focus away from the current task.
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

  if (!open) return null;

  return (
    <aside
      aria-labelledby="install-prompt-title"
      aria-live="polite"
      className="fixed inset-x-4 bottom-[calc(5.5rem+env(safe-area-inset-bottom))] z-[65] mx-auto max-w-md rounded-2xl border border-emerald-100 bg-white p-4 shadow-[0_16px_40px_-18px_rgba(1,87,48,0.35)]"
    >
      <div className="flex items-start gap-3">
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
          <Smartphone className="h-5 w-5" aria-hidden="true" />
        </span>
        <div className="min-w-0 flex-1">
          <h2 id="install-prompt-title" className="text-sm font-bold text-foreground">Install Aplikasi SaDesa</h2>
          <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
            Akses lebih cepat dari homescreen dan tetap nyaman saat koneksi tidak stabil.
          </p>
        </div>
        <Button type="button" variant="ghost" size="icon" onClick={handleDismiss} className="-mr-2 -mt-2 h-8 w-8 shrink-0" aria-label="Tutup pengingat instalasi">
          <span aria-hidden="true">×</span>
        </Button>
      </div>
      <div className="mt-3 flex gap-2">
        {canInstall ? (
          <Button onClick={handleInstall} className="flex-1">
            <Download className="mr-2 h-4 w-4" aria-hidden="true" />
            Install Sekarang
          </Button>
        ) : (
          <Button asChild className="flex-1">
            <Link to="/install" onClick={() => setOpen(false)}>Cara Install</Link>
          </Button>
        )}
        <Button type="button" variant="outline" onClick={handleDismiss}>Nanti</Button>
      </div>
    </aside>
  );
}
