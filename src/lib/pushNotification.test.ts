import { beforeEach, describe, expect, it, vi } from 'vitest';

const { getSession } = vi.hoisted(() => ({ getSession: vi.fn() }));

vi.mock('@/integrations/supabase/client', () => ({
  SUPABASE_URL: 'https://push-test.supabase.co',
  supabase: {
    auth: { getSession },
  },
}));

import { subscribeToPush } from './pushNotification';

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
      .mockResolvedValueOnce(new Response(JSON.stringify({ publicKey: 'BEl62iUYgUivxIkv69yViEuiBIa-Ib9-SkvMeAtA3LFgDzkrxZJjSgSnfckjBJuBkr3qBUYIHBQFLXYp5Nksh8U' }), { status: 200 }))
      .mockResolvedValueOnce(new Response('{}', { status: 200 }));

    await expect(subscribeToPush('user-1')).resolves.toBe(true);

    expect(fetchMock).toHaveBeenNthCalledWith(
      1,
      'https://push-test.supabase.co/functions/v1/push-subscription',
      { headers: { Authorization: 'Bearer test-token' } },
    );
    expect(fetchMock.mock.calls[1][1]).toMatchObject({
      method: 'POST',
      headers: expect.objectContaining({ Authorization: 'Bearer test-token' }),
    });
  });

  it('returns false when the backend rejects persistence instead of claiming activation succeeded', async () => {
    vi.spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(new Response(JSON.stringify({ publicKey: 'BEl62iUYgUivxIkv69yViEuiBIa-Ib9-SkvMeAtA3LFgDzkrxZJjSgSnfckjBJuBkr3qBUYIHBQFLXYp5Nksh8U' }), { status: 200 }))
      .mockResolvedValueOnce(new Response('{}', { status: 500 }));

    await expect(subscribeToPush('user-1')).resolves.toBe(false);
  });
});
