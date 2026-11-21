import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/135_20261118180000_static_qris_and_checkout_overload_repair.sql'),
  'utf8',
);
const manualPaymentMigration = readFileSync(
  resolve(process.cwd(), 'supabase/bootstrap/136_20261118183000_manual_qris_or_bank_payment.sql'),
  'utf8',
);
const settingsPage = readFileSync(
  resolve(process.cwd(), 'src/pages/merchant/MerchantSettingsPage.tsx'),
  'utf8',
);
const dynamicQrisApplication = readFileSync(
  resolve(process.cwd(), 'src/components/merchant/MerchantQrisApplicationCard.tsx'),
  'utf8',
);

describe('static merchant QRIS contract', () => {
  it('removes stale checkout overloads while preserving the canonical key-based signature', () => {
    expect(migration).toContain('DROP FUNCTION IF EXISTS public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text, text)');
    expect(migration).toContain('DROP FUNCTION IF EXISTS public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric)');
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text)');
  });

  it('scopes static QRIS storage writes to the merchant-owned prefix', () => {
    expect(migration).toContain("'qris-merchant-static'");
    expect(migration).toContain("(storage.foldername(name))[1] = 'qris'");
    expect(migration).toContain("m.id::text = (storage.foldername(name))[2]");
    expect(migration).toContain('m.user_id = auth.uid() OR public.is_admin()');
    expect(migration).toContain('Hanya pemilik merchant aktif yang dapat mengatur QRIS statis');
  });

  it('renders the merchant upload and persists its URL through settings RPC', () => {
    expect(settingsPage).toContain('bucket="qris-merchant-static"');
    expect(settingsPage).toContain('path={`qris/${merchant.id}`}');
    expect(settingsPage).toContain('qris_image_url: qrisImageUrl || null');
    expect(settingsPage).toContain('QRIS statis, dan ajukan aktivasi QRIS Dinamis GDC');
    expect(settingsPage).toContain('MerchantQrisApplicationCard');
    expect(settingsPage).toContain('bankName={merchant.bank_name}');
    expect(dynamicQrisApplication).toContain('Pengajuan QRIS Dinamis GDC');
    expect(dynamicQrisApplication).toContain('application.gdc_mpm_enabled === true');
  });

  it('keeps manual QRIS or bank transfer on the existing proof workflow', () => {
    expect(manualPaymentMigration).toContain('Merchant belum mengatur QRIS atau rekening bank');
    expect(manualPaymentMigration).toContain("'bank_account_number', v_merchant.bank_account_number");
    expect(manualPaymentMigration).toContain("'qris_image_url', v_merchant.qris_image_url");
    expect(manualPaymentMigration).toContain("'bank_account_number', v_order.payment_destination_snapshot->>'bank_account_number'");
  });
});
