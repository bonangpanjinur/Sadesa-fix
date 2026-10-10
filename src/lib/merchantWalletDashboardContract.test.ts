import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(resolve(process.cwd(), path), 'utf8');
const dashboard = read('src/pages/merchant/MerchantDashboardPage.tsx');
const walletPage = read('src/pages/CommissionWalletPage.tsx');
const sidebar = read('src/components/merchant/MerchantSidebar.tsx');
const featureTour = read('src/lib/featureTour.ts');

describe('merchant wallet dashboard contract', () => {
  it('shows the live wallet balance and links to the detailed balance page', () => {
    expect(dashboard).toContain('data-testid="merchant-quick-actions"');
    expect(dashboard).toContain("label: 'Pesanan'");
    expect(dashboard).toContain("label: 'Produk'");
    expect(dashboard).toContain("label: 'Stok'");
    expect(dashboard).toContain("queryKey: ['merchant-wallet-dashboard', merchant?.id]");
    expect(dashboard).toContain('data-testid="merchant-wallet-balance"');
    expect(dashboard).toContain("navigate('/merchant/wallet')");
    expect(sidebar).toContain("label: 'Saldo', href: '/merchant/wallet'");
    expect(walletPage).toContain("ownerType === 'MERCHANT' ? 'Saldo' : 'Saldo Komisi Ojek'");
    expect(dashboard).not.toContain('<QuotaAlertBanner />');
    expect(dashboard).not.toContain('<QuotaStatusCard />');
  });

  it('explains debt, low balance, fee-off and unavailable-wallet states', () => {
    expect(dashboard).toContain('Pesanan baru ditahan sampai tagihan lunas');
    expect(dashboard).toContain('Saldo mulai menipis');
    expect(dashboard).toContain('Saat tarif komisi aktif, wallet harus memiliki saldo positif');
    expect(dashboard).toContain('Tarif komisi belum aktif; saldo tetap dapat dipantau');
    expect(dashboard).toContain('Saldo belum dapat dimuat');
    expect(featureTour).toContain("title: 'Saldo'");
  });
});
