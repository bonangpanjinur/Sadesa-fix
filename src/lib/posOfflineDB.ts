/**
 * Offline-first POS storage.
 *
 * The queue is deliberately scoped by tenant and outlet. A browser profile can
 * therefore serve multiple businesses without one tenant seeing another
 * tenant's cached catalogue or pending sales.
 */

const DB_NAME = 'desamart_pos_offline';
const DB_VERSION = 2;
const MAX_SYNC_ATTEMPTS = 8;
const STORES = {
  PRODUCTS: 'pos_products',
  PENDING_SALES: 'pending_sales',
  SYNC_LOG: 'sync_log',
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
  category_name?: string;
  stock_qty?: number;
  cached_at: number;
}

export type PendingSaleStatus = 'queued' | 'syncing' | 'failed' | 'synced';

export interface PendingSale {
  id: string;
  outlet_id: string;
  tenant_id: string;
  cashier_id: string;
  items: Array<{
    product_id: string;
    name: string;
    qty: number;
    price: number;
    discount: number;
    tax_rate: number;
  }>;
  subtotal: number;
  discount_amount: number;
  tax_amount: number;
  total: number;
  payment_method: string;
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
}

export interface SyncResult {
  success: boolean;
  error?: string;
  retryable?: boolean;
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
  return {
    ...sale,
    synced: previous.synced === true && previous.status === 'synced',
    status: previous.status === 'synced' ? 'synced' : 'queued',
    attempts: previous.attempts || 0,
    next_attempt_at: previous.next_attempt_at || 0,
  };
}

// Product cache -----------------------------------------------------------------

export async function cacheProducts(products: OfflineProduct[]): Promise<void> {
  const db = await openDB();
  const tx = db.transaction(STORES.PRODUCTS, 'readwrite');
  const store = tx.objectStore(STORES.PRODUCTS);
  const now = Date.now();
  for (const product of products) {
    store.put({ ...product, cache_key: productCacheKey(product), cached_at: now });
  }
  await waitForTransaction(tx);
}

export async function getCachedProducts(tenantId?: string, outletId?: string): Promise<OfflineProduct[]> {
  const db = await openDB();
  const tx = db.transaction(STORES.PRODUCTS, 'readonly');
  const store = tx.objectStore(STORES.PRODUCTS);
  const request = tenantId && outletId
    ? store.index('scope').getAll(IDBKeyRange.only([tenantId, outletId]))
    : store.getAll();
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve((request.result || []) as OfflineProduct[]);
    request.onerror = () => reject(request.error || new Error('Failed to read product cache'));
  });
}

export async function findProductByBarcode(barcode: string, tenantId?: string, outletId?: string): Promise<OfflineProduct | null> {
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
  const db = await openDB();
  const tx = db.transaction(STORES.PENDING_SALES, 'readwrite');
  tx.objectStore(STORES.PENDING_SALES).put(normaliseSale(sale));
  await waitForTransaction(tx);
}

export async function getPendingSales(tenantId?: string, outletId?: string): Promise<PendingSale[]> {
  const db = await openDB();
  const tx = db.transaction(STORES.PENDING_SALES, 'readonly');
  const store = tx.objectStore(STORES.PENDING_SALES);
  const request = tenantId && outletId
    ? store.index('scope').getAll(IDBKeyRange.only([tenantId, outletId]))
    : store.getAll();
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

export async function getPendingSaleCount(tenantId?: string, outletId?: string): Promise<number> {
  return (await getPendingSales(tenantId, outletId)).length;
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
    if (!record || record.synced || record.status === 'syncing') return;
    if ((record.next_attempt_at || 0) > Date.now()) return;
    claimed = { ...record, status: 'syncing', last_attempt_at: Date.now() };
    store.put(claimed);
  };
  await waitForTransaction(tx);
  return claimed;
}

export async function syncPendingSales(
  syncFn: (sale: PendingSale) => Promise<SyncResult>,
  scope?: { tenantId?: string; outletId?: string },
): Promise<{ synced: number; failed: number }> {
  const pending = await getPendingSales(scope?.tenantId, scope?.outletId);
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
        await markSaleSyncError(sale.id, result.error || 'Unknown sync error', result.retryable !== false);
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
