import type { ReceiptData } from '@/lib/thermalPrinter';

/**
 * Android-only integration for ESC/POS Bluetooth Print Service.
 * The app receives an HTML data URL through its documented print:// app link.
 * A browser cannot confirm the physical print result, so callers should label
 * this result as "perintah dikirim", not as a hardware acknowledgement.
 */
export function isAndroidPrintServiceSupported(): boolean {
  return typeof navigator !== 'undefined' && /Android/i.test(navigator.userAgent);
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function money(value: number): string {
  return value.toLocaleString('id-ID');
}

export function buildAndroidReceiptHtml(receipt: ReceiptData): string {
  const itemRows = receipt.items.map(item => `
    <div class="item"><div>${escapeHtml(item.name)}</div>
    <div class="row"><span>${item.qty} x ${money(item.price)}</span><span>${money(item.qty * item.price)}</span></div>
    ${item.discount > 0 ? `<div>Diskon: -${money(item.discount)}</div>` : ''}</div>`).join('');
  return `<!doctype html><html><head><meta charset="utf-8"><title>Struk ${escapeHtml(receipt.invoiceNo)}</title>
    <style>@page{size:80mm auto;margin:2mm}body{width:76mm;margin:0;font:12px monospace;color:#000}.center{text-align:center}.line{border-top:1px dashed #000;margin:5px 0}.row{display:flex;justify-content:space-between;gap:8px}.item{margin:4px 0}h3{margin:0 0 4px;font-size:14px}</style>
    </head><body><div class="center"><h3>${escapeHtml(receipt.storeName || 'STRUK PENJUALAN')}</h3>
    ${receipt.storeAddress ? `<div>${escapeHtml(receipt.storeAddress)}</div>` : ''}
    ${receipt.storePhone ? `<div>${escapeHtml(receipt.storePhone)}</div>` : ''}</div>
    <div class="line"></div><div>No: ${escapeHtml(receipt.invoiceNo)}</div><div>Tgl: ${escapeHtml(receipt.date.toLocaleString('id-ID'))}</div>
    ${receipt.cashierName ? `<div>Kasir: ${escapeHtml(receipt.cashierName)}</div>` : ''}<div class="line"></div>${itemRows}<div class="line"></div>
    ${receipt.subtotal !== receipt.total ? `<div class="row"><span>Subtotal</span><span>${money(receipt.subtotal)}</span></div>` : ''}
    ${receipt.discountAmount > 0 ? `<div class="row"><span>Diskon</span><span>-${money(receipt.discountAmount)}</span></div>` : ''}
    ${receipt.taxAmount > 0 ? `<div class="row"><span>Pajak</span><span>${money(receipt.taxAmount)}</span></div>` : ''}
    <div class="row"><strong>TOTAL</strong><strong>${money(receipt.total)}</strong></div><div class="row"><span>Bayar</span><span>${money(receipt.paidAmount)}</span></div>
    <div class="row"><span>Kembalian</span><span>${money(receipt.changeAmount)}</span></div><div>Metode: ${escapeHtml(receipt.paymentMethod)}</div>
    <div class="line"></div><div class="center">${escapeHtml(receipt.receiptFooter || 'Terima kasih sudah berbelanja!')}</div></body></html>`;
}

export function buildAndroidPrintLink(receipt: ReceiptData, copies = 1): string {
  const html = buildAndroidReceiptHtml(receipt);
  const src = `data:text/html;charset=utf-8,${encodeURIComponent(html)}`;
  return `print://escpos.org/escpos/bt/print?srcTp=uri&srcObj=html&numCopies=${Math.min(10, Math.max(1, copies))}&src=${encodeURIComponent(src)}`;
}

export async function printReceiptViaAndroidService(receipt: ReceiptData, copies = 1): Promise<void> {
  if (!isAndroidPrintServiceSupported()) {
    throw new Error('ESC/POS Bluetooth Print Service hanya dapat dipanggil dari tablet Android.');
  }
  const link = document.createElement('a');
  link.href = buildAndroidPrintLink(receipt, copies);
  link.rel = 'noopener';
  link.style.display = 'none';
  document.body.appendChild(link);
  link.click();
  window.setTimeout(() => link.remove(), 1000);
}

export async function testPrintViaAndroidService(): Promise<void> {
  await printReceiptViaAndroidService({
    invoiceNo: 'TEST-PRINT',
    date: new Date(),
    storeName: 'SaDesa POS',
    items: [{ name: 'Test printer Android', qty: 1, price: 1000, discount: 0 }],
    subtotal: 1000,
    discountAmount: 0,
    taxAmount: 0,
    total: 1000,
    paidAmount: 1000,
    changeAmount: 0,
    paymentMethod: 'TEST',
    receiptFooter: 'Printer siap digunakan',
  });
}
