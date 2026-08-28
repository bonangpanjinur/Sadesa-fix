import type { ReceiptData } from '@/lib/thermalPrinter';

export interface POSQrTenant {
  id: string;
  name?: string | null;
  store_name?: string | null;
}

export interface POSQrTable {
  id: string;
  name: string;
  section: string;
}

export function getPOSMenuUrl(tenantId: string, tableId: string, origin = window.location.origin) {
  return new URL(`/menu/${encodeURIComponent(tenantId)}/${encodeURIComponent(tableId)}`, origin).toString();
}

export function getPOSQrFilename(tableName: string) {
  const safeName = tableName.trim().toLowerCase().replace(/[^a-z0-9]+/gi, '-').replace(/^-+|-+$/g, '') || 'meja';
  return `qr-menu-${safeName}.png`;
}

export function createPOSQrReceipt(tenant: POSQrTenant, table: POSQrTable, outletId?: string | null, origin?: string): ReceiptData {
  const qrData = getPOSMenuUrl(tenant.id, table.id, origin);
  const jobId = `qr-menu:${tenant.id}:${table.id}:${crypto.randomUUID()}`;
  const now = new Date();
  return {
    saleId: jobId,
    saleNumber: `QR-${table.name}`,
    createdAt: now.toISOString(),
    outletId: outletId || 'all-outlets',
    jobId,
    storeName: tenant.store_name || tenant.name || 'Toko',
    receiptHeader: table.section || 'Menu Digital',
    receiptFooter: 'Scan untuk melihat menu & memesan',
    invoiceNo: `QR-${table.name}`,
    date: now,
    items: [],
    subtotal: 0,
    discountAmount: 0,
    taxAmount: 0,
    total: 0,
    paidAmount: 0,
    changeAmount: 0,
    paymentMethod: 'QR MENU',
    qrData,
  };
}
