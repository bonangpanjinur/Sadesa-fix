import { describe, expect, it } from 'vitest';
import { buildAndroidPrintLink, buildAndroidReceiptHtml } from './androidPrintService';
import type { ReceiptData } from './thermalPrinter';

const receipt: ReceiptData = {
  invoiceNo: 'TRX-1',
  date: new Date('2026-10-02T06:00:00.000Z'),
  storeName: 'Toko <Uji>',
  items: [{ name: 'Kopi & Teh', qty: 2, price: 5000, discount: 0 }],
  subtotal: 10000,
  discountAmount: 0,
  taxAmount: 0,
  total: 10000,
  paidAmount: 10000,
  changeAmount: 0,
  paymentMethod: 'cash',
};

describe('android ESC/POS print service', () => {
  it('builds a print:// app link with encoded HTML and copies', () => {
    const link = buildAndroidPrintLink(receipt, 2);
    expect(link.startsWith('print://escpos.org/escpos/bt/print?')).toBe(true);
    expect(link).toContain('srcTp=uri');
    expect(link).toContain('srcObj=html');
    expect(link).toContain('numCopies=2');
    expect(link).toContain('data%3Atext%2Fhtml');
  });

  it('escapes receipt content before sending it to a third-party app', () => {
    const html = buildAndroidReceiptHtml(receipt);
    expect(html).toContain('Toko &lt;Uji&gt;');
    expect(html).toContain('Kopi &amp; Teh');
    expect(html).not.toContain('Toko <Uji>');
  });
});
