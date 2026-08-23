import { useState, useEffect, useCallback, useRef } from 'react';
import {
  cacheProducts,
  getCachedProducts,
  savePendingSale,
  syncPendingSales,
  getPendingSaleCount,
  type OfflineProduct,
  type PendingSale,
} from '@/lib/posOfflineDB';
import { posBridgeFetch } from '@/lib/posBridge';

interface OfflineProductApiRow {
  id: string;
  name: string;
  sku: string | null;
  barcode: string | null;
  price: number;
  cost_price: number | null;
  unit: string | null;
  tax_rate: number | null;
  is_stock_tracked: boolean | null;
  image_url: string | null;
  is_active: boolean | null;
  pos_categories?: { name: string } | null;
  pos_stock?: Array<{ quantity: number }>;
}

interface UsePOSOfflineSyncOptions {
  outletId: string | null;
  tenantId: string | null;
  autoSyncOnReconnect?: boolean;
}

export function isRetryableStatus(status: number): boolean {
  return status === 408 || status === 409 || status === 425 || status === 429 || status >= 500;
}

export function usePOSOfflineSync({ outletId, tenantId, autoSyncOnReconnect = true }: UsePOSOfflineSyncOptions) {
  const [isOnline, setIsOnline] = useState(() => typeof navigator === 'undefined' || navigator.onLine);
  const [isSyncing, setIsSyncing] = useState(false);
  const [pendingCount, setPendingCount] = useState(0);
  const [cachedProducts, setCachedProducts] = useState<OfflineProduct[]>([]);
  const [lastSync, setLastSync] = useState<Date | null>(null);
  const syncInProgress = useRef(false);

  const loadCachedProducts = useCallback(async () => {
    if (!tenantId || !outletId) {
      setCachedProducts([]);
      return;
    }
    try {
      setCachedProducts(await getCachedProducts(tenantId, outletId));
    } catch (error) {
      console.warn('[pos-offline] failed to load product cache:', error);
    }
  }, [tenantId, outletId]);

  const refreshPendingCount = useCallback(async () => {
    if (!tenantId || !outletId) {
      setPendingCount(0);
      return;
    }
    try {
      setPendingCount(await getPendingSaleCount(tenantId, outletId));
    } catch (error) {
      console.warn('[pos-offline] failed to count queue:', error);
    }
  }, [tenantId, outletId]);

  useEffect(() => {
    void loadCachedProducts();
    void refreshPendingCount();
  }, [loadCachedProducts, refreshPendingCount]);

  const refreshProductCache = useCallback(async () => {
    if (!outletId || !tenantId || !isOnline) return;
    try {
      const res = await posBridgeFetch(`/api/db/query?table=pos_products&outlet_id=${encodeURIComponent(outletId)}`, {
        headers: { 'Content-Type': 'application/json' },
      });
      if (!res.ok) return;
      const { data } = await res.json() as { data?: OfflineProductApiRow[] };
      if (!Array.isArray(data)) return;
      const mapped: OfflineProduct[] = data.map((product) => ({
        id: product.id,
        tenant_id: tenantId,
        outlet_id: outletId,
        cache_key: `${tenantId}:${outletId}:${product.id}`,
        name: product.name,
        sku: product.sku,
        barcode: product.barcode,
        price: product.price,
        cost_price: product.cost_price ?? 0,
        unit: product.unit ?? 'pcs',
        tax_rate: product.tax_rate ?? 0,
        is_stock_tracked: product.is_stock_tracked ?? false,
        image_url: product.image_url,
        is_active: product.is_active ?? true,
        category_name: product.pos_categories?.name,
        stock_qty: product.pos_stock?.[0]?.quantity,
        cached_at: Date.now(),
      }));
      await cacheProducts(mapped);
      setCachedProducts(mapped);
      setLastSync(new Date());
    } catch (error) {
      console.warn('[pos-offline] failed to refresh product cache:', error);
    }
  }, [outletId, tenantId, isOnline]);

  const saveOfflineSale = useCallback(async (sale: Omit<PendingSale, 'synced'>) => {
    if (!tenantId || !outletId || sale.tenant_id !== tenantId || sale.outlet_id !== outletId) {
      throw new Error('Offline sale scope does not match the active tenant and outlet');
    }
    await savePendingSale(sale);
    await refreshPendingCount();
  }, [tenantId, outletId, refreshPendingCount]);

  const triggerSync = useCallback(async () => {
    if (!tenantId || !outletId || !isOnline || syncInProgress.current) return { synced: 0, failed: 0 };
    syncInProgress.current = true;
    setIsSyncing(true);
    try {
      const result = await syncPendingSales(async (sale) => {
        const res = await posBridgeFetch('/api/db/pos-sale', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Idempotency-Key': `offline-pos-sale:${sale.id}` },
          body: JSON.stringify({
            outlet_id: sale.outlet_id,
            tenant_id: sale.tenant_id,
            cashier_id: sale.cashier_id,
            items: sale.items,
            subtotal: sale.subtotal,
            discount_amount: sale.discount_amount,
            tax_amount: sale.tax_amount,
            total: sale.total,
            payment_method: sale.payment_method,
            customer_id: sale.customer_id,
            customer_name: sale.customer_name,
            notes: sale.notes,
            offline_id: sale.id,
            created_at: sale.created_at,
          }),
        });
        if (!res.ok) {
          const body = await res.json().catch(() => ({})) as { error?: string };
          return { success: false, error: body.error || `HTTP ${res.status}`, retryable: isRetryableStatus(res.status) };
        }
        return { success: true };
      }, { tenantId, outletId });
      await refreshPendingCount();
      if (result.synced > 0 || result.failed > 0) setLastSync(new Date());
      return result;
    } finally {
      setIsSyncing(false);
      syncInProgress.current = false;
    }
  }, [tenantId, outletId, isOnline, refreshPendingCount]);

  useEffect(() => {
    const handleOnline = () => {
      setIsOnline(true);
      if (autoSyncOnReconnect) void triggerSync();
    };
    const handleOffline = () => setIsOnline(false);
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, [autoSyncOnReconnect, triggerSync]);

  useEffect(() => {
    if (!autoSyncOnReconnect || !isOnline || !tenantId || !outletId) return;
    const interval = window.setInterval(() => void triggerSync(), 30_000);
    return () => window.clearInterval(interval);
  }, [autoSyncOnReconnect, isOnline, tenantId, outletId, triggerSync]);

  return {
    isOnline,
    isSyncing,
    pendingCount,
    cachedProducts,
    lastSync,
    refreshProductCache,
    saveOfflineSale,
    triggerSync,
    loadCachedProducts,
  };
}
