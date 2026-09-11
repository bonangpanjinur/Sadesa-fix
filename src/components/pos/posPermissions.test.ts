import { describe, expect, it } from 'vitest';
import { canAccessPOSPath } from './posPermissionConfig';

const merchant = ['merchant'] as const;

function access(path: string, posRole: Parameters<typeof canAccessPOSPath>[2]) {
  return canAccessPOSPath([...merchant], path, posRole);
}

describe('POS permission registry', () => {
  it('allows cashier operations but denies finance and administration pages', () => {
    expect(access('/pos/kasir', 'kasir')).toBe(true);
    expect(access('/merchant/pos', 'kasir')).toBe(true);
    expect(access('/merchant/pos', 'finance')).toBe(true);
    expect(access('/merchant/pos/kasir', 'finance')).toBe(false);
    expect(access('/pos/transaksi', 'kasir')).toBe(true);
    expect(access('/pos/kas', 'kasir')).toBe(false);
    expect(access('/pos/pengguna', 'kasir')).toBe(false);
    expect(access('/pos/pengaturan', 'kasir')).toBe(false);
  });

  it('allows warehouse staff inventory pages but denies cashier and finance pages', () => {
    expect(access('/pos/stok', 'staff_gudang')).toBe(true);
    expect(access('/pos/produk', 'staff_gudang')).toBe(true);
    expect(access('/pos/kasir', 'staff_gudang')).toBe(false);
    expect(access('/pos/laporan/laba-rugi', 'staff_gudang')).toBe(false);
  });

  it('allows finance reporting without granting access administration', () => {
    expect(access('/pos/laporan', 'finance')).toBe(true);
    expect(access('/pos/laporan/cashflow', 'finance')).toBe(true);
    expect(access('/pos/penggajian', 'finance')).toBe(true);
    expect(access('/pos/akses', 'finance')).toBe(false);
  });

  it('allows onboarding only for application-level POS roles', () => {
    expect(canAccessPOSPath(['merchant'], '/pos/setup', null)).toBe(true);
    expect(canAccessPOSPath(['buyer'], '/pos/setup', null)).toBe(false);
    expect(access('/pos/not-registered', 'owner')).toBe(false);
  });

  it('does not let buyers or unknown routes enter the POS namespace', () => {
    expect(canAccessPOSPath(['buyer'], '/merchant/pos', null)).toBe(false);
    expect(canAccessPOSPath(['buyer'], '/merchant/pos/kasir', null)).toBe(false);
    expect(canAccessPOSPath(['merchant'], '/merchant/pos/unknown', 'owner')).toBe(false);
  });
});
