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
import { processAtomicPOSSale } from '@/lib/posCheckout';
import { supabase } from '@/integrations/supabase/client';

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
  pos_stock?: Array<{ quantity: number; outlet_id?: string | null }>;
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
      // The app is a Vite SPA, so the old Express `/api/db/query` bridge is
      // not available. Read through Supabase directly, just like the online
      // POS catalogue does, and keep the result in IndexedDB for offline use.
      const { data, error } = await supabase
        .from('pos_products' as never)
        .select('*, pos_categories(name), pos_stock(quantity, outlet_id)')
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
          const rpcError = error as { code?: string; message?: string };
          const message = rpcError.message || (error instanceof Error ? error.message : 'Offline sale sync failed');
          const conflict = rpcError.code === 'P0001' || message.includes('Price conflict');
          return {
            success: false,
            error: message,
            retryable: conflict ? false : rpcError.code ? isRetryableStatus(Number(rpcError.code)) : true,
            conflict,
            conflictCode: conflict ? 'PRICE_CHANGED' : rpcError.code,
          };
        }
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
