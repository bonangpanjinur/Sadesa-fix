import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const checkout = readFileSync(resolve(process.cwd(), 'src/pages/CheckoutPage.tsx'), 'utf8');
const paymentPage = readFileSync(resolve(process.cwd(), 'src/pages/PaymentConfirmationPage.tsx'), 'utf8');
const pricingMigration = readFileSync(
  resolve(process.cwd(), 'archive/supabase/migrations/20261013054500_checkout_p1_item_normalization_shipping_contracts.sql'),
  'utf8',
);
const authoritativeMigration = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20261014090000_checkout_authoritative_create_and_line_quotes.sql'),
  'utf8',
);
const authoritativeBootstrap = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/115_20261014090000_to_20261014090000.sql'),
  'utf8',
);

describe('checkout P2 readiness and presentation contracts', () => {
  it('fails closed until payment settings for the selected merchant have loaded', () => {
    expect(checkout).toContain('isCheckoutPaymentSettingsReady(');
    expect(checkout).toContain('if (!paymentSettingsReady)');
    expect(checkout).toContain('!paymentSettingsReady || !paymentReady');
    expect(checkout).toContain("status: 'loading'");
    expect(checkout).toContain('Pengaturan pembayaran gagal dimuat');
  });

  it('keeps expedition hidden until the supported rollout is enabled', () => {
    expect(checkout).toContain('Expedition remains supported server-side for a later rollout');
    expect(checkout).toContain("deliveryType === 'EXPEDITION'");
    expect(checkout).not.toContain('value="EXPEDITION" id="expedition"');
    expect(checkout).toContain('deliveryRestriction.requiresExpedition');
  });

  it('renders the server quote total before submission and the persisted order total on payment page', () => {
    expect(checkout).toContain('const total = serverQuote?.total ??');
    expect(checkout).toContain("serverQuote ? formatCurrency(total) : '—'");
    expect(checkout).toContain('p_items: quoteItems');
    expect(checkout).toContain('p_delivery_type: deliveryType');
    expect(checkout).not.toContain('p_total:');
    expect(paymentPage).toContain('formatPrice(order.total)');
    expect(pricingMigration).toContain('public.marketplace_shipping_contract_quote(');
    expect(pricingMigration).toContain("'total', v_total");
  });

  it('shows a waiting-for-instructions state instead of telling buyers to pay without merchant details', () => {
    expect(paymentPage).toContain('Menunggu instruksi pembayaran');
    expect(paymentPage).toContain('!isPaymentComplete && !hasPaymentInstructions');
    expect(paymentPage).toContain('!isPaymentComplete && hasPaymentInstructions && <motion.div');
  });

  it('clears purchased cart lines before redirecting to a successful online invoice', () => {
    const invoiceRedirect = checkout.indexOf('window.location.href = invoice.invoice_url;');
    const cartClear = checkout.lastIndexOf('selectedItems.forEach(item =>', invoiceRedirect);
    expect(invoiceRedirect).toBeGreaterThan(-1);
    expect(cartClear).toBeGreaterThan(-1);
    expect(cartClear).toBeLessThan(invoiceRedirect);
    expect(checkout).toContain('setMerchantLocation(null);');
  });

  it('keeps the database create path aligned with the single-merchant checkout policy', () => {
    expect(authoritativeMigration).toContain("IF v_merchant_count <> 1 THEN");
    expect(authoritativeMigration).toContain("RAISE EXCEPTION 'Invalid delivery contact'");
    expect(authoritativeMigration).toContain("RAISE EXCEPTION 'Delivery address is required'");
  });

  it('validates delivery address and coordinate ranges in both create RPCs and bootstrap', () => {
    for (const migration of [authoritativeMigration, authoritativeBootstrap]) {
      expect(migration.match(/RAISE EXCEPTION 'Delivery address is required'/g)?.length).toBe(2);
      expect(migration.match(/jsonb_typeof\(p_delivery->'lat'\)/g)?.length).toBe(2);
      // The quote helper has its own guard too; the two create RPCs must each
      // contribute at least one range check.
      expect(migration.match(/v_delivery_lat < -90/g)?.length).toBeGreaterThanOrEqual(2);
      expect(migration.match(/v_delivery_lng < -180/g)?.length).toBeGreaterThanOrEqual(2);
    }
  });

  it('keeps guest payment contract transfer-only in source and bootstrap', () => {
    for (const migration of [authoritativeMigration, authoritativeBootstrap]) {
      expect(migration).toContain("IF p_payment_method <> 'TRANSFER' THEN");
      expect(migration).not.toContain("IF p_payment_method NOT IN ('TRANSFER', 'ONLINE') THEN");
    }
  });
});
