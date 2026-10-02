import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import POSKasirPage from '@/pages/pos/POSKasirPage';

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
  rpc: vi.fn(),
  saveCheckoutTransaction: vi.fn(),
  markSaleSynced: vi.fn(),
  clearCheckoutCheckpoint: vi.fn(),
  fetchHeldBills: vi.fn(),
  refreshProductCache: vi.fn(),
  triggerSync: vi.fn(),
  saveOfflineSale: vi.fn(),
  holdBill: vi.fn(),
  resumeBill: vi.fn(),
  getPrinterSettings: vi.fn(),
  getUniversalPrinter: vi.fn(),
  buildReceiptBytes: vi.fn(),
  printReceiptBrowser: vi.fn(),
  enqueueReceiptData: vi.fn(),
  flushReceiptOutbox: vi.fn(),
  getReceiptJobStatus: vi.fn(),
  markReceiptJobPrinted: vi.fn(),
  tenant: {
    id: 'tenant-e2e',
    name: 'Toko Uji E2E',
    address: 'Alamat uji',
    phone: '0800000000',
    receipt_header: null,
    receipt_footer: null,
  },
  outlet: { id: 'outlet-e2e', name: 'Outlet Uji' },
  cachedProducts: [] as unknown[],
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: mocks.from, rpc: mocks.rpc },
}));

vi.mock('@/contexts/POSContext', () => ({
  usePOS: () => ({
    tenant: mocks.tenant,
    activeOutlet: mocks.outlet,
    formatCurrency: (amount: number) => `Rp ${amount.toLocaleString('id-ID')}`,
  }),
}));

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: { id: 'cashier-e2e', email: 'kasir@example.test' } }),
}));

vi.mock('@/components/pos/POSLayout', () => ({
  POSLayout: ({ children }: { children: React.ReactNode }) => <div data-testid="pos-layout">{children}</div>,
}));

vi.mock('@/components/pos/kasir/POSCart', () => ({
  POSCart: ({ cart, onOpenPayment }: { cart: Array<{ name: string }>; onOpenPayment: () => void }) => (
    <div>
      <span data-testid="cart-item-count">{cart.length}</span>
      <button type="button" onClick={onOpenPayment}>Buka Pembayaran</button>
    </div>
  ),
}));

vi.mock('@/hooks/usePOSOfflineSync', () => ({
  usePOSOfflineSync: () => ({
    isOnline: true,
    isSyncing: false,
    pendingCount: 0,
    queueSummary: { pending: 0, failed: 0, conflict: 0 },
    triggerSync: mocks.triggerSync,
    saveOfflineSale: mocks.saveOfflineSale,
    refreshProductCache: mocks.refreshProductCache,
    cachedProducts: mocks.cachedProducts,
    cacheAgeMs: 0,
    isCacheStale: false,
  }),
}));

vi.mock('@/hooks/usePOSHeldBills', () => ({
  usePOSHeldBills: () => ({
    heldBills: [],
    fetchHeldBills: mocks.fetchHeldBills,
    holdBill: mocks.holdBill,
    resumeBill: mocks.resumeBill,
  }),
}));

vi.mock('@/lib/posOfflineDB', () => ({
  saveCheckoutTransaction: mocks.saveCheckoutTransaction,
  markSaleSynced: mocks.markSaleSynced,
  clearCheckoutCheckpoint: mocks.clearCheckoutCheckpoint,
}));

vi.mock('@/lib/thermalPrinter', () => ({
  getPrinterSettings: mocks.getPrinterSettings,
  getUniversalPrinter: mocks.getUniversalPrinter,
  buildReceiptBytes: mocks.buildReceiptBytes,
  printReceiptBrowser: mocks.printReceiptBrowser,
}));

vi.mock('@/lib/printOutbox', () => ({
  enqueueReceiptData: mocks.enqueueReceiptData,
  flushReceiptOutbox: mocks.flushReceiptOutbox,
  getReceiptJobStatus: mocks.getReceiptJobStatus,
  markReceiptJobPrinted: mocks.markReceiptJobPrinted,
  getPendingReceiptCount: () => 0,
}));

const successfulSale = {
  sale_id: 'sale-e2e-1',
  sale_number: 'TRX-E2E-1',
  total: 10_000,
  payment_method: 'cash',
  duplicate: false,
};

function makeQuery(table: string) {
  const rowsByTable: Record<string, unknown> = {
    pos_products: [{
      id: 'product-e2e-1',
      name: 'Kopi Uji E2E',
      price: 10_000,
      cost_price: 4_000,
      unit: 'pcs',
      tax_rate: 0,
      is_stock_tracked: false,
      pos_stock: [],
      has_variants: false,
      is_active: true,
    }],
    pos_categories: [],
    pos_loyalty_programs: null,
    pos_promotions: [],
  };
  const result = { data: rowsByTable[table] ?? [], error: null };
  const query: Record<string, unknown> = {};
  for (const method of ['select', 'eq', 'order', 'or', 'gte', 'lte', 'ilike', 'limit']) {
    query[method] = vi.fn(() => query);
  }
  query.maybeSingle = vi.fn().mockResolvedValue(result);
  query.then = (resolve: (value: typeof result) => unknown, reject?: (reason: unknown) => unknown) =>
    Promise.resolve(result).then(resolve, reject);
  return query;
}

async function startCashierPayment() {
  render(
    <MemoryRouter>
      <POSKasirPage />
    </MemoryRouter>,
  );

  fireEvent.click(await screen.findByRole('button', { name: /Kopi Uji E2E/ }));
  await waitFor(() => expect(screen.getByTestId('cart-item-count')).toHaveTextContent('1'));
  fireEvent.click(screen.getByRole('button', { name: 'Buka Pembayaran' }));
  await screen.findByText('Proses Pembayaran');
  fireEvent.click(screen.getByRole('button', { name: 'Selesaikan' }));
}

describe('POS cashier payment end-to-end acceptance', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.from.mockImplementation((table: string) => makeQuery(table));
    mocks.rpc.mockResolvedValue({ data: successfulSale, error: null });
    mocks.saveCheckoutTransaction.mockResolvedValue(undefined);
    mocks.markSaleSynced.mockResolvedValue(undefined);
    mocks.clearCheckoutCheckpoint.mockResolvedValue(undefined);
    mocks.fetchHeldBills.mockResolvedValue(undefined);
    mocks.refreshProductCache.mockResolvedValue(undefined);
    mocks.triggerSync.mockResolvedValue(undefined);
    mocks.saveOfflineSale.mockResolvedValue(undefined);
    mocks.holdBill.mockResolvedValue(undefined);
    mocks.resumeBill.mockResolvedValue(undefined);
    mocks.getPrinterSettings.mockReturnValue({
      connectionType: 'wifi',
      wifiIp: '192.0.2.20',
      wifiPort: 9100,
      printCopies: 1,
      paperWidth: 58,
    });
    mocks.getUniversalPrinter.mockReturnValue({ connected: false });
    mocks.enqueueReceiptData.mockImplementation((receipt: { jobId: string }) => receipt);
    mocks.flushReceiptOutbox.mockResolvedValue({ printed: 1, failed: 0 });
    mocks.getReceiptJobStatus.mockReturnValue('printed');
  });

  it('completes cashier UI → durable checkpoint → atomic RPC → synced sale → receipt contract', async () => {
    await startCashierPayment();

    await screen.findByRole('heading', { name: 'Transaksi Berhasil!' });
    expect(mocks.saveCheckoutTransaction).toHaveBeenCalledWith(expect.objectContaining({
      tenant_id: 'tenant-e2e',
      outlet_id: 'outlet-e2e',
      sale: expect.objectContaining({ total: 10_000, payment_method: 'cash' }),
    }));
    expect(mocks.rpc).toHaveBeenCalledTimes(1);
    const [, rpcArgs] = mocks.rpc.mock.calls[0];
    expect(rpcArgs).toMatchObject({
      p_tenant_id: 'tenant-e2e',
      p_outlet_id: 'outlet-e2e',
      p_cashier_id: 'cashier-e2e',
      p_sale: expect.objectContaining({
        total: 10_000,
        payment_amount: 10_000,
        change_amount: 0,
        payment_method: 'cash',
      }),
      p_items: [expect.objectContaining({ product_id: 'product-e2e-1', qty: 1, price: 10_000 })],
    });
    expect(mocks.markSaleSynced).toHaveBeenCalledWith(rpcArgs.p_request_key, successfulSale);

    fireEvent.click(screen.getByRole('button', { name: 'Cetak Struk' }));
    await waitFor(() => expect(mocks.flushReceiptOutbox).toHaveBeenCalledTimes(1));
    expect(mocks.enqueueReceiptData).toHaveBeenCalledWith(expect.objectContaining({
      saleId: successfulSale.sale_id,
      saleNumber: successfulSale.sale_number,
      outletId: 'outlet-e2e',
      total: 10_000,
    }));
    expect(mocks.clearCheckoutCheckpoint).toHaveBeenCalledWith(rpcArgs.p_request_key);
  });

  it('reuses the same request key after a transient RPC failure and retry', async () => {
    mocks.rpc
      .mockResolvedValueOnce({ data: null, error: new Error('temporary RPC timeout') })
      .mockResolvedValueOnce({ data: successfulSale, error: null });

    await startCashierPayment();
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledTimes(1));
    expect(screen.getByRole('button', { name: 'Selesaikan' })).toBeEnabled();

    fireEvent.click(screen.getByRole('button', { name: 'Selesaikan' }));
    await screen.findByRole('heading', { name: 'Transaksi Berhasil!' });

    expect(mocks.rpc).toHaveBeenCalledTimes(2);
    expect(mocks.rpc.mock.calls[1][1].p_request_key).toBe(mocks.rpc.mock.calls[0][1].p_request_key);
  });
});
