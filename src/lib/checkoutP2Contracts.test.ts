import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const checkout = readFileSync(resolve(process.cwd(), 'src/pages/CheckoutPage.tsx'), 'utf8');
const paymentPage = readFileSync(resolve(process.cwd(), 'src/pages/PaymentConfirmationPage.tsx'), 'utf8');
const pricingMigration = readFileSync(
  resolve(process.cwd(), 'archive/supabase/migrations/20261013054500_checkout_p1_item_normalization_shipping_contracts.sql'),
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

  it('offers expedition explicitly and presents a real server rate or a clear unavailable state', () => {
    expect(checkout).toContain('value="EXPEDITION" id="expedition"');
    expect(checkout).toContain('Tarif, layanan, dan estimasi diverifikasi dari server');
    expect(checkout).toContain('Tarif ekspedisi belum tersedia untuk tujuan ini');
    expect(checkout).toContain("serverQuote?.shipping_contract?.contract === 'EXPEDITION_PROVIDER_WEIGHT_V1'");
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
});
