import { describe, expect, it } from 'vitest';
import { createPOSQrReceipt, getPOSMenuUrl, getPOSQrFilename } from './posQrPrint';

describe('POS QR print jobs', () => {
  it('encodes public menu identifiers safely', () => {
    expect(getPOSMenuUrl('tenant A', 'table/1', 'https://example.test')).toBe('https://example.test/menu/tenant%20A/table%2F1');
    expect(getPOSQrFilename('Meja 01 / Lantai 2')).toBe('qr-menu-meja-01-lantai-2.png');
    expect(getPOSQrFilename('!!!')).toBe('qr-menu-meja.png');
  });

  it('creates a structured QR receipt job without HTML content', () => {
    const receipt = createPOSQrReceipt({ id: 'tenant-1', name: 'Toko Uji' }, { id: 'table-1', name: 'Meja 1', section: 'Indoor' }, 'outlet-1', 'https://example.test');
    expect(receipt.jobId).toMatch(/^qr-menu:tenant-1:table-1:/);
    expect(receipt.outletId).toBe('outlet-1');
    expect(receipt.qrData).toBe('https://example.test/menu/tenant-1/table-1');
    expect(receipt.items).toEqual([]);
  });
});
