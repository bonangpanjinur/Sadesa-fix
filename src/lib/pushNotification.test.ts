import { beforeEach, describe, expect, it, vi } from 'vitest';

const { getSession, from } = vi.hoisted(() => ({ getSession: vi.fn(), from: vi.fn() }));

vi.mock('@/integrations/supabase/client', () => ({
  SUPABASE_URL: 'https://push-test.supabase.co',
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_push_test',
  supabase: {
    auth: { getSession },
    from,
  },
}));

import {
  getLastPushError,
  getSubscriptionStatus,
  hasActiveBrowserPushSubscription,
  replacePushSubscription,
  subscribeToPush,
  waitForPushServiceWorkerRegistration,
} from './pushNotification';

describe('subscribeToPush', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    getSession.mockResolvedValue({ data: { session: { access_token: 'test-token' } } });

    Object.defineProperty(window, 'Notification', {
      configurable: true,
      value: { permission: 'granted', requestPermission: vi.fn() },
    });
    Object.defineProperty(window, 'PushManager', { configurable: true, value: class PushManager {} });
    Object.defineProperty(navigator, 'serviceWorker', {
      configurable: true,
      value: {
        ready: Promise.resolve({
          pushManager: {
            getSubscription: vi.fn().mockResolvedValue(null),
            subscribe: vi.fn().mockResolvedValue({
              toJSON: () => ({ endpoint: 'https://push.example/subscription', keys: { p256dh: 'key', auth: 'auth' } }),
            }),
          },
        }),
      },
    });
  });

  it('uses the backend VAPID key and hides the onboarding gate after persistence succeeds', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(new Response(JSON.stringify({ publicKey: 'BEl62iUYgUivxIkv69yViEuiBIa-Ib9-SkvMeAtA3LFgDzkrxZJjSgSnfckjBJuBkr3qBUYIHBQFLXYp5Nksh8U', vapidConfigured: true }), { status: 200 }))
      .mockResolvedValueOnce(new Response('{}', { status: 200 }));

    await expect(subscribeToPush('user-1')).resolves.toBe(true);

    expect(fetchMock).toHaveBeenNthCalledWith(
      1,
      'https://push-test.supabase.co/functions/v1/push-subscription',
      { headers: { apikey: 'sb_publishable_push_test', Authorization: 'Bearer test-token' } },
    );
    expect(fetchMock.mock.calls[1][1]).toMatchObject({
      method: 'POST',
      headers: expect.objectContaining({
        apikey: 'sb_publishable_push_test',
        Authorization: 'Bearer test-token',
      }),
    });
  });

  it('returns false when the backend rejects persistence instead of claiming activation succeeded', async () => {
    vi.spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(new Response(JSON.stringify({ publicKey: 'BEl62iUYgUivxIkv69yViEuiBIa-Ib9-SkvMeAtA3LFgDzkrxZJjSgSnfckjBJuBkr3qBUYIHBQFLXYp5Nksh8U', vapidConfigured: true }), { status: 200 }))
      .mockResolvedValueOnce(new Response('{}', { status: 500 }));

    await expect(subscribeToPush('user-1')).resolves.toBe(false);
  });

  it('does not subscribe when the server reports incomplete VAPID configuration', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({
        publicKey: 'AQID',
        publicKeyConfigured: true,
        privateKeyConfigured: false,
        vapidConfigured: false,
        missingVariables: ['VAPID_PRIVATE_KEY'],
      }), { status: 200 }),
    );
    const registration = await navigator.serviceWorker.ready;

    await expect(subscribeToPush('user-1')).resolves.toBe(false);
    expect(getLastPushError()).toContain('VAPID_PUBLIC_KEY dan VAPID_PRIVATE_KEY');
    expect(registration.pushManager.subscribe).not.toHaveBeenCalled();
    expect(fetchMock).toHaveBeenCalledTimes(1);
    consoleError.mockRestore();
  });

  it('replaces an existing browser subscription when its application server key has rotated', async () => {
    const oldSubscription = {
      endpoint: 'https://push.example/old-subscription',
      options: { applicationServerKey: Uint8Array.of(9, 9, 9).buffer },
      unsubscribe: vi.fn().mockResolvedValue(true),
    };
    const newSubscription = {
      toJSON: () => ({ endpoint: 'https://push.example/new-subscription', keys: { p256dh: 'new-key', auth: 'new-auth' } }),
    };
    const getSubscription = vi.fn().mockResolvedValue(oldSubscription);
    const subscribe = vi.fn().mockResolvedValue(newSubscription);
    Object.defineProperty(navigator, 'serviceWorker', {
      configurable: true,
      value: {
        ready: Promise.resolve({ pushManager: { getSubscription, subscribe } }),
      },
    });
    const fetchMock = vi.spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(new Response(JSON.stringify({ publicKey: 'AQID', vapidConfigured: true }), { status: 200 }))
      .mockResolvedValueOnce(new Response('{}', { status: 200 }))
      .mockResolvedValueOnce(new Response('{}', { status: 200 }));

    await expect(subscribeToPush('user-1')).resolves.toBe(true);

    expect(oldSubscription.unsubscribe).toHaveBeenCalledOnce();
    expect(fetchMock.mock.calls[1][1]).toMatchObject({
      method: 'DELETE',
      body: JSON.stringify({ endpoint: oldSubscription.endpoint }),
    });
    expect(subscribe).toHaveBeenCalledWith({
      userVisibleOnly: true,
      applicationServerKey: Uint8Array.of(1, 2, 3),
    });
    expect(fetchMock.mock.calls[2][1]).toMatchObject({ method: 'POST' });
  });

  it('allows a manual refresh to replace an existing subscription when the browser hides its key', async () => {
    const oldSubscription = {
      endpoint: 'https://push.example/old-subscription',
      options: { applicationServerKey: null },
      unsubscribe: vi.fn().mockResolvedValue(true),
    };
    const getSubscription = vi.fn().mockResolvedValue(oldSubscription);
    const subscribe = vi.fn().mockResolvedValue({
      toJSON: () => ({ endpoint: 'https://push.example/new-subscription', keys: { p256dh: 'new-key', auth: 'new-auth' } }),
    });
    Object.defineProperty(navigator, 'serviceWorker', {
      configurable: true,
      value: {
        ready: Promise.resolve({ pushManager: { getSubscription, subscribe } }),
      },
    });
    vi.spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(new Response(JSON.stringify({ publicKey: 'AQID', vapidConfigured: true }), { status: 200 }))
      .mockResolvedValueOnce(new Response('{}', { status: 200 }))
      .mockResolvedValueOnce(new Response('{}', { status: 200 }));

    await expect(replacePushSubscription('user-1')).resolves.toBe(true);
    expect(oldSubscription.unsubscribe).toHaveBeenCalledOnce();
    expect(subscribe).toHaveBeenCalledOnce();
  });

  it('returns an actionable error when a service worker never becomes ready', async () => {
    vi.useFakeTimers();
    try {
      Object.defineProperty(navigator, 'serviceWorker', {
        configurable: true,
        value: { ready: new Promise<ServiceWorkerRegistration>(() => {}) },
      });

      const result = waitForPushServiceWorkerRegistration(250);
      const rejection = expect(result).rejects.toThrow('Service worker belum aktif');
      await vi.advanceTimersByTimeAsync(250);
      await rejection;
    } finally {
      vi.useRealTimers();
    }
  });

  it('fails activation clearly without requesting a VAPID key when the service worker is missing', async () => {
    vi.useFakeTimers();
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});
    const fetchMock = vi.spyOn(globalThis, 'fetch');
    try {
      Object.defineProperty(navigator, 'serviceWorker', {
        configurable: true,
        value: { ready: new Promise<ServiceWorkerRegistration>(() => {}) },
      });

      const activation = subscribeToPush('user-1');
      await vi.advanceTimersByTimeAsync(10_000);

      await expect(activation).resolves.toBe(false);
      expect(getLastPushError()).toContain('Service worker belum aktif');
      expect(fetchMock).not.toHaveBeenCalled();
    } finally {
      consoleError.mockRestore();
      vi.useRealTimers();
    }
  });

  it('includes gateway auth details when the VAPID-key request is rejected', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({ message: 'Invalid JWT' }), { status: 401 }),
    );
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});

    await expect(subscribeToPush('user-1')).resolves.toBe(false);
    expect(getLastPushError()).toContain('Server push tidak siap (401): Invalid JWT');
    expect(globalThis.fetch).toHaveBeenCalledWith(
      'https://push-test.supabase.co/functions/v1/push-subscription',
      { headers: { apikey: 'sb_publishable_push_test', Authorization: 'Bearer test-token' } },
    );
    consoleError.mockRestore();
  });

  it('recognizes an existing browser subscription when permission is granted', async () => {
    Object.defineProperty(navigator, 'serviceWorker', {
      configurable: true,
      value: {
        ready: Promise.resolve({
          pushManager: { getSubscription: vi.fn().mockResolvedValue({ endpoint: 'https://push.example/subscription' }) },
        }),
      },
    });

    await expect(hasActiveBrowserPushSubscription()).resolves.toBe(true);
  });

  it('propagates backend status errors instead of treating them as an inactive subscription', async () => {
    Object.defineProperty(navigator, 'serviceWorker', {
      configurable: true,
      value: {
        ready: Promise.resolve({
          pushManager: { getSubscription: vi.fn().mockResolvedValue({ endpoint: 'https://push.example/subscription' }) },
        }),
      },
    });
    const query = {
      select: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      maybeSingle: vi.fn().mockResolvedValue({ data: null, error: new Error('status lookup failed') }),
    };
    from.mockReturnValue(query);
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});

    await expect(getSubscriptionStatus('user-1')).rejects.toThrow('status lookup failed');
    consoleError.mockRestore();
  });
});
