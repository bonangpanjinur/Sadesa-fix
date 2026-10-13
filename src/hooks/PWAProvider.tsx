import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { allowsPwaDeviceRegistration, canRegisterPwaDeviceForSession, heartbeatPwaDevice, registerPwaDevice, shouldForcePwaDeviceLogout, type PwaDeviceSession } from '@/lib/pwaDevice';
import { PWAContext, type PWAContextValue } from './PWAContext';
import { reportObservability } from '@/lib/observability';
import { supabase } from '@/integrations/supabase/client';
import { isPendingServiceWorkerUpdate, requestPwaUpdate } from '@/lib/pwaUpdate';
import { useAuth } from '@/contexts/AuthContext';
import { usePOS } from '@/contexts/POSContext';

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed'; platform: string }>;
}

interface PWAStatus {
  isInstallable: boolean;
  isInstalled: boolean;
  isOnline: boolean;
  isUpdateAvailable: boolean;
  isUpdating: boolean;
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
  const { user } = useAuth();
  const { tenant, posEnabled, posRole, posRoleLoading, loading: posLoading } = usePOS();
  const pwaDeviceScope = useMemo(() => {
    if (!canRegisterPwaDeviceForSession({
      userId: user?.id,
      tenantId: tenant?.id,
      posRole,
      posEnabled,
      posLoading,
      posRoleLoading,
    }) || !user?.id || !tenant?.id || !posRole) return null;

    return {
      key: `${user.id}:${tenant.id}`,
      userId: user.id,
      tenantId: tenant.id,
      posRole,
    };
  }, [user?.id, tenant?.id, posRole, posEnabled, posLoading, posRoleLoading]);
  const [deferredPrompt, setDeferredPrompt] = useState<BeforeInstallPromptEvent | null>(null);
  const [status, setStatus] = useState<PWAStatus>({
    isInstallable: false,
    isInstalled: false,
    isOnline: navigator.onLine,
    isUpdateAvailable: false,
    isUpdating: false,
    device: null,
    deviceRevoked: false,
  });
  const registrationInFlight = useRef(new Map<string, Promise<PwaDeviceSession | null>>());
  const activeDeviceScope = useRef<string | null>(null);
  const deviceHeartbeatEnabled = useRef(false);
  const forcedLogoutStarted = useRef(false);
  const heartbeatTimer = useRef<ReturnType<typeof setInterval> | null>(null);

  const heartbeat = useCallback(async (syncAt?: string | null) => {
    if (!deviceHeartbeatEnabled.current) return null;
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) return null;

    const device = await heartbeatPwaDevice(syncAt);
    if (!device) return null;
    setStatus((prev) => ({ ...prev, device, deviceRevoked: device.status === 'revoked' }));
    if (shouldForcePwaDeviceLogout(device.status) && !forcedLogoutStarted.current) {
      forcedLogoutStarted.current = true;
      reportObservability('device', 'device_revoked_forced_logout', 'warn', { deviceId: device.id });
      await supabase.auth.signOut({ scope: 'local' });
      window.location.assign('/auth?reason=device-revoked');
    }
    return device;
  }, []);

  const registerForSession = useCallback(async (userId: string, tenantId?: string | null) => {
    const scopeKey = `${userId}:${tenantId ?? ''}`;
    const inFlight = registrationInFlight.current.get(scopeKey);
    if (inFlight) return inFlight;

    const registration = registerPwaDevice(tenantId)
      .then((device) => {
        if (device && activeDeviceScope.current === scopeKey) {
          setStatus((prev) => ({ ...prev, device, deviceRevoked: device.status === 'revoked' }));
        }
        return device;
      })
      .catch((error: unknown) => {
        reportObservability('device', 'register_failed', 'warn', { hasTenant: Boolean(tenantId) }, error);
        return null;
      })
      .finally(() => {
        if (registrationInFlight.current.get(scopeKey) === registration) {
          registrationInFlight.current.delete(scopeKey);
        }
      });

    registrationInFlight.current.set(scopeKey, registration);
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
      // A controller change also happens during first install; it is not proof
      // of an update. An approved update clears its prompt after activation.
      setStatus((prev) => ({ ...prev, isUpdateAvailable: false }));
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
        setStatus((prev) => ({
          ...prev,
          isUpdateAvailable: isPendingServiceWorkerUpdate(
            registration.waiting?.state,
            Boolean(registration.waiting),
            Boolean(navigator.serviceWorker.controller),
          ),
        }));
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
              if (isPendingServiceWorkerUpdate(
                newWorker.state,
                registration.waiting === newWorker,
                Boolean(navigator.serviceWorker.controller),
              )) {
                setStatus((prev) => ({ ...prev, isUpdateAvailable: true }));
              }
            });
          }
        });
      }).catch((error: unknown) => reportObservability('device', 'service_worker_registration_failed', 'warn', {}, error));
    }
    document.addEventListener('visibilitychange', handleVisibilityChange);
    window.addEventListener('focus', handleWindowFocus);

    return () => {
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
  }, [heartbeat, stopHeartbeat]);

  useEffect(() => {
    if (!pwaDeviceScope) {
      activeDeviceScope.current = null;
      deviceHeartbeatEnabled.current = false;
      stopHeartbeat();
      setStatus((prev) => (prev.device || prev.deviceRevoked
        ? { ...prev, device: null, deviceRevoked: false }
        : prev));
      return;
    }

    const scope = pwaDeviceScope;
    let cancelled = false;
    activeDeviceScope.current = scope.key;
    deviceHeartbeatEnabled.current = false;
    stopHeartbeat();
    forcedLogoutStarted.current = false;
    setStatus((prev) => ({ ...prev, device: null, deviceRevoked: false }));

    const registerWhenEntitled = async () => {
      try {
        const { data: merchant, error: merchantError } = await supabase
          .from('merchants')
          .select('id')
          .eq('user_id', scope.userId)
          .maybeSingle();
        if (merchantError) throw merchantError;

        if (merchant?.id) {
          const { data, error } = await supabase.rpc('get_subscription_entitlement' as never, {
            p_merchant_id: merchant.id,
            p_feature_key: 'pos_devices',
          } as never);
          if (error) throw error;
          if (!allowsPwaDeviceRegistration(data)) {
            reportObservability('device', 'register_skipped', 'info', {
              hasTenant: true,
              reason: 'pos_device_entitlement_disabled',
            });
            return;
          }
        }

        if (cancelled || activeDeviceScope.current !== scope.key) return;
        const device = await registerForSession(scope.userId, scope.tenantId);
        if (cancelled || activeDeviceScope.current !== scope.key || !device) return;
        deviceHeartbeatEnabled.current = true;
        startHeartbeat();
      } catch (error: unknown) {
        if (!cancelled) {
          reportObservability('device', 'register_preflight_failed', 'warn', { hasTenant: true }, error);
        }
      }
    };

    void registerWhenEntitled();
    return () => {
      cancelled = true;
      if (activeDeviceScope.current === scope.key) {
        activeDeviceScope.current = null;
        deviceHeartbeatEnabled.current = false;
      }
      stopHeartbeat();
    };
  }, [pwaDeviceScope, registerForSession, startHeartbeat, stopHeartbeat]);

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

  const updateApp = useCallback(async () => {
    if (status.isUpdating) return;
    setStatus((prev) => ({ ...prev, isUpdating: true }));
    try {
      await requestPwaUpdate();
    } catch (error: unknown) {
      setStatus((prev) => ({ ...prev, isUpdating: false }));
      reportObservability('device', 'pwa_update_failed', 'error', {}, error);
    }
  }, [status.isUpdating]);

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
