import { useState, useEffect, useCallback, useRef } from 'react';
import {
  replaceCachedProducts,
  getCachedProducts,
  savePendingSale,
  recoverCheckoutCheckpoints,
  syncPendingSales,
  getOfflineQueueSummary,
  PRODUCT_CACHE_MAX_AGE_MS,
  type OfflineProduct,
  type OfflineVariant,
  type PendingSale,
} from '@/lib/posOfflineDB';
import { processAtomicPOSSale } from '@/lib/posCheckout';
import { supabase } from '@/integrations/supabase/client';
import { withPOSSyncLock } from '@/lib/posOfflineCoordinator';

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
  has_variants: boolean | null;
  pos_categories?: { name: string } | null;
  pos_stock?: Array<{ quantity: number; outlet_id?: string | null }>;
  pos_product_variants?: Array<{
    id: string;
    product_id: string;
    name: string;
    sku: string | null;
    barcode: string | null;
    price: number | null;
    cost_price: number | null;
    is_active: boolean;
    pos_stock?: Array<{ quantity: number; outlet_id?: string | null }>;
  }>;
}

interface UsePOSOfflineSyncOptions {
  outletId: string | null;
  tenantId: string | null;
  autoSyncOnReconnect?: boolean;
}

export function isRetryableStatus(status: number): boolean {
  return status === 408 || status === 425 || status === 429 || status >= 500;
}

export function usePOSOfflineSync({ outletId, tenantId, autoSyncOnReconnect = true }: UsePOSOfflineSyncOptions) {
  const [isOnline, setIsOnline] = useState(() => typeof navigator === 'undefined' || navigator.onLine);
  const [isSyncing, setIsSyncing] = useState(false);
  const [pendingCount, setPendingCount] = useState(0);
  const [queueSummary, setQueueSummary] = useState({ pending: 0, queued: 0, syncing: 0, failed: 0, conflict: 0 });
  const [cachedProducts, setCachedProducts] = useState<OfflineProduct[]>([]);
  const [lastSync, setLastSync] = useState<Date | null>(null);
  const [clock, setClock] = useState(() => Date.now());
  const [recoveredCheckpointCount, setRecoveredCheckpointCount] = useState(0);
  const [recoveryReady, setRecoveryReady] = useState(false);
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

  const refreshQueueSummary = useCallback(async () => {
    if (!tenantId || !outletId) {
      setPendingCount(0);
      setQueueSummary({ pending: 0, queued: 0, syncing: 0, failed: 0, conflict: 0 });
      return;
    }
    try {
      const summary = await getOfflineQueueSummary(tenantId, outletId);
      setPendingCount(summary.pending);
      setQueueSummary(summary);
    } catch (error) {
      console.warn('[pos-offline] failed to count queue:', error);
    }
  }, [tenantId, outletId]);

  useEffect(() => {
    void loadCachedProducts();
    void refreshQueueSummary();
  }, [loadCachedProducts, refreshQueueSummary]);

  useEffect(() => {
    let cancelled = false;
    if (!tenantId || !outletId) {
      setRecoveryReady(true);
      setRecoveredCheckpointCount(0);
      return () => { cancelled = true; };
    }

    setRecoveryReady(false);
    void recoverCheckoutCheckpoints(tenantId, outletId)
      .then((count) => {
        if (!cancelled) {
          setRecoveredCheckpointCount(count);
          setRecoveryReady(true);
          void refreshQueueSummary();
        }
      })
      .catch((error) => {
        console.warn('[pos-offline] failed to recover checkout checkpoint:', error);
        if (!cancelled) setRecoveryReady(true);
      });

    return () => { cancelled = true; };
  }, [tenantId, outletId, refreshQueueSummary]);

  useEffect(() => {
    const interval = window.setInterval(() => setClock(Date.now()), 60_000);
    return () => window.clearInterval(interval);
  }, []);

  const refreshProductCache = useCallback(async () => {
    if (!outletId || !tenantId || !isOnline) return;
    try {
      // The app is a Vite SPA, so the old Express `/api/db/query` bridge is
      // not available. Read through Supabase directly, just like the online
      // POS catalogue does, and keep the result in IndexedDB for offline use.
      const { data, error } = await supabase
        .from('pos_products' as never)
        .select('*, pos_categories(name), pos_stock(quantity, outlet_id), pos_product_variants(id, product_id, name, sku, barcode, price, cost_price, is_active, pos_stock(quantity, outlet_id))')
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .order('name');
      if (error) throw error;
      const outletProducts = (data as unknown as OfflineProductApiRow[]).map((product) => ({
        ...product,
        pos_stock: (product.pos_stock || []).filter(
          (stock) => !stock.outlet_id || stock.outlet_id === outletId,
        ),
      }));
      const mapped: OfflineProduct[] = outletProducts.map((product) => ({
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
        has_variants: product.has_variants ?? false,
        variants: (product.pos_product_variants || [])
          .filter((variant) => variant.is_active)
          .map((variant): OfflineVariant => ({
            id: variant.id,
            product_id: variant.product_id,
            name: variant.name,
            sku: variant.sku,
            barcode: variant.barcode,
            price: variant.price,
            cost_price: variant.cost_price,
            is_active: variant.is_active,
            stock_qty: variant.pos_stock
              ?.filter((stock) => !stock.outlet_id || stock.outlet_id === outletId)
              .reduce((total, stock) => total + stock.quantity, 0),
          })),
        category_name: product.pos_categories?.name,
        stock_qty: product.pos_stock?.[0]?.quantity,
        cached_at: Date.now(),
      }));
      await replaceCachedProducts(mapped, tenantId, outletId);
      setCachedProducts(mapped);
      setLastSync(new Date());
    } catch (error) {
      console.warn('[pos-offline] failed to refresh product cache:', error);
    }
  }, [outletId, tenantId, isOnline]);

  // Keep the offline catalogue fresh when another POS session changes a
  // product or its outlet stock. The debounce prevents a bulk import from
  // issuing one cache refresh per row.
  useEffect(() => {
    if (!tenantId || !outletId) return;

    let refreshTimer: number | null = null;
    const scheduleRefresh = () => {
      if (refreshTimer) window.clearTimeout(refreshTimer);
      refreshTimer = window.setTimeout(() => {
        refreshTimer = null;
        void refreshProductCache();
      }, 300);
    };

    const channel = supabase
      .channel(`pos-product-cache-${tenantId}-${outletId}`)
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'pos_products',
        filter: `tenant_id=eq.${tenantId}`,
      }, scheduleRefresh)
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'pos_stock',
        filter: `tenant_id=eq.${tenantId}`,
      }, scheduleRefresh)
      .subscribe();

    return () => {
      if (refreshTimer) window.clearTimeout(refreshTimer);
      void channel.unsubscribe();
      void supabase.removeChannel(channel);
    };
  }, [tenantId, outletId, refreshProductCache]);

  const saveOfflineSale = useCallback(async (sale: Omit<PendingSale, 'synced'>) => {
    if (!tenantId || !outletId || sale.tenant_id !== tenantId || sale.outlet_id !== outletId) {
      throw new Error('Offline sale scope does not match the active tenant and outlet');
    }
    await savePendingSale(sale);
    await refreshQueueSummary();
  }, [tenantId, outletId, refreshQueueSummary]);

  const triggerSync = useCallback(async () => {
    if (!tenantId || !outletId || !isOnline || !recoveryReady || syncInProgress.current) return { synced: 0, failed: 0 };
    syncInProgress.current = true;
    setIsSyncing(true);
    try {
      const result = await withPOSSyncLock(tenantId, outletId, () => syncPendingSales(async (sale) => {
        try {
          await processAtomicPOSSale(
            sale.id,
            sale.tenant_id,
            sale.outlet_id,
            sale.cashier_id,
            {
              sale_number: sale.sale_number || `OFF-${sale.id.slice(0, 20)}`,
              cashier_name: null,
              customer_id: sale.customer_id || null,
              customer_name: sale.customer_name || null,
              customer_segment: sale.customer_segment || 'retail',
              offline_sync: true,
              subtotal: sale.subtotal,
              discount_amount: sale.discount_amount,
              tax_amount: sale.tax_amount,
              total: sale.total,
              payment_method: sale.payment_method,
              payment_amount: sale.payment_amount ?? sale.total,
              change_amount: sale.change_amount ?? 0,
              notes: sale.notes || `Offline sale ${sale.id}`,
              promotion_id: sale.promotion_id || null,
              promotion_discount: sale.promotion_discount ?? 0,
              voucher_id: sale.voucher_id || null,
              voucher_code: sale.voucher_code || null,
              voucher_discount: sale.voucher_discount ?? 0,
              loyalty_points_earned: sale.loyalty_points_earned ?? 0,
              loyalty_points_redeemed: sale.loyalty_points_redeemed ?? 0,
              loyalty_discount: sale.loyalty_discount ?? 0,
            },
            sale.items.map((item) => ({
              product_id: item.product_id,
              variant_id: item.variant_id || null,
              name: item.name,
              variant_name: item.variant_name || null,
              qty: item.qty,
              price: item.price,
              cost_price: item.cost_price ?? 0,
              discount: item.discount,
              tax_amount: (item.price * item.qty - item.discount) * item.tax_rate / 100,
              subtotal: item.price * item.qty - item.discount,
            })),
          );
          return { success: true };
        } catch (error: unknown) {
          const rpcError = error as { code?: string; message?: string; details?: string };
          const message = rpcError.message || (error instanceof Error ? error.message : 'Offline sale sync failed');
          const searchable = `${message} ${rpcError.details || ''}`.toLowerCase();
          const priceConflict = rpcError.code === 'P0001' || searchable.includes('price conflict') || searchable.includes('price_changed');
          const stockConflict = searchable.includes('stock conflict') || searchable.includes('stock_conflict') || searchable.includes('insufficient stock') || searchable.includes('stok tidak cukup');
          const conflict = priceConflict || stockConflict;
          return {
            success: false,
            error: message,
            retryable: conflict ? false : rpcError.code ? isRetryableStatus(Number(rpcError.code)) : true,
            conflict,
            conflictCode: priceConflict ? 'PRICE_CHANGED' : stockConflict ? 'STOCK_CONFLICT' : rpcError.code,
          };
        }
      }, { tenantId, outletId })) ?? { synced: 0, failed: 0 };
      await refreshQueueSummary();
      if (result.synced > 0 || result.failed > 0) setLastSync(new Date());
      return result;
    } finally {
      setIsSyncing(false);
      syncInProgress.current = false;
    }
  }, [tenantId, outletId, isOnline, recoveryReady, refreshQueueSummary]);

  useEffect(() => {
    const handleOnline = () => {
      setIsOnline(true);
    };
    const handleOffline = () => setIsOnline(false);
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, [autoSyncOnReconnect, triggerSync]);

  // The online event fires before React commits isOnline=true. Retrying from
  // this effect avoids calling a callback that still captured the offline state.
  useEffect(() => {
    if (autoSyncOnReconnect && isOnline && recoveryReady && tenantId && outletId) void triggerSync();
  }, [autoSyncOnReconnect, isOnline, recoveryReady, tenantId, outletId, triggerSync]);

  useEffect(() => {
    if (!autoSyncOnReconnect || !isOnline || !tenantId || !outletId) return;
    const interval = window.setInterval(() => void triggerSync(), 30_000);
    return () => window.clearInterval(interval);
  }, [autoSyncOnReconnect, isOnline, tenantId, outletId, triggerSync]);

  const cacheUpdatedAt = cachedProducts.reduce((latest, product) => Math.max(latest, product.cached_at || 0), 0);
  const cacheAgeMs = cacheUpdatedAt > 0 ? Math.max(0, clock - cacheUpdatedAt) : null;
  const isCacheStale = cacheAgeMs === null || cacheAgeMs > PRODUCT_CACHE_MAX_AGE_MS;

  return {
    isOnline,
    isSyncing,
    pendingCount,
    queueSummary,
    cachedProducts,
    lastSync,
    cacheUpdatedAt: cacheUpdatedAt ? new Date(cacheUpdatedAt) : null,
    cacheAgeMs,
    isCacheStale,
    recoveredCheckpointCount,
    refreshProductCache,
    saveOfflineSale,
    triggerSync,
    loadCachedProducts,
  };
}
