export interface MerchantStoreLinkSource {
  id: string;
  slug: string | null;
}

export function getMerchantStorePath(merchant: MerchantStoreLinkSource): string {
  return `/merchant/${encodeURIComponent(merchant.slug || merchant.id)}`;
}
