export type CatalogIdentityKind = 'sku' | 'barcode';

export interface CatalogIdentityRecord {
  id?: string | null;
  product_id?: string | null;
  sku?: string | null;
  barcode?: string | null;
}

export interface CatalogIdentityConflict {
  kind: CatalogIdentityKind;
  value: string;
  conflictingId?: string | null;
  conflictingProductId?: string | null;
}

export interface CatalogIdentityValidationInput {
  product: CatalogIdentityRecord;
  variants: CatalogIdentityRecord[];
  existingProducts?: CatalogIdentityRecord[];
  existingVariants?: CatalogIdentityRecord[];
}

export function normalizeCatalogIdentity(value: string | null | undefined): string | null {
  const normalized = value?.trim().toLowerCase();
  return normalized ? normalized : null;
}

function identities(record: CatalogIdentityRecord): Array<{ kind: CatalogIdentityKind; value: string }> {
  const result: Array<{ kind: CatalogIdentityKind; value: string }> = [];
  const sku = normalizeCatalogIdentity(record.sku);
  const barcode = normalizeCatalogIdentity(record.barcode);
  if (sku) result.push({ kind: 'sku', value: sku });
  if (barcode) result.push({ kind: 'barcode', value: barcode });
  return result;
}

function isSameRecord(left: CatalogIdentityRecord, right: CatalogIdentityRecord): boolean {
  if (left.id && right.id) return left.id === right.id;
  return Boolean(
    left.product_id &&
    right.product_id &&
    left.product_id === right.product_id &&
    normalizeCatalogIdentity(left.sku) === normalizeCatalogIdentity(right.sku) &&
    normalizeCatalogIdentity(left.barcode) === normalizeCatalogIdentity(right.barcode),
  );
}

export function findCatalogIdentityConflicts({
  product,
  variants,
  existingProducts = [],
  existingVariants = [],
}: CatalogIdentityValidationInput): CatalogIdentityConflict[] {
  const conflicts: CatalogIdentityConflict[] = [];
  const seen = new Map<string, CatalogIdentityRecord>();
  const candidates = [product, ...variants];

  for (const candidate of candidates) {
    for (const identity of identities(candidate)) {
      const key = `${identity.kind}:${identity.value}`;
      const previous = seen.get(key);
      if (previous && !isSameRecord(previous, candidate)) {
        conflicts.push({
          ...identity,
          conflictingId: previous.id,
          conflictingProductId: previous.product_id,
        });
      } else {
        seen.set(key, candidate);
      }
    }
  }

  for (const existing of [...existingProducts, ...existingVariants]) {
    if (isSameRecord(existing, product) || variants.some((variant) => isSameRecord(existing, variant))) {
      continue;
    }
    for (const identity of identities(existing)) {
      const key = `${identity.kind}:${identity.value}`;
      if (seen.has(key)) {
        conflicts.push({
          ...identity,
          conflictingId: existing.id,
          conflictingProductId: existing.product_id,
        });
      }
    }
  }

  return conflicts;
}

export function formatCatalogIdentityConflict(conflict: CatalogIdentityConflict): string {
  const label = conflict.kind === 'sku' ? 'SKU' : 'barcode';
  return `${label} "${conflict.value}" sudah digunakan oleh produk atau varian lain dalam tenant ini.`;
}