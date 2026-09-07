/**
 * Offline-first POS storage.
 *
 * The queue is deliberately scoped by tenant and outlet. A browser profile can
 * therefore serve multiple businesses without one tenant seeing another
 * tenant's cached catalogue or pending sales.
 */

import { getCheckoutRecoveryAction } from './posOfflineRecovery';

const DB_NAME = 'desamart_pos_offline';
const DB_VERSION = 3;
const MAX_SYNC_ATTEMPTS = 8;
const CLAIM_LEASE_MS = 5 * 60_000;
export const PRODUCT_CACHE_MAX_AGE_MS = 30 * 60_000;
const STORES = {
  PRODUCTS: 'pos_products',
  PENDING_SALES: 'pending_sales',
  SYNC_LOG: 'sync_log',
  CHECKOUT_CHECKPOINTS: 'checkout_checkpoints',
} as const;

export interface OfflineProduct {
  id: string;
  tenant_id?: string;
  outlet_id?: string;
  cache_key?: string;
  name: string;
  sku: string | null;
  barcode: string | null;
  price: number;
  cost_price: number;
  unit: string;
  tax_rate: number;
  is_stock_tracked: boolean;
  image_url: string | null;
  is_active: boolean;
  has_variants?: boolean;
  variants?: OfflineVariant[];
  category_name?: string;
  stock_qty?: number;
  cached_at: number;
}

export interface OfflineVariant {
  id: string;
  product_id: string;
  name: string;
  sku: string | null;
  barcode: string | null;
  price: number | null;
  cost_price: number | null;
  is_active: boolean;
  stock_qty?: number;
}

export type PendingSaleStatus = 'queued' | 'syncing' | 'failed' | 'conflict' | 'synced';

export interface PendingSale {
  id: string;
  outlet_id: string;
  tenant_id: string;
  cashier_id: string;
  sale_number?: string;
  items: Array<{
    product_id: string;
    variant_id?: string | null;
    name: string;
    variant_name?: string | null;
    qty: number;
    price: number;
    cost_price?: number;
    discount: number;
    tax_rate: number;
  }>;
  subtotal: number;
  discount_amount: number;
  tax_amount: number;
  total: number;
  payment_method: string;
  payment_amount?: number;
  change_amount?: number;
  promotion_id?: string | null;
  promotion_discount?: number;
  voucher_id?: string | null;
  voucher_code?: string | null;
  voucher_discount?: number;
  loyalty_points_earned?: number;
  loyalty_points_redeemed?: number;
  loyalty_discount?: number;
  customer_segment?: 'retail' | 'wholesale' | 'reseller' | 'member' | 'outlet';
  customer_id?: string | null;
  customer_name?: string | null;
  notes?: string;
  created_at: string;
  synced: boolean;
  status?: PendingSaleStatus;
  attempts?: number;
  next_attempt_at?: number;
  last_attempt_at?: number;
  sync_error?: string;
  conflict_code?: string;
  conflict_message?: string;
}

export interface CheckoutCheckpoint {
  id: string;
  tenant_id: string;
  outlet_id: string;
  created_at: string;
  sale: Omit<PendingSale, 'synced'>;
}

export interface SyncResult {
  success: boolean;
  error?: string;
  retryable?: boolean;
  conflict?: boolean;
  conflictCode?: string;
}

export interface OfflineQueueSummary {
  pending: number;
  queued: number;
  syncing: number;
  failed: number;
  conflict: number;
}

function scopeKey(tenantId: string, outletId: string): string {
  return `${tenantId}:${outletId}`;
}

function productCacheKey(product: OfflineProduct): string {
  return product.cache_key || `${product.tenant_id || 'unknown'}:${product.outlet_id || 'unknown'}:${product.id}`;
}

function openDB(): Promise<IDBDatabase> {
  if (typeof indexedDB === 'undefined') return Promise.reject(new Error('IndexedDB is unavailable'));
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = (event) => {
      const db = (event.target as IDBOpenDBRequest).result;
      const oldVersion = event.oldVersion;
      if (oldVersion < 2 && db.objectStoreNames.contains(STORES.PRODUCTS)) {
        db.deleteObjectStore(STORES.PRODUCTS);
      }
      if (!db.objectStoreNames.contains(STORES.PRODUCTS)) {
        const productStore = db.createObjectStore(STORES.PRODUCTS, { keyPath: 'cache_key' });
        productStore.createIndex('scope', ['tenant_id', 'outlet_id'], { unique: false });
        productStore.createIndex('barcode_scope', ['tenant_id', 'outlet_id', 'barcode'], { unique: false });
        productStore.createIndex('cached_at', 'cached_at', { unique: false });
      }
      if (!db.objectStoreNames.contains(STORES.PENDING_SALES)) {
        const salesStore = db.createObjectStore(STORES.PENDING_SALES, { keyPath: 'id' });
        salesStore.createIndex('scope', ['tenant_id', 'outlet_id'], { unique: false });
        salesStore.createIndex('status', 'status', { unique: false });
        salesStore.createIndex('created_at', 'created_at', { unique: false });
      } else if (oldVersion < 2) {
        const upgradeTransaction = (event.target as IDBOpenDBRequest).transaction;
        if (!upgradeTransaction) throw new Error('IndexedDB upgrade transaction unavailable');
        const salesStore = upgradeTransaction.objectStore(STORES.PENDING_SALES);
        if (!salesStore.indexNames.contains('scope')) salesStore.createIndex('scope', ['tenant_id', 'outlet_id'], { unique: false });
        if (!salesStore.indexNames.contains('status')) salesStore.createIndex('status', 'status', { unique: false });
      }
      if (!db.objectStoreNames.contains(STORES.SYNC_LOG)) {
        db.createObjectStore(STORES.SYNC_LOG, { keyPath: 'id', autoIncrement: true });
      }
      if (!db.objectStoreNames.contains(STORES.CHECKOUT_CHECKPOINTS)) {
        const checkpointStore = db.createObjectStore(STORES.CHECKOUT_CHECKPOINTS, { keyPath: 'id' });
        checkpointStore.createIndex('scope', ['tenant_id', 'outlet_id'], { unique: false });
        checkpointStore.createIndex('created_at', 'created_at', { unique: false });
      } else if (oldVersion < 3) {
        const upgradeTransaction = (event.target as IDBOpenDBRequest).transaction;
        if (!upgradeTransaction) throw new Error('IndexedDB upgrade transaction unavailable');
        const checkpointStore = upgradeTransaction.objectStore(STORES.CHECKOUT_CHECKPOINTS);
        if (!checkpointStore.indexNames.contains('scope')) checkpointStore.createIndex('scope', ['tenant_id', 'outlet_id'], { unique: false });
        if (!checkpointStore.indexNames.contains('created_at')) checkpointStore.createIndex('created_at', 'created_at', { unique: false });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error || new Error('Failed to open IndexedDB'));
  });
}

function waitForTransaction(tx: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error || new Error('IndexedDB transaction failed'));
    tx.onabort = () => reject(tx.error || new Error('IndexedDB transaction aborted'));
  });
}

function normaliseSale(sale: Omit<PendingSale, 'synced'> | PendingSale): PendingSale {
  const previous = sale as PendingSale;
  const staleClaim = previous.status === 'syncing'
    && (previous.last_attempt_at || 0) + CLAIM_LEASE_MS <= Date.now();
  const synced = previous.synced === true && previous.status === 'synced';
  return {
    ...sale,
    synced,
    status: synced ? 'synced' : (staleClaim ? 'queued' : (previous.status || 'queued')),
    attempts: previous.attempts || 0,
    next_attempt_at: staleClaim ? 0 : (previous.next_attempt_at || 0),
  };
}

// Product cache -----------------------------------------------------------------

export async function cacheProducts(products: OfflineProduct[]): Promise<void> {
  if (products.some((product) => !product.tenant_id || !product.outlet_id)) {
    throw new Error('Offline product cache requires tenant and outlet scope');
  }
  const db = await openDB();
  const tx = db.transaction(STORES.PRODUCTS, 'readwrite');
  const store = tx.objectStore(STORES.PRODUCTS);
  const now = Date.now();
  for (const product of products) {
    store.put({ ...product, cache_key: productCacheKey(product), cached_at: now });
  }
  await waitForTransaction(tx);
}

/** Replaces one scoped catalogue snapshot so deleted/deactivated products do not linger offline. */
export async function replaceCachedProducts(products: OfflineProduct[], tenantId: string, outletId: string): Promise<void> {
  if (!tenantId || !outletId) throw new Error('Offline product cache scope is required');
  if (products.some((product) => product.tenant_id !== tenantId || product.outlet_id !== outletId)) {
    throw new Error('Offline product cache contains a product outside the requested scope');
  }
  const db = await openDB();
  const tx = db.transaction(STORES.PRODUCTS, 'readwrite');
  const store = tx.objectStore(STORES.PRODUCTS);
  const request = store.index('scope').openCursor(IDBKeyRange.only([tenantId, outletId]));
  request.onsuccess = () => {
    const cursor = request.result;
    if (cursor) {
      cursor.delete();
      cursor.continue();
      return;
    }
    const now = Date.now();
    for (const product of products) {
      store.put({ ...product, cache_key: productCacheKey(product), cached_at: now });
    }
  };
  await waitForTransaction(tx);
}

export async function getCachedProducts(tenantId: string, outletId: string): Promise<OfflineProduct[]> {
  if (!tenantId || !outletId) throw new Error('Offline product cache scope is required');
  const db = await openDB();
  const tx = db.transaction(STORES.PRODUCTS, 'readonly');
  const store = tx.objectStore(STORES.PRODUCTS);
  const request = store.index('scope').getAll(IDBKeyRange.only([tenantId, outletId]));
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve((request.result || []) as OfflineProduct[]);
    request.onerror = () => reject(request.error || new Error('Failed to read product cache'));
  });
}

export async function findProductByBarcode(barcode: string, tenantId: string, outletId: string): Promise<OfflineProduct | null> {
  const products = await getCachedProducts(tenantId, outletId);
  return products.find((product) => product.barcode === barcode) || null;
}

export async function clearProductCache(tenantId?: string, outletId?: string): Promise<void> {
  const db = await openDB();
  const tx = db.transaction(STORES.PRODUCTS, 'readwrite');
  const store = tx.objectStore(STORES.PRODUCTS);
  if (!tenantId || !outletId) {
    store.clear();
  } else {
    const request = store.index('scope').openCursor(IDBKeyRange.only([tenantId, outletId]));
    request.onsuccess = () => {
      const cursor = request.result;
      if (cursor) {
        cursor.delete();
        cursor.continue();
      }
    };
  }
  await waitForTransaction(tx);
}

// Durable pending queue ---------------------------------------------------------

export async function savePendingSale(sale: Omit<PendingSale, 'synced'>): Promise<void> {
  if (!sale.tenant_id || !sale.outlet_id) throw new Error('Pending sale requires tenant and outlet scope');
  const db = await openDB();
  const tx = db.transaction(STORES.PENDING_SALES, 'readwrite');
  tx.objectStore(STORES.PENDING_SALES).put(normaliseSale(sale));
  await waitForTransaction(tx);
}

/**
 * Saves the checkout payload before the network RPC. If the browser is
 * refreshed, closed, or loses power after the server commits but before the
 * response reaches the browser, the same request key can safely be replayed.
 */
export async function saveCheckoutCheckpoint(checkpoint: CheckoutCheckpoint): Promise<void> {
  if (!checkpoint.id || !checkpoint.tenant_id || !checkpoint.outlet_id) {
    throw new Error('Checkout checkpoint requires id, tenant, and outlet scope');
  }
  if (checkpoint.sale.id !== checkpoint.id || checkpoint.sale.tenant_id !== checkpoint.tenant_id || checkpoint.sale.outlet_id !== checkpoint.outlet_id) {
    throw new Error('Checkout checkpoint scope does not match its sale');
  }
  const db = await openDB();
  const tx = db.transaction(STORES.CHECKOUT_CHECKPOINTS, 'readwrite');
  tx.objectStore(STORES.CHECKOUT_CHECKPOINTS).put(checkpoint);
  await waitForTransaction(tx);
}

export async function getCheckoutCheckpoints(tenantId: string, outletId: string): Promise<CheckoutCheckpoint[]> {
  if (!tenantId || !outletId) throw new Error('Checkout checkpoint scope is required');
  const db = await openDB();
  const tx = db.transaction(STORES.CHECKOUT_CHECKPOINTS, 'readonly');
  const request = tx.objectStore(STORES.CHECKOUT_CHECKPOINTS)
    .index('scope')
    .getAll(IDBKeyRange.only([tenantId, outletId]));
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve((request.result || []) as CheckoutCheckpoint[]);
    request.onerror = () => reject(request.error || new Error('Failed to read checkout checkpoints'));
  });
}

export async function clearCheckoutCheckpoint(id: string): Promise<void> {
  const db = await openDB();
  const tx = db.transaction(STORES.CHECKOUT_CHECKPOINTS, 'readwrite');
  tx.objectStore(STORES.CHECKOUT_CHECKPOINTS).delete(id);
  await waitForTransaction(tx);
}

/** Converts every durable pre-RPC checkpoint into the normal idempotent queue. */
export async function recoverCheckoutCheckpoints(tenantId: string, outletId: string): Promise<number> {
  const checkpoints = await getCheckoutCheckpoints(tenantId, outletId);
  let recovered = 0;
  for (const checkpoint of checkpoints) {
    const action = getCheckoutRecoveryAction(checkpoint.sale);
    if (action === 'ignore_synced' || action === 'manual_conflict') continue;
    await savePendingSale(checkpoint.sale);
    await clearCheckoutCheckpoint(checkpoint.id);
    recovered++;
  }
  return recovered;
}

export async function getPendingSales(tenantId: string, outletId: string): Promise<PendingSale[]> {
  if (!tenantId || !outletId) throw new Error('Pending sale scope is required');
  const db = await openDB();
  const tx = db.transaction(STORES.PENDING_SALES, 'readonly');
  const store = tx.objectStore(STORES.PENDING_SALES);
  const request = store.index('scope').getAll(IDBKeyRange.only([tenantId, outletId]));
  return new Promise((resolve, reject) => {
    request.onsuccess = () => {
      const records = (request.result || []) as PendingSale[];
      resolve(records
        .map(normaliseSale)
        .filter((sale) => sale.status !== 'synced' && !sale.synced)
        .sort((a, b) => a.created_at.localeCompare(b.created_at)));
    };
    request.onerror = () => reject(request.error || new Error('Failed to read pending sales'));
  });
}

export async function getPendingSaleCount(tenantId: string, outletId: string): Promise<number> {
  return (await getPendingSales(tenantId, outletId)).length;
}

export async function getOfflineQueueSummary(tenantId: string, outletId: string): Promise<OfflineQueueSummary> {
  if (!tenantId || !outletId) throw new Error('Offline queue scope is required');
  const db = await openDB();
  const tx = db.transaction(STORES.PENDING_SALES, 'readonly');
  const request = tx.objectStore(STORES.PENDING_SALES).index('scope').getAll(IDBKeyRange.only([tenantId, outletId]));
  return new Promise((resolve, reject) => {
    request.onsuccess = () => {
      const summary: OfflineQueueSummary = { pending: 0, queued: 0, syncing: 0, failed: 0, conflict: 0 };
      for (const sale of (request.result || []) as PendingSale[]) {
        if (sale.synced || sale.status === 'synced') continue;
        summary.pending++;
        const status = sale.status || 'queued';
        if (status === 'queued') summary.queued++;
        else if (status === 'syncing') summary.syncing++;
        else if (status === 'failed') summary.failed++;
        else if (status === 'conflict') summary.conflict++;
      }
      resolve(summary);
    };
    request.onerror = () => reject(request.error || new Error('Failed to summarize offline queue'));
  });
}

export async function markSaleSynced(id: string): Promise<void> {
  const db = await openDB();
  const tx = db.transaction(STORES.PENDING_SALES, 'readwrite');
  const store = tx.objectStore(STORES.PENDING_SALES);
  const request = store.get(id);
  request.onsuccess = () => {
    if (request.result) store.put({ ...request.result, synced: true, status: 'synced', sync_error: undefined });
  };
  await waitForTransaction(tx);
}

export async function markSaleSyncConflict(id: string, error: string, code = 'CONFLICT'): Promise<void> {
  const db = await openDB();
  const tx = db.transaction(STORES.PENDING_SALES, 'readwrite');
  const store = tx.objectStore(STORES.PENDING_SALES);
  const request = store.get(id);
  request.onsuccess = () => {
    const record = request.result as PendingSale | undefined;
    if (!record) return;
    store.put({
      ...record,
      synced: false,
      status: 'conflict',
      last_attempt_at: Date.now(),
      next_attempt_at: Number.MAX_SAFE_INTEGER,
      sync_error: error.slice(0, 500),
      conflict_code: code,
      conflict_message: error.slice(0, 500),
    });
  };
  await waitForTransaction(tx);
}

export async function markSaleSyncError(id: string, error: string, retryable = true): Promise<void> {
  const db = await openDB();
  const tx = db.transaction(STORES.PENDING_SALES, 'readwrite');
  const store = tx.objectStore(STORES.PENDING_SALES);
  const request = store.get(id);
  request.onsuccess = () => {
    const record = request.result as PendingSale | undefined;
    if (!record) return;
    const attempts = (record.attempts || 0) + 1;
    const permanent = !retryable || attempts >= MAX_SYNC_ATTEMPTS;
    store.put({
      ...record,
      synced: false,
      status: permanent ? 'failed' : 'queued',
      attempts,
      last_attempt_at: Date.now(),
      next_attempt_at: permanent ? Number.MAX_SAFE_INTEGER : Date.now() + Math.min(30 * 60_000, 2 ** attempts * 1_000),
      sync_error: error.slice(0, 500),
    });
  };
  await waitForTransaction(tx);
}

async function claimSale(id: string): Promise<PendingSale | null> {
  const db = await openDB();
  const tx = db.transaction(STORES.PENDING_SALES, 'readwrite');
  const store = tx.objectStore(STORES.PENDING_SALES);
  let claimed: PendingSale | null = null;
  const request = store.get(id);
  request.onsuccess = () => {
    const record = request.result as PendingSale | undefined;
    if (!record || record.synced) return;
    const staleClaim = record.status === 'syncing'
      && (record.last_attempt_at || 0) + CLAIM_LEASE_MS <= Date.now();
    if (record.status === 'syncing' && !staleClaim) return;
    if (!staleClaim && (record.next_attempt_at || 0) > Date.now()) return;
    claimed = { ...record, status: 'syncing', last_attempt_at: Date.now() };
    store.put(claimed);
  };
  await waitForTransaction(tx);
  return claimed;
}

export async function syncPendingSales(
  syncFn: (sale: PendingSale) => Promise<SyncResult>,
  scope: { tenantId: string; outletId: string },
): Promise<{ synced: number; failed: number }> {
  if (!scope.tenantId || !scope.outletId) throw new Error('Pending sale sync scope is required');
  const pending = await getPendingSales(scope.tenantId, scope.outletId);
  let synced = 0;
  let failed = 0;
  for (const candidate of pending) {
    const sale = await claimSale(candidate.id);
    if (!sale) continue;
    try {
      const result = await syncFn(sale);
      if (result.success) {
        await markSaleSynced(sale.id);
        synced++;
      } else {
        if (result.conflict) {
          await markSaleSyncConflict(sale.id, result.error || 'Sync conflict', result.conflictCode || 'CONFLICT');
        } else {
          await markSaleSyncError(sale.id, result.error || 'Unknown sync error', result.retryable !== false);
        }
        failed++;
      }
    } catch (error) {
      await markSaleSyncError(sale.id, error instanceof Error ? error.message : 'Sync failed');
      failed++;
    }
  }
  return { synced, failed };
}

export function getOfflineScopeKey(tenantId: string, outletId: string): string {
  return scopeKey(tenantId, outletId);
}

/** Re-queues a failed/conflicted sale for an explicit operator retry. */
export async function retryPendingSale(id: string): Promise<void> {
  const db = await openDB();
  const tx = db.transaction(STORES.PENDING_SALES, 'readwrite');
  const store = tx.objectStore(STORES.PENDING_SALES);
  const request = store.get(id);
  request.onsuccess = () => {
    const record = request.result as PendingSale | undefined;
    if (!record || record.synced) return;
    store.put({
      ...record,
      status: 'queued',
      next_attempt_at: 0,
      sync_error: undefined,
      conflict_code: undefined,
      conflict_message: undefined,
    });
  };
  await waitForTransaction(tx);
}
