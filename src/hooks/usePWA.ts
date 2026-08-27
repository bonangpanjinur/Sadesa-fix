import { useState, useEffect, useCallback } from 'react';
import { heartbeatPwaDevice, registerPwaDevice, type PwaDeviceSession } from '@/lib/pwaDevice';
import { reportObservability } from '@/lib/observability';
import { supabase } from '@/integrations/supabase/client';

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed'; platform: string }>;
}

interface PWAStatus {
  isInstallable: boolean;
  isInstalled: boolean;
  isOnline: boolean;
  isUpdateAvailable: boolean;
  device: PwaDeviceSession | null;
  deviceRevoked: boolean;
}

export function usePWA(options: { tenantId?: string | null; enableDeviceManagement?: boolean } = {}) {
  const [deferredPrompt, setDeferredPrompt] = useState<BeforeInstallPromptEvent | null>(null);
  const [status, setStatus] = useState<PWAStatus>({
    isInstallable: false,
    isInstalled: false,
    isOnline: navigator.onLine,
    isUpdateAvailable: false,
    device: null,
    deviceRevoked: false,
  });
  const deviceManagementEnabled = options.enableDeviceManagement ?? true;

  const heartbeat = useCallback(async (syncAt?: string | null) => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) return null;

    const device = await heartbeatPwaDevice(syncAt);
    if (!device) return null;
    setStatus((prev) => ({ ...prev, device, deviceRevoked: device.status === 'revoked' }));
    return device;
  }, []);

  useEffect(() => {
    const isStandalone = window.matchMedia('(display-mode: standalone)').matches;
    const isIOSInstalled = (navigator as Navigator & { standalone?: boolean }).standalone === true;
    const isPWA = isStandalone || isIOSInstalled;
    setStatus(prev => ({ ...prev, isInstalled: isPWA }));

    const handleBeforeInstallPrompt = (e: Event) => {
      setDeferredPrompt(e as BeforeInstallPromptEvent);
      setStatus(prev => ({ ...prev, isInstallable: true }));
    };
    const handleAppInstalled = () => {
      setDeferredPrompt(null);
      setStatus(prev => ({ ...prev, isInstallable: false, isInstalled: true }));
      reportObservability('device', 'pwa_installed');
    };
    const handleOnline = () => { setStatus(prev => ({ ...prev, isOnline: true })); void heartbeat(); };
    const handleOffline = () => { setStatus(prev => ({ ...prev, isOnline: false })); reportObservability('offline_sync', 'network_offline', 'warn'); };

    window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
    window.addEventListener('appinstalled', handleAppInstalled);
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.getRegistration().then(registration => {
        if (registration) {
          registration.addEventListener('updatefound', () => {
            const newWorker = registration.installing;
            if (newWorker) newWorker.addEventListener('statechange', () => {
              if (newWorker.state === 'installed' && navigator.serviceWorker.controller) setStatus(prev => ({ ...prev, isUpdateAvailable: true }));
            });
          });
        }
      }).catch((error) => reportObservability('device', 'service_worker_registration_failed', 'warn', {}, error));
    }

    let heartbeatTimer: ReturnType<typeof setInterval> | undefined;
    let cancelled = false;
    if (deviceManagementEnabled) {
      void supabase.auth.getSession().then(async ({ data }) => {
        if (cancelled || !data.session) return;
        const device = await registerPwaDevice(options.tenantId);
        if (!cancelled && device) setStatus(prev => ({ ...prev, device, deviceRevoked: device.status === 'revoked' }));
        if (!cancelled) heartbeatTimer = setInterval(() => { void heartbeat(); }, 60_000);
      }).catch((error: unknown) => {
        if (!cancelled) reportObservability('device', 'session_check_failed', 'warn', {}, error);
      });
    }

    return () => {
      cancelled = true;
      if (heartbeatTimer) clearInterval(heartbeatTimer);
      window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
      window.removeEventListener('appinstalled', handleAppInstalled);
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, [deviceManagementEnabled, heartbeat, options.tenantId]);

  const installApp = async () => {
    if (!deferredPrompt) return false;
    try {
      await deferredPrompt.prompt();
      const { outcome } = await deferredPrompt.userChoice;
      if (outcome === 'accepted') { setDeferredPrompt(null); setStatus(prev => ({ ...prev, isInstallable: false })); return true; }
      return false;
    } catch (error) {
      reportObservability('device', 'pwa_install_failed', 'error', {}, error);
      return false;
    }
  };

  const updateApp = () => {
    if ('serviceWorker' in navigator) navigator.serviceWorker.ready.then(registration => { registration.waiting?.postMessage({ type: 'SKIP_WAITING' }); window.location.reload(); }).catch((error) => reportObservability('device', 'pwa_update_failed', 'error', {}, error));
  };

  return { ...status, heartbeat, installApp, updateApp, canInstall: status.isInstallable && !status.isInstalled };
}
