import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const checkout = readFileSync(resolve(process.cwd(), 'src/pages/CheckoutPage.tsx'), 'utf8');
const shippingMigration = readFileSync(
  resolve(process.cwd(), 'archive/supabase/migrations/20261013052500_marketplace_checkout_shipping_quote.sql'),
  'utf8',
);
const guestCheckout = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/65_20261002170000_guest_checkout_phase1.sql'),
  'utf8',
);
const p1Migration = readFileSync(
  resolve(process.cwd(), 'archive/supabase/migrations/20261013054500_checkout_p1_item_normalization_shipping_contracts.sql'),
  'utf8',
);
const currentPricingMigration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/115_20261014090000_to_20261014090000.sql'),
  'utf8',
);
const normalizerRepairMigration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/117_20261014093000_to_20261014093000.sql'),
  'utf8',
);
const shippingColumnsRepairMigration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/118_20261014104000_to_20261014104000.sql'),
  'utf8',
);

describe('checkout shipping distance consistency contract', () => {
  it('requests a server quote and renders its authoritative amounts', () => {
    expect(checkout).toContain("supabase.rpc('quote_marketplace_checkout' as never");
    expect(checkout).toContain('const displaySubtotal = serverQuote?.subtotal ?? subtotal');
    expect(checkout).toContain('const shippingCost = serverQuote?.shipping_cost ?? estimatedShippingCost');
    expect(checkout).toContain('const total = serverQuote?.total ??');
    expect(checkout).toContain('!checkoutQuoteReady');
    expect(checkout).toContain('formatCurrency(displaySubtotal)');
    expect(checkout).not.toContain('p_distance_km: deliveryType');
  });

  it('uses coordinate-derived server distance in both the quote and authenticated order path', () => {
    expect(shippingMigration).toContain('CREATE OR REPLACE FUNCTION public.quote_marketplace_checkout');
    expect(shippingMigration).toContain('v_distance := 6371 * 2 * asin');
    expect(shippingMigration).toContain('v_server_distance := 6371 * 2 * asin');
    expect(shippingMigration).toContain('p_items, p_delivery, p_delivery_type, p_payment_method, p_voucher_id, v_server_distance');
    expect(guestCheckout).toContain('v_server_distance := 6371 * 2 * asin');
    expect(guestCheckout).toContain('v_shipping, v_subtotal, v_total');
  });

  it('fails closed while a quote or its driving distance is not ready', () => {
    expect(checkout).toContain('if (!checkoutQuoteReady || checkoutQuoteLoading)');
    expect(checkout).toContain('if (!distanceReady)');
    expect(checkout).toContain('!checkoutQuoteReady || routeCalculationPending || !distanceReady');
  });

  it('normalizes duplicate products and toppings before authoritative checkout and stock reservation', () => {
    expect(checkout).toContain('normalizeCheckoutProductQuantities(items.flatMap');
    expect(checkout).toContain('p_items: quoteItems');
    expect(p1Migration).toContain('CREATE OR REPLACE FUNCTION public.normalize_marketplace_checkout_items');
    expect(p1Migration).toContain('GROUP BY i.product_id, i.variant_id');
    expect(p1Migration).toContain('public.normalize_marketplace_checkout_items(p_items)');
    expect(p1Migration).toContain('reserve_marketplace_stock_unaggregated');
    expect(p1Migration).toContain('reserve_marketplace_stock_guest_unaggregated');
  });

  it('ships a repair for databases where the quote RPC exists without its normalizer dependency', () => {
    expect(normalizerRepairMigration).toContain('CREATE OR REPLACE FUNCTION public.normalize_marketplace_checkout_items');
    expect(normalizerRepairMigration).toContain('jsonb_to_recordset(p_items)');
    expect(normalizerRepairMigration).toContain('REVOKE ALL ON FUNCTION public.normalize_marketplace_checkout_items(jsonb)');
  });

  it('repairs the orders and products columns required by the shipping contract RPCs', () => {
    expect(shippingColumnsRepairMigration).toContain('ADD COLUMN IF NOT EXISTS shipping_pricing_contract jsonb');
    expect(shippingColumnsRepairMigration).toContain('ADD COLUMN IF NOT EXISTS merchant_delivery_fee_contract text');
    expect(shippingColumnsRepairMigration).toContain('ADD COLUMN IF NOT EXISTS shipping_weight_kg numeric');
  });

  it('routes the quote and both checkout creation paths through one shipping contract calculator', () => {
    expect(currentPricingMigration).toContain('CREATE OR REPLACE FUNCTION public.quote_marketplace_checkout');
    expect(currentPricingMigration).toContain('CREATE OR REPLACE FUNCTION public.create_marketplace_checkout');
    expect(currentPricingMigration).toContain('CREATE OR REPLACE FUNCTION public.create_guest_marketplace_checkout');
    expect(currentPricingMigration.match(/v_(?:shipping_contract|contract) := public\.marketplace_shipping_contract_quote\(/g)).toHaveLength(3);
  });

  it('uses distinct local, merchant self-delivery, and provider-weight expedition contracts', () => {
    expect(p1Migration).toContain('LOCAL_COURIER_DISTANCE_V1');
    expect(p1Migration).toContain('MERCHANT_SELF_DELIVERY_PLATFORM_PERCENT_V1');
    expect(p1Migration).toContain('EXPEDITION_PROVIDER_WEIGHT_V1');
    expect(p1Migration).toContain('marketplace_expedition_rate_cards');
    expect(p1Migration).toContain('shipping_weight_kg');
    expect(p1Migration).toContain("'city_id'");
    expect(p1Migration).toContain('shipping_pricing_contract = v_contract');
  });
});
