import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const page = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminSettingsPage.tsx'), 'utf8');
const walletPage = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminWalletCommissionPage.tsx'), 'utf8');

describe('admin courier commission source contract', () => {
  it('does not expose the legacy app_settings courier commission as an editable source', () => {
    expect(page).not.toContain("getSetting('courier_commission')");
    expect(page).not.toContain("updateAppSetting('courier_commission'");
    expect(page).toContain('/admin/wallet-commissions');
    expect(page).toContain('commission_fee_settings');
  });

  it('keeps the wallet commission page on the payout source of truth', () => {
    expect(walletPage).toContain("supabase.from('commission_fee_settings' as never).select('*')");
    expect(walletPage).toContain("supabase.from('commission_fee_settings' as never)");
    expect(walletPage).toContain('charge_courier_delivery');
  });
});
