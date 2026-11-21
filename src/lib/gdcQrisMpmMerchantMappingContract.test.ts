import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// Source-contract tests: they pin the rules that keep store A's order from ever
// using store B's GDC identity. They do not replace the staging end-to-end test
// with two real sandbox mappings (see the runbook).
const source = readFileSync(resolve(process.cwd(), 'supabase/functions/gdc-qris-mpm/index.ts'), 'utf8');
const lines = source.split('\n');

function between(start: string, end: string): string {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from);
  expect(from, `missing marker: ${start}`).toBeGreaterThan(-1);
  expect(to, `missing marker: ${end}`).toBeGreaterThan(from);
  return source.slice(from, to);
}

describe('GDC QRIS MPM per-merchant mapping contract', () => {
  it('loads the order only for the authenticated buyer', () => {
    expect(source).toMatch(/\.eq\('id', input\.order_id\)\.eq\('buyer_id', authData\.user\.id\)/);
  });

  it('selects the checkout mapping strictly by orders.merchant_id and only when active and enabled', () => {
    const checkoutMapping = between(
      ".from('qris_applications')\n    .select('gdc_merchant_id, gdc_account_number, gdc_mpm_enabled",
      '.maybeSingle()',
    );
    expect(checkoutMapping).toContain(".eq('merchant_id', order.merchant_id)");
    expect(checkoutMapping).toContain(".eq('status', 'ACTIVE')");
    expect(checkoutMapping).toContain(".eq('gdc_mpm_enabled', true)");
  });

  it('takes MID and account number from the same mapping row in every generate request', () => {
    const merchantIds = lines.filter((line) => line.includes('merchantId:'));
    const accountNumbers = lines.filter((line) => line.includes('accountNumber:'));
    expect(merchantIds.length).toBeGreaterThanOrEqual(2); // admin preview + checkout
    for (const line of merchantIds) expect(line).toContain('application.gdc_merchant_id');
    for (const line of accountNumbers) expect(line).toContain('application.gdc_account_number');
  });

  it('never falls back to a global MID, account number, or browser-supplied value', () => {
    expect(source).not.toMatch(/Deno\.env\.get\(['"]GDC_(MERCHANT_ID|MID|ACCOUNT_NUMBER)['"]\)/);
    expect(source).not.toMatch(/input\.(merchant_id|merchantId|mid|account_number|accountNumber|amount)/);
    expect(source).toContain('const amount = Number(order.total)');
  });

  it('stores the order merchant on the payment and rejects a mismatching existing payment', () => {
    expect(source).toContain('merchant_id: order.merchant_id');
    expect(source).toContain('payment.merchant_id !== order.merchant_id');
  });
});
