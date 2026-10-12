import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const read = (file: string) => readFileSync(resolve(process.cwd(), file), 'utf8');
const cartPage = read('src/pages/CartPage.tsx');
const checkoutPage = read('src/pages/CheckoutPage.tsx');

describe('cart selection and multi-merchant checkout contracts', () => {
  it('uses a deduplicated merchant selection plan for the per-store select-all action', () => {
    expect(cartPage).toContain('getMerchantSelectionPlan(');
    expect(cartPage).toContain('selectionPlan.productIdsToToggle.forEach(toggleItemSelection)');
    expect(cartPage).toContain('{selectionPlan.allSelected ?');
  });

  it('derives checkout policy from distinct merchant IDs, not merchant display names or duplicate lines', () => {
    expect(checkoutPage).toContain('getCheckoutMerchantIds(items)');
    expect(checkoutPage).toContain('hasMultipleCheckoutMerchants(merchantIds)');
  });

  it('blocks multi-merchant quoting and order submission while retaining the return-to-cart alert', () => {
    expect(checkoutPage).toContain('!quoteItems.length || !firstMerchantId || hasMultipleMerchants');
    expect(checkoutPage).toContain('if (hasMultipleMerchants) {');
    expect(checkoutPage).toContain('items.length === 0 || hasMultipleMerchants');
    expect(checkoutPage).toContain('checkout.multiStore.action');
  });
});
