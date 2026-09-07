export interface StockIdentity {
  productId: string;
  variantId?: string | null;
  outletId: string;
}

export interface StockLot extends StockIdentity {
  id?: string;
  quantity: number;
  reservedQuantity?: number | null;
}

export interface StockAllocation {
  outletId: string;
  quantity: number;
  availableBefore: number;
  availableAfter: number;
}

export function stockIdentityKey(identity: StockIdentity): string {
  return [
    identity.productId,
    identity.variantId || 'base',
    identity.outletId,
  ].join(':');
}

export function availableStock(stock: Pick<StockLot, 'quantity' | 'reservedQuantity'>): number {
  return Math.max(0, stock.quantity - (stock.reservedQuantity || 0));
}

/**
 * Allocates a marketplace reservation across active outlets in a stable order.
 * Variant rows never fall back to a parent-product row: callers must pass lots
 * for the exact product/variant identity being reserved.
 */
export function allocateStockAcrossOutlets(
  lots: StockLot[],
  requestedQuantity: number,
): { allocations: StockAllocation[]; remaining: number } {
  if (!Number.isFinite(requestedQuantity) || requestedQuantity <= 0) {
    return { allocations: [], remaining: requestedQuantity };
  }

  let remaining = requestedQuantity;
  const allocations: StockAllocation[] = [];
  const orderedLots = [...lots].sort((left, right) =>
    left.outletId.localeCompare(right.outletId) || (left.id || '').localeCompare(right.id || ''),
  );

  for (const lot of orderedLots) {
    if (remaining <= 0) break;
    const availableBefore = availableStock(lot);
    const quantity = Math.min(availableBefore, remaining);
    if (quantity <= 0) continue;

    allocations.push({
      outletId: lot.outletId,
      quantity,
      availableBefore,
      availableAfter: availableBefore - quantity,
    });
    remaining -= quantity;
  }

  return { allocations, remaining };
}

export function assertStockIdentity(
  stock: StockIdentity,
  context: { tenantProductId: string; tenantOutletId: string; variantProductId?: string | null; variantTenantId?: string | null },
): void {
  if (stock.productId !== context.tenantProductId) {
    throw new Error('Stok harus memakai produk POS pada tenant yang sama.');
  }
  if (stock.outletId !== context.tenantOutletId) {
    throw new Error('Stok harus memakai outlet pada tenant yang sama.');
  }
  if (stock.variantId && (
    context.variantProductId !== stock.productId ||
    (context.variantTenantId && context.variantTenantId !== context.tenantProductId)
  )) {
    throw new Error('Varian stok harus berasal dari produk dan tenant yang sama.');
  }
}