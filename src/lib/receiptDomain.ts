import type { CartItem, LastSale, ReceiptStore } from '@/components/pos/kasir/types';
import type { ReceiptData } from '@/lib/thermalPrinter';

export interface ReceiptSnapshot {
  store: ReceiptStore;
  sale: LastSale;
}

export interface PrintJobEnvelope {
  jobId: string;
  saleId: string;
  saleNumber: string;
  outletId: string;
  createdAt: string;
  copies: number;
  receipt: ReceiptData;
}

export function createPrintJobId(saleId: string, saleNumber: string): string {
  return `receipt:${saleId || saleNumber}`;
}

export function toReceiptData(snapshot: ReceiptSnapshot, cashierName?: string): ReceiptData {
  const { store, sale } = snapshot;
  return {
    saleId: sale.saleId,
    saleNumber: sale.saleNumber,
    createdAt: sale.createdAt,
    outletId: sale.outletId,
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

export function createPrintJob(snapshot: ReceiptSnapshot, cashierName: string | undefined, copies = 1): PrintJobEnvelope {
  const receipt = toReceiptData(snapshot, cashierName);
  return {
    jobId: snapshot.sale.printJobId,
    saleId: snapshot.sale.saleId,
    saleNumber: snapshot.sale.saleNumber,
    outletId: snapshot.sale.outletId,
    createdAt: snapshot.sale.createdAt,
    copies: Math.max(1, copies),
    receipt,
  };
}
