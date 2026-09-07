/// <reference lib="webworker" />

import { clientsClaim } from 'workbox-core';
import { cleanupOutdatedCaches, precacheAndRoute } from 'workbox-precaching';

declare const self: ServiceWorkerGlobalScope;

precacheAndRoute(self.__WB_MANIFEST);
cleanupOutdatedCaches();
clientsClaim();
self.skipWaiting();

const refreshPublicPwaMetadata = async () => {
  const response = await fetch('/manifest.webmanifest', { cache: 'no-store' });
  if (!response.ok) {
    throw new Error(`Manifest refresh failed with status ${response.status}`);
  }

  const cache = await caches.open('sadesa-pwa-metadata');
  await cache.put('/manifest.webmanifest', response.clone());

  const clients = await self.clients.matchAll({
    type: 'window',
    includeUncontrolled: true,
  });
  for (const client of clients) {
    client.postMessage({
      type: 'SADESA_PWA_SYNC_COMPLETED',
      resource: 'manifest',
    });
  }
};

self.addEventListener('message', (event) => {
  if (event.data?.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

self.addEventListener('sync', (event) => {
  const syncEvent = event as ExtendableEvent & { tag?: string };
  if (syncEvent.tag === 'sadesa-background-sync') {
    syncEvent.waitUntil(refreshPublicPwaMetadata());
  }
});

self.addEventListener('periodicsync', (event) => {
  const periodicEvent = event as ExtendableEvent & { tag?: string };
  if (periodicEvent.tag === 'sadesa-periodic-refresh') {
    periodicEvent.waitUntil(refreshPublicPwaMetadata());
  }
});

self.addEventListener('push', (event) => {
  let data = {
    title: 'Notifikasi Baru',
    body: 'Anda memiliki notifikasi baru',
    icon: '/branding/sadesa-favicon.png',
    url: '/',
  };

  try {
    if (event.data) {
      data = { ...data, ...event.data.json() };
    }
  } catch (error) {
    console.error('Error parsing push data:', error);
  }

  const notificationOptions: NotificationOptions & {
    vibrate?: number[];
    actions?: Array<{ action: string; title: string }>;
  } = {
      body: data.body,
      icon: data.icon,
      badge: '/branding/sadesa-favicon.png',
      vibrate: [100, 50, 100],
      data: { url: data.url },
      actions: [
        { action: 'open', title: 'Buka' },
        { action: 'close', title: 'Tutup' },
      ],
  };

  event.waitUntil(
    self.registration.showNotification(data.title, notificationOptions),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  if (event.action === 'close') return;

  const url = event.notification.data?.url || '/';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if (client.url.startsWith(self.location.origin) && 'focus' in client) {
          void client.focus();
          return client.navigate(url);
        }
      }

      return self.clients.openWindow?.(url);
    }),
  );
});