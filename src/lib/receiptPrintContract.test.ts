import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { ReceiptData } from '@/lib/thermalPrinter';

const mocks = vi.hoisted(() => ({
  getPrinterSettings: vi.fn(),
  getUniversalPrinter: vi.fn(),
  printReceiptBrowser: vi.fn(),
  enqueueReceiptData: vi.fn(),
  flushReceiptOutbox: vi.fn(),
  getReceiptJobStatus: vi.fn(),
  markReceiptJobPrinted: vi.fn(),
}));

vi.mock('@/lib/thermalPrinter', () => ({
  getPrinterSettings: mocks.getPrinterSettings,
  getUniversalPrinter: mocks.getUniversalPrinter,
  printReceiptBrowser: mocks.printReceiptBrowser,
}));

vi.mock('@/lib/printOutbox', () => ({
  enqueueReceiptData: mocks.enqueueReceiptData,
  flushReceiptOutbox: mocks.flushReceiptOutbox,
  getReceiptJobStatus: mocks.getReceiptJobStatus,
  markReceiptJobPrinted: mocks.markReceiptJobPrinted,
}));

import { printReceiptWithContract } from './receiptPrintContract';

const receipt = {
  jobId: 'receipt:test-1',
  saleId: 'sale-1',
  saleNumber: 'TRX-1',
  outletId: 'outlet-1',
  createdAt: '2026-09-07T00:00:00.000Z',
  storeName: 'Toko Uji',
  invoiceNo: 'TRX-1',
  date: new Date('2026-09-07T00:00:00.000Z'),
  items: [],
  subtotal: 0,
  discountAmount: 0,
  taxAmount: 0,
  total: 0,
  paidAmount: 0,
  changeAmount: 0,
  paymentMethod: 'cash',
} as ReceiptData;

describe('receipt print contract', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.getPrinterSettings.mockReturnValue({ connectionType: 'wifi', printCopies: 1 });
    mocks.getUniversalPrinter.mockReturnValue({ connected: false, isConnected: vi.fn().mockReturnValue(false) });
    mocks.enqueueReceiptData.mockReturnValue(receipt);
    mocks.getReceiptJobStatus.mockReturnValue('failed');
    mocks.printReceiptBrowser.mockResolvedValue(undefined);
  });

  it('prints through the local bridge and keeps the job idempotent', async () => {
    mocks.flushReceiptOutbox.mockResolvedValue({ printed: 1, failed: 0 });
    mocks.getReceiptJobStatus.mockReturnValue('printed');

    await expect(printReceiptWithContract(receipt)).resolves.toEqual({
      status: 'printed',
      channel: 'bridge',
    });
    expect(mocks.enqueueReceiptData).toHaveBeenCalledWith(receipt);
    expect(mocks.printReceiptBrowser).not.toHaveBeenCalled();
  });

  it('falls back to browser printing and marks the queued job printed', async () => {
    mocks.flushReceiptOutbox.mockResolvedValue({ printed: 0, failed: 1 });

    await expect(printReceiptWithContract(receipt)).resolves.toEqual({
      status: 'printed',
      channel: 'browser',
    });
    expect(mocks.printReceiptBrowser).toHaveBeenCalledWith(receipt);
    expect(mocks.markReceiptJobPrinted).toHaveBeenCalledWith(receipt.jobId);
  });

  it('falls back to browser print when a USB printer is not connected', async () => {
    mocks.getPrinterSettings.mockReturnValue({ connectionType: 'usb', printCopies: 1 });
    mocks.flushReceiptOutbox.mockResolvedValue({ printed: 0, failed: 1 });

    await expect(printReceiptWithContract(receipt)).resolves.toMatchObject({
      status: 'printed',
      channel: 'browser',
    });
    expect(mocks.printReceiptBrowser).toHaveBeenCalledWith(receipt);
  });
});
