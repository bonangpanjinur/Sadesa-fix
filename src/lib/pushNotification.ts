import { supabase, SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from '@/integrations/supabase/client';

const PUSH_SUBSCRIPTION_API = `${SUPABASE_URL}/functions/v1/push-subscription`;
let lastPushError: string | null = null;

function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - base64String.length % 4) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = window.atob(base64);
  const outputArray = new Uint8Array(rawData.length);

  for (let index = 0; index < rawData.length; index += 1) {
    outputArray[index] = rawData.charCodeAt(index);
  }
  return outputArray;
}

async function getSessionToken(): Promise<string> {
  const { data } = await supabase.auth.getSession();
  return data.session?.access_token || '';
}

async function readPushErrorDetails(response: Response): Promise<string> {
  try {
    const payload = await response.json() as {
      error?: unknown;
      message?: unknown;
      requestId?: unknown;
    };
    const message = typeof payload.error === 'string'
      ? payload.error
      : typeof payload.message === 'string'
        ? payload.message
        : null;
    const details = [
      message?.slice(0, 200),
      typeof payload.requestId === 'string' ? `request ID ${payload.requestId.slice(0, 100)}` : null,
    ].filter((value): value is string => Boolean(value));
    return details.length > 0 ? `: ${details.join(' — ')}` : '';
  } catch {
    // Keep the HTTP status when the gateway returns a non-JSON error.
    return '';
  }
}

async function getVapidPublicKey(sessionToken: string): Promise<string> {
  const response = await fetch(PUSH_SUBSCRIPTION_API, {
    headers: {
      apikey: SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${sessionToken}`,
    },
  });
  if (!response.ok) {
    throw new Error(`Server push tidak siap (${response.status})${await readPushErrorDetails(response)}`);
  }

  const payload = await response.json() as {
    publicKey?: unknown;
    vapidConfigured?: unknown;
  };
  if (payload.vapidConfigured === false) {
    throw new Error(
      'Konfigurasi VAPID server belum lengkap. Atur VAPID_PUBLIC_KEY dan VAPID_PRIVATE_KEY pada secrets Edge Functions.',
    );
  }
  if (typeof payload.publicKey !== 'string' || payload.publicKey.length === 0) {
    throw new Error('Push subscription endpoint returned no public key');
  }
  return payload.publicKey;
}

function matchesApplicationServerKey(subscription: PushSubscription, expectedKey: Uint8Array): boolean | null {
  const currentKey = subscription.options.applicationServerKey;
  if (!currentKey) return null;

  const currentBytes = new Uint8Array(currentKey);
  return currentBytes.length === expectedKey.length
    && currentBytes.every((value, index) => value === expectedKey[index]);
}

async function removeSubscriptionFromServer(endpoint: string, sessionToken: string): Promise<void> {
  const response = await fetch(PUSH_SUBSCRIPTION_API, {
    method: 'DELETE',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${sessionToken}`,
    },
    body: JSON.stringify({ endpoint }),
  });
  if (!response.ok) {
    throw new Error(`Failed to remove subscription (${response.status})${await readPushErrorDetails(response)}`);
  }
}

async function unsubscribeBrowserSubscription(
  registration: ServiceWorkerRegistration,
  subscription: PushSubscription,
): Promise<void> {
  const unsubscribed = await subscription.unsubscribe();
  if (!unsubscribed && (await registration.pushManager.getSubscription())?.endpoint === subscription.endpoint) {
    throw new Error('Subscription browser tidak dapat dihapus.');
  }
}

export function getLastPushError(): string | null {
  return lastPushError;
}

export async function isPushSupported(): Promise<boolean> {
  return 'Notification' in window && 'serviceWorker' in navigator && 'PushManager' in window;
}

export async function waitForPushServiceWorkerRegistration(timeoutMs = 10_000): Promise<ServiceWorkerRegistration> {
  let timeoutId: number | undefined;
  try {
    return await Promise.race([
      navigator.serviceWorker.ready,
      new Promise<never>((_, reject) => {
        timeoutId = window.setTimeout(() => {
          reject(new Error(
            'Service worker belum aktif. Notifikasi background hanya dapat diuji pada build production atau PWA yang terpasang.',
          ));
        }, timeoutMs);
      }),
    ]);
  } finally {
    if (timeoutId !== undefined) window.clearTimeout(timeoutId);
  }
}

export async function getPushPermission(): Promise<NotificationPermission> {
  if (!('Notification' in window)) return 'denied';
  return Notification.permission;
}

export async function requestPushPermission(): Promise<boolean> {
  if (!('Notification' in window) || Notification.permission === 'denied') return false;
  if (Notification.permission === 'granted') return true;
  return (await Notification.requestPermission()) === 'granted';
}

/**
 * Creates the browser subscription and persists it through the authenticated
 * edge function. Keeping these steps in one path prevents the onboarding gate
 * from using a stale hard-coded VAPID key or a different persistence contract.
 */
export async function subscribeToPush(
  _userId: string,
  options: { forceReplace?: boolean } = {},
): Promise<boolean> {
  lastPushError = null;
  try {
    if (!(await isPushSupported())) {
      lastPushError = 'Browser tidak mendukung push notification.';
      return false;
    }

    const permission = await getPushPermission();
    if (permission === 'denied') {
      lastPushError = 'Izin notifikasi diblokir oleh browser.';
      return false;
    }
    if (permission === 'default' && !(await requestPushPermission())) {
      lastPushError = 'Izin notifikasi belum diberikan.';
      return false;
    }

    const sessionToken = await getSessionToken();
    if (!sessionToken) throw new Error('Sesi login tidak ditemukan. Silakan masuk ulang.');

    const registration = await waitForPushServiceWorkerRegistration();
    const publicKey = await getVapidPublicKey(sessionToken);
    const applicationServerKey = urlBase64ToUint8Array(publicKey);
    let subscription = await registration.pushManager.getSubscription();

    if (subscription && (
      options.forceReplace
      || matchesApplicationServerKey(subscription, applicationServerKey) === false
    )) {
      const oldEndpoint = subscription.endpoint;
      await removeSubscriptionFromServer(oldEndpoint, sessionToken);
      await unsubscribeBrowserSubscription(registration, subscription);
      subscription = null;
    }

    if (!subscription) {
      subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: applicationServerKey as BufferSource,
      });
    }

    const response = await fetch(PUSH_SUBSCRIPTION_API, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: SUPABASE_PUBLISHABLE_KEY,
        Authorization: `Bearer ${sessionToken}`,
      },
      body: JSON.stringify({ subscription: subscription.toJSON() }),
    });
    if (!response.ok) {
      throw new Error(`Subscription belum tersimpan (${response.status})${await readPushErrorDetails(response)}`);
    }

    return true;
  } catch (error) {
    lastPushError = error instanceof Error ? error.message : 'Aktivasi notifikasi gagal.';
    console.error('Error subscribing to push:', error);
    return false;
  }
}

export async function replacePushSubscription(userId: string): Promise<boolean> {
  return subscribeToPush(userId, { forceReplace: true });
}

export async function unsubscribeFromPush(_userId: string): Promise<boolean> {
  try {
    const registration = await waitForPushServiceWorkerRegistration();
    const subscription = await registration.pushManager.getSubscription();
    if (!subscription) return true;

    const sessionToken = await getSessionToken();
    if (!sessionToken) throw new Error('Sesi login tidak ditemukan. Silakan masuk ulang.');
    await removeSubscriptionFromServer(subscription.endpoint, sessionToken);
    await unsubscribeBrowserSubscription(registration, subscription);
    return true;
  } catch (error) {
    console.error('Error unsubscribing from push:', error);
    return false;
  }
}

export async function hasActiveBrowserPushSubscription(): Promise<boolean> {
  try {
    if (!(await isPushSupported()) || (await getPushPermission()) !== 'granted') return false;
    const registration = await waitForPushServiceWorkerRegistration();
    return Boolean(await registration.pushManager.getSubscription());
  } catch (error) {
    console.error('Error checking browser push subscription:', error);
    return false;
  }
}

export async function getSubscriptionStatus(userId: string): Promise<boolean> {
  try {
    if (!(await isPushSupported())) return false;

    const registration = await waitForPushServiceWorkerRegistration();
    const subscription = await registration.pushManager.getSubscription();
    if (!subscription) return false;

    const { data, error } = await supabase
      .from('push_subscriptions' as never)
      .select('id')
      .eq('user_id', userId)
      .eq('endpoint', subscription.endpoint)
      .maybeSingle();

    if (error) throw error;
    return !!data;
  } catch (error) {
    console.error('Error checking push subscription:', error);
    throw error;
  }
}

export function showLocalNotification(title: string, options?: NotificationOptions) {
  if ('Notification' in window && Notification.permission === 'granted') {
    new Notification(title, options);
  }
}
