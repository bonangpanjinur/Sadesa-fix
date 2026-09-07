import { describe, expect, it } from 'vitest';
import {
  allocateStockAcrossOutlets,
  availableStock,
  assertStockIdentity,
  stockIdentityKey,
} from './posStockContract';

describe('POS variant and multi-outlet stock contract', () => {
  it('keeps base and variant stock identities separate', () => {
    expect(stockIdentityKey({ productId: 'p1', outletId: 'o1' }))
      .not.toBe(stockIdentityKey({ productId: 'p1', variantId: 'v1', outletId: 'o1' }));
    expect(stockIdentityKey({ productId: 'p1', variantId: 'v1', outletId: 'o1' }))
      .not.toBe(stockIdentityKey({ productId: 'p1', variantId: 'v1', outletId: 'o2' }));
  });

  it('does not expose reserved quantity as available stock', () => {
    expect(availableStock({ quantity: 10, reservedQuantity: 3 })).toBe(7);
    expect(availableStock({ quantity: 2, reservedQuantity: 4 })).toBe(0);
  });

  it('allocates deterministically across outlets without overselling', () => {
    const result = allocateStockAcrossOutlets([
      { productId: 'p1', variantId: 'v1', outletId: 'outlet-b', quantity: 5 },
      { productId: 'p1', variantId: 'v1', outletId: 'outlet-a', quantity: 3, reservedQuantity: 1 },
    ], 6);

    expect(result).toEqual({
      allocations: [
        { outletId: 'outlet-a', quantity: 2, availableBefore: 2, availableAfter: 0 },
        { outletId: 'outlet-b', quantity: 4, availableBefore: 5, availableAfter: 1 },
      ],
      remaining: 0,
    });
  });

  it('reports an insufficient multi-outlet reservation instead of allocating beyond stock', () => {
    const result = allocateStockAcrossOutlets([
      { productId: 'p1', variantId: 'v1', outletId: 'outlet-a', quantity: 2 },
      { productId: 'p1', variantId: 'v1', outletId: 'outlet-b', quantity: 1 },
    ], 5);

    expect(result.remaining).toBe(2);
    expect(result.allocations.reduce((sum, allocation) => sum + allocation.quantity, 0)).toBe(3);
  });

  it('rejects a stock row that crosses product or outlet scope', () => {
    expect(() => assertStockIdentity(
      { productId: 'p2', variantId: 'v1', outletId: 'outlet-a' },
      { tenantProductId: 'p1', tenantOutletId: 'outlet-a', variantProductId: 'p1', variantTenantId: 'p1' },
    )).toThrow('produk POS');

    expect(() => assertStockIdentity(
      { productId: 'p1', variantId: 'v1', outletId: 'outlet-b' },
      { tenantProductId: 'p1', tenantOutletId: 'outlet-a', variantProductId: 'p1', variantTenantId: 'p1' },
    )).toThrow('outlet');
  });
});