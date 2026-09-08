export type OfflineCapability = 'secure_context' | 'indexed_db' | 'service_worker';

export interface OfflineDeviceCheck {
  capability: OfflineCapability;
  label: string;
  required: boolean;
  available: boolean;
  reason: string;
}

export interface OfflineDevicePolicy {
  supportedOperations: readonly string[];
  onlineOnlyOperations: readonly string[];
  checks: OfflineDeviceCheck[];
  canUseOfflineCashier: boolean;
}

/**
 * Offline POS is capability-based rather than browser-name based. This keeps
 * the support boundary honest as browser versions change.
 */
export function getOfflineDevicePolicy(input: {
  isSecureContext: boolean;
  indexedDBAvailable: boolean;
  serviceWorkerAvailable: boolean;
}): OfflineDevicePolicy {
  const checks: OfflineDeviceCheck[] = [
    {
      capability: 'secure_context',
      label: 'Konteks aman (HTTPS)',
      required: true,
      available: input.isSecureContext,
      reason: input.isSecureContext ? 'Koneksi aman tersedia.' : 'Offline POS membutuhkan HTTPS.',
    },
    {
      capability: 'indexed_db',
      label: 'Penyimpanan IndexedDB',
      required: true,
      available: input.indexedDBAvailable,
      reason: input.indexedDBAvailable ? 'Cache dan antrean lokal tersedia.' : 'Browser tidak menyediakan IndexedDB.',
    },
    {
      capability: 'service_worker',
      label: 'Service worker PWA',
      required: true,
      available: input.serviceWorkerAvailable,
      reason: input.serviceWorkerAvailable ? 'Aset aplikasi dapat dipakai saat koneksi terputus.' : 'PWA belum dapat mendaftarkan service worker.',
    },
  ];

  return {
    supportedOperations: ['Penjualan tunai', 'Katalog yang sudah dicache', 'Receipt lokal'],
    onlineOnlyOperations: ['Pembayaran online', 'Order marketplace', 'Laporan final', 'Settlement'],
    checks,
    canUseOfflineCashier: checks.every((check) => !check.required || check.available),
  };
}

export function getCurrentOfflineDevicePolicy(): OfflineDevicePolicy {
  return getOfflineDevicePolicy({
    isSecureContext: typeof window !== 'undefined' && window.isSecureContext,
    indexedDBAvailable: typeof indexedDB !== 'undefined',
    serviceWorkerAvailable: typeof navigator !== 'undefined' && 'serviceWorker' in navigator,
  });
}