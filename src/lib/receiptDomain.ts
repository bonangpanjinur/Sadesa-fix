import type { CartItem, LastSale, ReceiptStore } from '@/components/pos/kasir/types';
import { getPrinterScope } from '@/lib/thermalPrinter';
import type { ReceiptData } from '@/lib/thermalPrinter';

export interface ReceiptSnapshot {
  store: ReceiptStore;
  sale: LastSale;
}

export type PrintIntent = 'auto' | 'manual' | 'reprint' | 'retry';

export interface PrintJobEnvelope {
  jobId: string;
  saleId: string;
  saleNumber: string;
  outletId: string;
  createdAt: string;
  copies: number;
  printIntent: PrintIntent;
  attemptId: string;
  requestedAt: string;
  receipt: ReceiptData;
}

export function createPrintJobId(saleId: string, saleNumber: string): string {
  return `receipt:${saleId || saleNumber}`;
}

export function createReceiptReprintJobId(saleId: string, attemptId = createAttemptId()): string {
  return `receipt:reprint:${saleId}:${attemptId}`;
}

export function createAttemptId(): string {
  return typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

export function toReceiptData(snapshot: ReceiptSnapshot, cashierName?: string): ReceiptData {
  const { store, sale } = snapshot;
  return {
    saleId: sale.saleId,
    saleNumber: sale.saleNumber,
    createdAt: sale.createdAt,
    outletId: sale.outletId,
    printerScope: store.id && sale.outletId ? getPrinterScope(store.id, sale.outletId) : undefined,
    jobId: sale.printJobId,
    storeName: store.name || 'Toko',
    storeAddress: store.address,
    storePhone: store.phone,
    receiptHeader: store.receipt_header,
    receiptFooter: store.receipt_footer,
    invoiceNo: sale.saleNumber,
    date: new Date(sale.createdAt),
    cashierName,
    customerName: sale.customerName !== 'Umum' ? sale.customerName : undefined,
    items: sale.items.map((item: CartItem) => ({
      name: item.variantName ? `${item.name} (${item.variantName})` : item.name,
      qty: item.qty,
      price: item.price,
      discount: item.discount || 0,
    })),
    subtotal: sale.subtotal ?? sale.total,
    discountAmount: sale.promoDiscount + sale.voucherDiscount + sale.pointsDiscount,
    taxAmount: sale.taxAmount ?? 0,
    total: sale.total,
    paidAmount: sale.paidAmount ?? sale.total,
    changeAmount: sale.change ?? 0,
    paymentMethod: sale.paymentMethod,
  };
}

export function createPrintJob(snapshot: ReceiptSnapshot, cashierName: string | undefined, copies = 1, options: { printIntent?: PrintIntent; attemptId?: string } = {}): PrintJobEnvelope {
  const receipt = toReceiptData(snapshot, cashierName);
  const jobId = snapshot.sale.printJobId || createPrintJobId(snapshot.sale.saleId || '', snapshot.sale.saleNumber);
  const printIntent = options.printIntent ?? 'auto';
  const attemptId = options.attemptId ?? jobId;
  const requestedAt = new Date().toISOString();
  receipt.jobId = jobId;
  receipt.printIntent = printIntent;
  receipt.attemptId = attemptId;
  receipt.requestedAt = requestedAt;
  return {
    jobId,
    saleId: snapshot.sale.saleId,
    saleNumber: snapshot.sale.saleNumber,
    outletId: snapshot.sale.outletId,
    createdAt: snapshot.sale.createdAt,
    copies: Math.max(1, copies),
    printIntent,
    attemptId,
    requestedAt,
    receipt,
  };
}
