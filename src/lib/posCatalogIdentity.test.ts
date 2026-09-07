import { describe, expect, it } from 'vitest';
import {
  findCatalogIdentityConflicts,
  formatCatalogIdentityConflict,
  normalizeCatalogIdentity,
} from './posCatalogIdentity';

describe('POS catalog identity validation', () => {
  it('normalizes blank values and case differences', () => {
    expect(normalizeCatalogIdentity('  SKU-Abc  ')).toBe('sku-abc');
    expect(normalizeCatalogIdentity('   ')).toBeNull();
    expect(normalizeCatalogIdentity(null)).toBeNull();
  });

  it('detects duplicate identities between a product and its variants', () => {
    const conflicts = findCatalogIdentityConflicts({
      product: { id: 'product-1', sku: 'SKU-01', barcode: '89901' },
      variants: [
        { id: 'variant-1', product_id: 'product-1', sku: ' sku-01 ', barcode: '89902' },
        { id: 'variant-2', product_id: 'product-1', sku: 'SKU-02', barcode: '89901' },
      ],
    });

    expect(conflicts.map(({ kind, value }) => `${kind}:${value}`)).toEqual([
      'sku:sku-01',
      'barcode:89901',
    ]);
  });

  it('detects conflicts with another product or variant in the same tenant', () => {
    const conflicts = findCatalogIdentityConflicts({
      product: { id: 'product-2', sku: 'SKU-02', barcode: '89902' },
      variants: [{ id: 'variant-2', product_id: 'product-2', sku: 'SKU-03', barcode: null }],
      existingProducts: [{ id: 'product-1', sku: 'sku-02', barcode: null }],
      existingVariants: [{ id: 'variant-1', product_id: 'product-1', sku: null, barcode: '89902' }],
    });

    expect(conflicts).toHaveLength(2);
    expect(formatCatalogIdentityConflict(conflicts[0])).toContain('SKU "sku-02"');
    expect(formatCatalogIdentityConflict(conflicts[1])).toContain('barcode "89902"');
  });

  it('does not flag the records currently being edited', () => {
    expect(findCatalogIdentityConflicts({
      product: { id: 'product-1', sku: 'SKU-01', barcode: '89901' },
      variants: [{ id: 'variant-1', product_id: 'product-1', sku: 'SKU-02', barcode: '89902' }],
      existingProducts: [{ id: 'product-1', sku: 'SKU-01', barcode: '89901' }],
      existingVariants: [{ id: 'variant-1', product_id: 'product-1', sku: 'SKU-02', barcode: '89902' }],
    })).toEqual([]);
  });
});