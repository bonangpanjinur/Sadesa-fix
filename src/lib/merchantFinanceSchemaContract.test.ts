import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const financePage = readFileSync(resolve(process.cwd(), 'src/pages/merchant/MerchantFinancePage.tsx'), 'utf8');
const financeExport = readFileSync(resolve(process.cwd(), 'src/components/merchant/MerchantFinanceExportActions.tsx'), 'utf8');
const receipt = readFileSync(resolve(process.cwd(), 'src/components/merchant/MerchantTransactionReceiptButton.tsx'), 'utf8');

describe('merchant finance orders schema contract', () => {
  it('does not query the POS-only voucher_discount field from marketplace orders', () => {
    const ordersSelect = financePage.match(/from\('orders'\)\.select\('([^']+)'/);
    expect(ordersSelect?.[1]).toContain('subtotal');
    expect(ordersSelect?.[1]).not.toContain('voucher_discount');
    expect(financePage).not.toContain('order.voucher_discount');
  });

  it('does not report an unsupported order discount as a real zero-valued finance field', () => {
    expect(financePage).not.toContain('>Diskon</p>');
    expect(financeExport).not.toContain("'Diskon'");
    expect(financeExport).not.toContain('row.discount');
    expect(receipt).not.toContain("['Diskon'");
    expect(receipt).not.toContain('order.discount');
  });
});
