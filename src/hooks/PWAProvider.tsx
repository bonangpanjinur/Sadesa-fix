import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { heartbeatPwaDevice, registerPwaDevice, type PwaDeviceSession } from '@/lib/pwaDevice';
import { PWAContext, type PWAContextValue } from './PWAContext';
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

const HEARTBEAT_INTERVAL_MS = 60_000;

function usePWAController(): PWAContextValue {
  const [deferredPrompt, setDeferredPrompt] = useState<BeforeInstallPromptEvent | null>(null);
  const [status, setStatus] = useState<PWAStatus>({
    isInstallable: false,
    isInstalled: false,
    isOnline: navigator.onLine,
    isUpdateAvailable: false,
    device: null,
    deviceRevoked: false,
  });
  const registrationInFlight = useRef<Promise<PwaDeviceSession | null> | null>(null);
  const heartbeatTimer = useRef<ReturnType<typeof setInterval> | null>(null);

  const heartbeat = useCallback(async (syncAt?: string | null) => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) return null;

    const device = await heartbeatPwaDevice(syncAt);
    if (!device) return null;
    setStatus((prev) => ({ ...prev, device, deviceRevoked: device.status === 'revoked' }));
    return device;
  }, []);

  const registerForSession = useCallback(async (tenantId?: string | null) => {
    if (registrationInFlight.current) return registrationInFlight.current;

    const registration = registerPwaDevice(tenantId)
      .then((device) => {
        if (device) {
          setStatus((prev) => ({ ...prev, device, deviceRevoked: device.status === 'revoked' }));
        }
        return device;
      })
      .catch((error: unknown) => {
        reportObservability('device', 'register_failed', 'warn', { hasTenant: Boolean(tenantId) }, error);
        return null;
      })
      .finally(() => {
        registrationInFlight.current = null;
      });

    registrationInFlight.current = registration;
    return registration;
  }, []);

  const startHeartbeat = useCallback(() => {
    if (!heartbeatTimer.current) {
      heartbeatTimer.current = setInterval(() => { void heartbeat(); }, HEARTBEAT_INTERVAL_MS);
    }
  }, [heartbeat]);

  const stopHeartbeat = useCallback(() => {
    if (heartbeatTimer.current) {
      clearInterval(heartbeatTimer.current);
      heartbeatTimer.current = null;
    }
  }, []);

  useEffect(() => {
    const isStandalone = window.matchMedia('(display-mode: standalone)').matches;
    const isIOSInstalled = (navigator as Navigator & { standalone?: boolean }).standalone === true;
    setStatus((prev) => ({ ...prev, isInstalled: isStandalone || isIOSInstalled }));

    const handleBeforeInstallPrompt = (event: Event) => {
      event.preventDefault();
      setDeferredPrompt(event as BeforeInstallPromptEvent);
      setStatus((prev) => ({ ...prev, isInstallable: true }));
    };
    const handleAppInstalled = () => {
      setDeferredPrompt(null);
      setStatus((prev) => ({ ...prev, isInstallable: false, isInstalled: true }));
      reportObservability('device', 'pwa_installed');
    };
    const handleOnline = () => {
      setStatus((prev) => ({ ...prev, isOnline: true }));
      void heartbeat();
    };
    const handleOffline = () => {
      setStatus((prev) => ({ ...prev, isOnline: false }));
      reportObservability('offline_sync', 'network_offline', 'warn');
    };

    window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
    window.addEventListener('appinstalled', handleAppInstalled);
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    if ('serviceWorker' in navigator) {
      void navigator.serviceWorker.getRegistration().then((registration) => {
        if (!registration) return;
        registration.addEventListener('updatefound', () => {
          const newWorker = registration.installing;
          if (newWorker) {
            newWorker.addEventListener('statechange', () => {
              if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
                setStatus((prev) => ({ ...prev, isUpdateAvailable: true }));
              }
            });
          }
        });
      }).catch((error: unknown) => reportObservability('device', 'service_worker_registration_failed', 'warn', {}, error));
    }

    let cancelled = false;
    const handleSession = async (session: { user?: { id: string } } | null) => {
      if (cancelled) return;
      if (!session?.user) {
        stopHeartbeat();
        setStatus((prev) => ({ ...prev, device: null, deviceRevoked: false }));
        return;
      }
      await registerForSession();
      if (!cancelled) startHeartbeat();
    };

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      void handleSession(session);
    });
    void supabase.auth.getSession().then(({ data: { session } }) => handleSession(session)).catch((error: unknown) => {
      if (!cancelled) reportObservability('device', 'session_check_failed', 'warn', {}, error);
    });

    return () => {
      cancelled = true;
      subscription.unsubscribe();
      stopHeartbeat();
      window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
      window.removeEventListener('appinstalled', handleAppInstalled);
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, [heartbeat, registerForSession, startHeartbeat, stopHeartbeat]);

  const installApp = useCallback(async () => {
    if (!deferredPrompt) return false;
    try {
      await deferredPrompt.prompt();
      const { outcome } = await deferredPrompt.userChoice;
      if (outcome === 'accepted') {
        setDeferredPrompt(null);
        setStatus((prev) => ({ ...prev, isInstallable: false }));
        return true;
      }
      return false;
    } catch (error: unknown) {
      reportObservability('device', 'pwa_install_failed', 'error', {}, error);
      return false;
    }
  }, [deferredPrompt]);

  const updateApp = useCallback(() => {
    if ('serviceWorker' in navigator) {
      void navigator.serviceWorker.ready.then((registration) => {
        registration.waiting?.postMessage({ type: 'SKIP_WAITING' });
        window.location.reload();
      }).catch((error: unknown) => reportObservability('device', 'pwa_update_failed', 'error', {}, error));
    }
  }, []);

  return useMemo(() => ({
    ...status,
    heartbeat,
    installApp,
    updateApp,
    canInstall: status.isInstallable && !status.isInstalled,
  }), [heartbeat, installApp, status, updateApp]);
}

export function PWAProvider({ children }: { children: React.ReactNode }) {
  const value = usePWAController();
  return <PWAContext.Provider value={value}>{children}</PWAContext.Provider>;
}

