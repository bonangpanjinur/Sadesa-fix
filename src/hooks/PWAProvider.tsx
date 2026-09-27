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
const SERVICE_WORKER_UPDATE_INTERVAL_MS = 30 * 60 * 1000;
const BACKGROUND_SYNC_TAG = 'sadesa-background-sync';
const PERIODIC_SYNC_TAG = 'sadesa-periodic-refresh';

type SyncRegistration = ServiceWorkerRegistration & {
  sync?: {
    register: (tag: string) => Promise<void>;
  };
  periodicSync?: {
    getTags: () => Promise<string[]>;
    register: (tag: string, options: { minInterval: number }) => Promise<void>;
  };
};

async function registerPwaSyncCapabilities(registration: ServiceWorkerRegistration) {
  const syncRegistration = registration as SyncRegistration;

  if (syncRegistration.sync) {
    try {
      await syncRegistration.sync.register(BACKGROUND_SYNC_TAG);
    } catch (error: unknown) {
      // Background Sync is an optional browser capability. Some browsers
      // expose the API but reject registration when permission is unavailable.
      // Offline queue processing still works without this best-effort wake-up.
      if ((error as DOMException | undefined)?.name !== 'NotAllowedError') throw error;
      reportObservability('offline_sync', 'background_sync_unavailable', 'info');
    }
  }

  if (syncRegistration.periodicSync) {
    try {
      const tags = await syncRegistration.periodicSync.getTags();
      if (!tags.includes(PERIODIC_SYNC_TAG)) {
        await syncRegistration.periodicSync.register(PERIODIC_SYNC_TAG, {
          minInterval: 24 * 60 * 60 * 1000,
        });
      }
    } catch (error: unknown) {
      if ((error as DOMException | undefined)?.name !== 'NotAllowedError') throw error;
      reportObservability('offline_sync', 'periodic_sync_unavailable', 'info');
    }
  }
}

async function checkForServiceWorkerUpdate() {
  if (!('serviceWorker' in navigator)) return;

  try {
    const registration = await navigator.serviceWorker.ready;
    await registration.update();
  } catch (error: unknown) {
    reportObservability('device', 'service_worker_update_check_failed', 'warn', {}, error);
  }
}

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
    const standaloneMedia = window.matchMedia('(display-mode: standalone)');
    const detectInstalled = () => {
      const isStandalone = standaloneMedia.matches;
      const isIOSInstalled = (navigator as Navigator & { standalone?: boolean }).standalone === true;
      setStatus((prev) => ({ ...prev, isInstalled: isStandalone || isIOSInstalled }));
    };

    detectInstalled();
    // A user may install from another tab or return from the browser's
    // install flow without firing `appinstalled` in this document. Recheck
    // when display mode or visibility changes so the reminder closes and is
    // not shown again after installation.
    const handleDisplayModeChange = () => detectInstalled();
    const handleInstallVisibilityChange = () => {
      if (document.visibilityState === 'visible') detectInstalled();
    };
    standaloneMedia.addEventListener?.('change', handleDisplayModeChange);
    document.addEventListener('visibilitychange', handleInstallVisibilityChange);

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
      void checkForServiceWorkerUpdate();
    };
    const handleOffline = () => {
      setStatus((prev) => ({ ...prev, isOnline: false }));
      reportObservability('offline_sync', 'network_offline', 'warn');
    };

    window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
    window.addEventListener('appinstalled', handleAppInstalled);
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    let updateCheckTimer: ReturnType<typeof setInterval> | null = null;

    const handleControllerChange = () => {
      // A worker update must not interrupt an active form, checkout, chat, or
      // admin operation. The explicit UpdatePrompt button calls updateApp()
      // when the user is ready to reload.
      setStatus((prev) => ({ ...prev, isUpdateAvailable: true }));
    };

    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') {
        void checkForServiceWorkerUpdate();
      }
    };

    const handleWindowFocus = () => {
      void checkForServiceWorkerUpdate();
    };

    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.addEventListener('controllerchange', handleControllerChange);
      void navigator.serviceWorker.ready.then((registration) => {
        void registerPwaSyncCapabilities(registration).catch((error: unknown) => {
          reportObservability('offline_sync', 'capability_registration_failed', 'warn', {}, error);
        });

        // A browser may keep an installed PWA suspended for hours. Check now,
        // when it becomes visible, and periodically while it stays open.
        void registration.update().catch((error: unknown) => {
          reportObservability('device', 'service_worker_update_check_failed', 'warn', {}, error);
        });
        updateCheckTimer = setInterval(() => {
          if (document.visibilityState === 'visible') {
            void registration.update().catch((error: unknown) => {
              reportObservability('device', 'service_worker_update_check_failed', 'warn', {}, error);
            });
          }
        }, SERVICE_WORKER_UPDATE_INTERVAL_MS);

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
    document.addEventListener('visibilitychange', handleVisibilityChange);
    window.addEventListener('focus', handleWindowFocus);

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
      standaloneMedia.removeEventListener?.('change', handleDisplayModeChange);
      document.removeEventListener('visibilitychange', handleInstallVisibilityChange);
      window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
      window.removeEventListener('appinstalled', handleAppInstalled);
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      window.removeEventListener('focus', handleWindowFocus);
      navigator.serviceWorker?.removeEventListener('controllerchange', handleControllerChange);
      if (updateCheckTimer) {
        clearInterval(updateCheckTimer);
        updateCheckTimer = null;
      }
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
