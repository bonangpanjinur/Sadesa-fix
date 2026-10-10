import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { hasMerchantPaymentSetup } from './merchantPaymentSetup';

const dashboardPage = readFileSync(resolve(process.cwd(), 'src/pages/merchant/MerchantDashboardPage.tsx'), 'utf8');
const paymentSetupMigration = readFileSync(
  resolve(process.cwd(), 'archive/supabase/migrations/20261010150000_merchant_payment_setup_push_alert.sql'),
  'utf8',
);

describe('merchant payment setup reminder', () => {
  it('accepts a complete bank account or a QRIS image', () => {
    expect(hasMerchantPaymentSetup({
      bank_name: 'BCA',
      bank_account_number: '1234567890',
      bank_account_name: 'Warung Maju',
      qris_image_url: null,
    })).toBe(true);
    expect(hasMerchantPaymentSetup({
      bank_name: null,
      bank_account_number: null,
      bank_account_name: null,
      qris_image_url: 'https://example.test/qris.png',
    })).toBe(true);
  });

  it('requires all bank fields and treats whitespace as empty', () => {
    expect(hasMerchantPaymentSetup({
      bank_name: 'BCA',
      bank_account_number: null,
      bank_account_name: 'Warung Maju',
      qris_image_url: null,
    })).toBe(false);
    expect(hasMerchantPaymentSetup({
      bank_name: ' ',
      bank_account_number: '1234567890',
      bank_account_name: 'Warung Maju',
      qris_image_url: ' ',
    })).toBe(false);
  });

  it('shows a dashboard action and uses the shared background push queue', () => {
    expect(dashboardPage).toContain('merchant-payment-setup-warning');
    expect(dashboardPage).toContain("navigate('/merchant/settings')");
    expect(paymentSetupMigration).toContain('payment_setup_push_alerted_at');
    expect(paymentSetupMigration).toContain('AFTER INSERT OR UPDATE ON public.push_subscriptions');
    expect(paymentSetupMigration).toContain("'merchant_payment_setup_required'");
    expect(paymentSetupMigration).toContain("'/merchant/settings'");
    expect(paymentSetupMigration).toContain('public.notification_delivery_jobs');
  });
});
