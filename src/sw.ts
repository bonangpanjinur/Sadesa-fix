/// <reference lib="webworker" />

import { clientsClaim } from 'workbox-core';
import { cleanupOutdatedCaches, precacheAndRoute } from 'workbox-precaching';
import { COURIER_ALARM_VIBRATION_PATTERN } from './lib/notificationVibrationPattern';

declare const self: ServiceWorkerGlobalScope;

precacheAndRoute(self.__WB_MANIFEST);
cleanupOutdatedCaches();
clientsClaim();

const CACHE_VERSION = 'v2';
const SCRIPT_CACHE = `sadesa-script-cache-${CACHE_VERSION}`;
const IMAGE_CACHE = `sadesa-image-cache-${CACHE_VERSION}`;
const MAX_SCRIPT_ENTRIES = 80;
const MAX_IMAGE_ENTRIES = 120;
const MAX_IMAGE_AGE_MS = 7 * 24 * 60 * 60 * 1000;

function isPublicImage(url: URL): boolean {
  const isPublicStorage = url.hostname.includes('supabase')
    && /\/storage\/v1\/(?:object|render\/image)\/public\/(product-images|tourism-images|profile-images|merchant-images|merchant-gallery|village-images)\//i.test(url.pathname);
  if (isPublicStorage) return true;
  if (url.origin !== self.location.origin) return false;
  return url.pathname.startsWith('/assets/')
    || url.pathname.startsWith('/branding/')
    || url.pathname === '/motor-icon.png'
    || url.pathname === '/motor-icon_original.png';
}

async function pruneCache(cacheName: string, maxEntries: number, maxAgeMs?: number): Promise<void> {
  const cache = await caches.open(cacheName);
  const requests = await cache.keys();
  const now = Date.now();
  for (const request of requests) {
    const response = await cache.match(request);
    const dateHeader = response?.headers.get('date');
    const isExpired = Boolean(maxAgeMs && dateHeader && now - new Date(dateHeader).getTime() > maxAgeMs);
    if (isExpired) await cache.delete(request);
  }
  const remaining = await cache.keys();
  if (remaining.length > maxEntries) {
    await Promise.all(remaining.slice(0, remaining.length - maxEntries).map((request) => cache.delete(request)));
  }
}

async function putInCache(cacheName: string, request: Request, response: Response, maxEntries: number, maxAgeMs?: number): Promise<Response> {
  if (response.ok) {
    const cache = await caches.open(cacheName);
    await cache.put(request, response.clone());
    await pruneCache(cacheName, maxEntries, maxAgeMs);
  }
  return response;
}

// Lazy route chunks and public media are cached after first use. This keeps
// repeat visits fast while avoiding a multi-megabyte service-worker install.
self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  const isScript = url.origin === self.location.origin && request.destination === 'script';
  const isImage = request.destination === 'image' && isPublicImage(url);
  if (!isScript && !isImage) return;

  const cacheName = isScript ? SCRIPT_CACHE : IMAGE_CACHE;
  event.respondWith((async () => {
    const cache = await caches.open(cacheName);
    const cached = await cache.match(request);

    if (cached && isScript) {
      // Stale-while-revalidate for route chunks: show the cached route now,
      // but refresh it for the next navigation.
      event.waitUntil(fetch(request).then((response) => putInCache(cacheName, request, response, isScript ? MAX_SCRIPT_ENTRIES : MAX_IMAGE_ENTRIES, isImage ? MAX_IMAGE_AGE_MS : undefined)).catch(() => undefined));
      return cached;
    }

    if (cached) return cached;
    return putInCache(cacheName, request, await fetch(request), isScript ? MAX_SCRIPT_ENTRIES : MAX_IMAGE_ENTRIES, isImage ? MAX_IMAGE_AGE_MS : undefined);
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(
    keys
      .filter((key) => (key.startsWith('sadesa-script-cache-') || key.startsWith('sadesa-image-cache-')) && !key.endsWith(CACHE_VERSION))
      .map((key) => caches.delete(key)),
  )));
});

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
    data: {} as Record<string, unknown>,
  };

  try {
    if (event.data) {
      data = { ...data, ...event.data.json() };
    }
  } catch (error) {
    console.error('Error parsing push data:', error);
  }

  const notificationType = data.data?.type;
  const merchantOrderId = typeof data.data?.order_id === 'string' ? data.data.order_id : null;
  const deliveryAssignmentId = typeof data.data?.assignment_id === 'string' ? data.data.assignment_id : null;
  const rideId = typeof data.data?.ride_id === 'string' ? data.data.ride_id : null;
  const isPersistentOrderAlert = notificationType === 'new_ride_request'
    || notificationType === 'new_delivery_offer'
    || notificationType === 'new_merchant_order';
  const notificationUrl = notificationType === 'new_merchant_order' && merchantOrderId
    ? `/merchant/orders?orderId=${encodeURIComponent(merchantOrderId)}`
    : data.url;

  const notificationOptions: NotificationOptions & {
    vibrate?: number[];
    actions?: Array<{ action: string; title: string }>;
    renotify?: boolean;
  } = {
      body: data.body,
      icon: data.icon,
      badge: '/branding/sadesa-favicon.png',
      silent: false,
      requireInteraction: isPersistentOrderAlert,
      tag: notificationType === 'new_merchant_order' && merchantOrderId
        ? `merchant-order-${merchantOrderId}`
        : notificationType === 'new_delivery_offer' && deliveryAssignmentId
          ? `delivery-offer-${deliveryAssignmentId}`
          : notificationType === 'new_ride_request' && rideId
            ? `ride-offer-${rideId}`
            : isPersistentOrderAlert
              ? `order-${notificationType}`
              : undefined,
      renotify: true,
      vibrate: [...COURIER_ALARM_VIBRATION_PATTERN],
      data: { url: notificationUrl },
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
