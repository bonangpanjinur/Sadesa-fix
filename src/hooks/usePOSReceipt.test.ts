// @vitest-environment jsdom
import { act, renderHook } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { usePOSReceipt } from './usePOSReceipt';

const mocks = vi.hoisted(() => ({
  printReceiptWithContract: vi.fn(),
}));
vi.mock('@/lib/printBridgeClient', () => ({
  printBridgeClient: {
    health: vi.fn(),
    listPrinters: vi.fn(),
  },
}));
vi.mock('@/lib/receiptPrintContract', () => ({
  printReceiptWithContract: mocks.printReceiptWithContract,
}));
vi.mock('sonner', () => ({ toast: { success: vi.fn(), info: vi.fn(), error: vi.fn() } }));

describe('usePOSReceipt browser fallback', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.printReceiptWithContract.mockResolvedValue({ status: 'printed', channel: 'bridge' });
  });

  it('keeps the native print path when the local Print Bridge succeeds', async () => {
    mocks.printReceiptWithContract.mockResolvedValue({ status: 'printed', channel: 'bridge' });
    const tenant = { name: 'Toko Uji', address: 'Desa Uji', phone: '0800000000' };
    const lastSale = {
      saleId: 'sale-success', saleNumber: 'SALE-002', createdAt: '2026-08-30T15:00:00.000Z',
      outletId: 'outlet-1', printJobId: 'receipt:sale-success', total: 15000, change: 0,
      paymentMethod: 'cash', customerName: 'Umum', items: [{ productId: 'product-1', name: 'Produk Uji', qty: 1, price: 15000, discount: 0, costPrice: 0, unit: 'pcs', taxRate: 0, notes: '' }],
      pointsEarned: 0, pointsRedeemed: 0, pointsDiscount: 0, promoDiscount: 0,
      voucherDiscount: 0, appliedPromoName: null, appliedVoucherCode: null, newPointsBalance: null,
      subtotal: 15000, taxAmount: 0, paidAmount: 15000,
    } as const;
    const { result } = renderHook(() => usePOSReceipt({ tenant, outletReady: true, lastSale, userEmail: 'kasir@example.com' }));

    let printed: boolean | undefined;
    await act(async () => { printed = await result.current.printReceipt(); });

    expect(printed).toBe(true);
    expect(mocks.printReceiptWithContract).toHaveBeenCalledOnce();
  });

  it('opens browser print when local Print Bridge is unavailable', async () => {
    const tenant = { name: 'Toko Uji', address: 'Desa Uji', phone: '0800000000' };
    const lastSale = {
      saleId: 'sale-1', saleNumber: 'SALE-001', createdAt: '2026-08-30T15:00:00.000Z',
      outletId: 'outlet-1', printJobId: 'receipt:sale-1', total: 15000, change: 0,
      paymentMethod: 'cash', customerName: 'Umum', items: [{ productId: 'product-1', name: 'Produk Uji', qty: 1, price: 15000, discount: 0, costPrice: 0, unit: 'pcs', taxRate: 0, notes: '' }],
      pointsEarned: 0, pointsRedeemed: 0, pointsDiscount: 0, promoDiscount: 0,
      voucherDiscount: 0, appliedPromoName: null, appliedVoucherCode: null, newPointsBalance: null,
      subtotal: 15000, taxAmount: 0, paidAmount: 15000,
    } as const;
    const { result } = renderHook(() => usePOSReceipt({ tenant, outletReady: true, lastSale, userEmail: 'kasir@example.com' }));

    let printed: boolean | undefined;
    await act(async () => { printed = await result.current.printReceipt(); });

    expect(printed).toBe(true);
    expect(mocks.printReceiptWithContract).toHaveBeenCalledOnce();
  });
});
