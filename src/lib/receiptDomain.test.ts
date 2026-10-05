import { describe, expect, it } from 'vitest';
import {
  createAttemptId,
  createPrintJob,
  createPrintJobId,
  createReceiptReprintJobId,
} from './receiptDomain';

const snapshot = {
  store: { id: 'tenant-1', name: 'Toko Uji' },
  sale: {
    saleId: 'sale-1',
    saleNumber: 'TRX-1',
    createdAt: '2026-10-04T00:00:00.000Z',
    outletId: 'outlet-1',
    printJobId: createPrintJobId('sale-1', 'TRX-1'),
    total: 10000,
    change: 0,
    paymentMethod: 'cash',
    customerName: 'Umum',
    items: [],
    pointsEarned: 0,
    pointsRedeemed: 0,
    pointsDiscount: 0,
    promoDiscount: 0,
    voucherDiscount: 0,
    appliedPromoName: null,
    appliedVoucherCode: null,
    newPointsBalance: null,
    paidAmount: 10000,
  },
} as never;

describe('receipt print identity', () => {
  it('keeps normal auto-print idempotent and marks its metadata', () => {
    const first = createPrintJob(snapshot, 'Kasir Uji');
    const second = createPrintJob(snapshot, 'Kasir Uji');

    expect(first.jobId).toBe(second.jobId);
    expect(first.receipt.printIntent).toBe('auto');
    expect(first.receipt.attemptId).toBe(first.jobId);
    expect(first.receipt.printerScope).toEqual({
      tenantId: 'tenant-1',
      outletId: 'outlet-1',
      deviceId: expect.any(String),
    });
  });

  it('creates a new job for every explicit reprint attempt', () => {
    const attemptA = createAttemptId();
    const attemptB = createAttemptId();
    const jobA = createReceiptReprintJobId('sale-1', attemptA);
    const jobB = createReceiptReprintJobId('sale-1', attemptB);

    expect(jobA).not.toBe(jobB);
    expect(jobA).toContain(`sale-1:${attemptA}`);
    expect(jobB).toContain(`sale-1:${attemptB}`);
  });
});
