export interface ViewedProduct {
  id: string;
  name: string;
  price: number;
  image_url: string | null;
  merchant_name: string;
  viewed_at: number;
}

export const RECENTLY_VIEWED_STORAGE_KEY = 'recently_viewed_products';

export function addToRecentlyViewed(product: {
  id: string;
  name: string;
  price: number;
  image?: string;
  merchantName?: string;
}): void {
  try {
    const existing: ViewedProduct[] = JSON.parse(
      localStorage.getItem(RECENTLY_VIEWED_STORAGE_KEY) || '[]'
    );
    const filtered = existing.filter((item) => item.id !== product.id);
    filtered.unshift({
      id: product.id,
      name: product.name,
      price: product.price,
      image_url: product.image || null,
      merchant_name: product.merchantName || '',
      viewed_at: Date.now(),
    });
    localStorage.setItem(
      RECENTLY_VIEWED_STORAGE_KEY,
      JSON.stringify(filtered.slice(0, 50))
    );
  } catch {
    // Ignore local-storage failures.
  }
}
