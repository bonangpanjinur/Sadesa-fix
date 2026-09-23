import { useState, useEffect } from 'react';
import { X, Download, Smartphone } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { usePWA } from '@/hooks/usePWA';
import { Link } from 'react-router-dom';

const DISMISS_KEY = 'pwa-install-dismissed';
const DISMISS_DAYS = 7;

export function InstallBanner() {
  const { canInstall, isInstalled, installApp } = usePWA();
  const [dismissed, setDismissed] = useState(false);
  const [showBanner, setShowBanner] = useState(false);

  useEffect(() => {
    try {
      const dismissedAt = localStorage.getItem(DISMISS_KEY);
      if (dismissedAt) {
        const daysSinceDismissed = (Date.now() - new Date(dismissedAt).getTime()) / (1000 * 60 * 60 * 24);
        if (daysSinceDismissed < DISMISS_DAYS) setDismissed(true);
      }
    } catch {
      // Storage can be unavailable in private browsing; the prompt remains usable.
    }

    // Do not compete with the first meaningful interaction or first paint.
    const timer = window.setTimeout(() => setShowBanner(true), 10000);
    return () => window.clearTimeout(timer);
  }, []);

  const handleDismiss = () => {
    setDismissed(true);
    try {
      localStorage.setItem(DISMISS_KEY, new Date().toISOString());
    } catch {
      // Ignore storage errors; this dismissal still applies for the current visit.
    }
  };

  const handleInstall = async () => {
    const success = await installApp();
    if (success) handleDismiss();
  };

  if (isInstalled || dismissed || !showBanner) return null;

  return (
    <aside
      aria-label="Ajakan memasang aplikasi SaDesa"
      className="pointer-events-none fixed inset-x-0 bottom-[calc(5.75rem+env(safe-area-inset-bottom))] z-40 px-4 sm:bottom-5"
    >
      <div className="pointer-events-auto mx-auto max-w-[min(31rem,calc(100vw-2rem))] rounded-2xl border border-border bg-card p-4 shadow-lg">
        <div className="flex items-start gap-3">
          <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-primary/10">
            <Smartphone className="h-6 w-6 text-primary" aria-hidden="true" />
          </div>
          <div className="min-w-0 flex-1">
            <h2 className="text-sm font-semibold text-foreground">Install Aplikasi SaDesa</h2>
            <p className="mt-0.5 text-xs text-muted-foreground">Akses lebih cepat langsung dari homescreen</p>
            <div className="mt-3 flex gap-2">
              {canInstall ? (
                <Button size="sm" onClick={handleInstall} className="h-9 text-xs">
                  <Download className="mr-1.5 h-3.5 w-3.5" aria-hidden="true" /> Install
                </Button>
              ) : (
                <Button asChild size="sm" className="h-9 text-xs"><Link to="/install">Cara Install</Link></Button>
              )}
              <Button size="sm" variant="ghost" onClick={handleDismiss} className="h-9 text-xs">Nanti</Button>
            </div>
          </div>
          <Button type="button" variant="ghost" size="icon" onClick={handleDismiss} className="h-8 w-8 shrink-0 text-muted-foreground" aria-label="Tutup prompt instalasi">
            <X className="h-4 w-4" aria-hidden="true" />
          </Button>
        </div>
      </div>
    </aside>
  );
}
