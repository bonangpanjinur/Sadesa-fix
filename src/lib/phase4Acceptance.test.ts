import { describe, expect, it } from 'vitest';
import { canAccessPOSPath } from '@/components/pos/posPermissions';
import { isRetryableStatus } from '@/hooks/usePOSOfflineSync';
import { getProductUnavailableReason } from './productAvailability';
import { validatePOSPayment, type POSPaymentValidationInput } from './posPaymentValidation';
import { canTransition } from './posStateMachine';
import { deriveDailyReconciliationStatus, reconciliationStatusLabel } from './posDailyReconciliation';

const merchantRoles = ['merchant'] as const;
const paymentDefaults: POSPaymentValidationInput = {
  total: 10000,
  paymentMethod: 'cash',
  paymentAmount: 10000,
  isSplitPayment: false,
  splitAmount1: 0,
  splitAmount2: 0,
  isOnline: true,
  usePoints: false,
  pointsToRedeem: 0,
  minimumRedeemPoints: 100,
};

describe('Fase 4 acceptance matrix: transaksi dan operasional POS', () => {
  it.each([
    ['owner', '/merchant/pos/pengaturan', true],
    ['manager', '/merchant/pos/laporan', true],
    ['kasir', '/merchant/pos/kasir', true],
    ['kasir', '/merchant/pos/pengguna', false],
    ['staff_gudang', '/merchant/pos/stok', true],
    ['staff_gudang', '/merchant/pos/kasir', false],
    ['purchasing', '/merchant/pos/pembelian', true],
    ['finance', '/merchant/pos/kas', true],
    ['auditor', '/merchant/pos/laporan', true],
  ] as const)('permission: %s -> %s is %s', (role, path, expected) => {
    expect(canAccessPOSPath([...merchantRoles], path, role)).toBe(expected);
  });

  it('denies buyers while allowing a merchant without an assigned POS role to onboard', () => {
    expect(canAccessPOSPath(['buyer'], '/merchant/pos/kasir', null)).toBe(false);
    expect(canAccessPOSPath([...merchantRoles], '/merchant/pos/kasir', null)).toBe(true);
  });

  it.each([
    ['cash payment exact', { ...paymentDefaults }, null],
    ['cash underpayment', { ...paymentDefaults, paymentAmount: 9999 }, 'Jumlah bayar kurang dari total'],
    ['split total mismatch', { ...paymentDefaults, isSplitPayment: true, splitAmount1: 4000, splitAmount2: 5000 }, 'Total pembayaran split harus sama dengan total transaksi'],
    ['offline non-cash', { ...paymentDefaults, isOnline: false, paymentMethod: 'qris' }, 'Pembayaran non-tunai memerlukan koneksi internet'],
    ['voucher/points minimum', { ...paymentDefaults, usePoints: true, pointsToRedeem: 50 }, 'Min. tukar 100 poin'],
  ] as const)('payment: %s', (_scenario, input, expected) => {
    expect(validatePOSPayment(input)).toBe(expected);
  });

  it('supports safe retry semantics without repeating a completed workflow transition', () => {
    expect(isRetryableStatus(408)).toBe(true);
    expect(isRetryableStatus(429)).toBe(true);
    expect(isRetryableStatus(503)).toBe(true);
    expect(isRetryableStatus(409)).toBe(false);
    expect(isRetryableStatus(422)).toBe(false);
    expect(canTransition('return', 'draft', 'submitted')).toBe(true);
    expect(canTransition('return', 'completed', 'submitted')).toBe(false);
    expect(canTransition('stock_transfer', 'in_transit', 'received')).toBe(true);
    expect(canTransition('stock_transfer', 'received', 'in_transit')).toBe(false);
  });

  it.each([
    [{ isActive: false, stock: 10, hasQuota: true, isMerchantOpen: true }, 'Produk Nonaktif'],
    [{ isActive: true, stock: 10, hasQuota: false, isMerchantOpen: true }, 'Kuota Habis'],
    [{ isActive: true, stock: 10, hasQuota: true, isMerchantOpen: false }, 'Toko Tutup'],
    [{ isActive: true, stock: 0, hasQuota: true, isMerchantOpen: true }, 'Stok Habis'],
  ] as const)('unavailable reason is explicit: %s', (input, expected) => {
    expect(getProductUnavailableReason(input)).toBe(expected);
  });

  it('keeps a healthy product available when all storefront guards pass', () => {
    expect(getProductUnavailableReason({ isActive: true, stock: 2, hasQuota: true, isMerchantOpen: true })).toBeUndefined();
  });

  it.each([
    [{ unbalancedJournals: 0, unreconciledSessions: 0, shiftDifference: 0 }, 'balanced', 'Seimbang'],
    [{ unbalancedJournals: 0, unreconciledSessions: 1, shiftDifference: 0 }, 'attention', 'Perlu ditinjau'],
    [{ unbalancedJournals: 0, unreconciledSessions: 0, shiftDifference: -1250 }, 'attention', 'Perlu ditinjau'],
    [{ unbalancedJournals: 1, unreconciledSessions: 0, shiftDifference: 0 }, 'unbalanced', 'Jurnal tidak seimbang'],
  ] as const)('daily reconciliation state is explicit: %s', (input, expectedStatus, expectedLabel) => {
    const status = deriveDailyReconciliationStatus(input);
    expect(status).toBe(expectedStatus);
    expect(reconciliationStatusLabel(status)).toBe(expectedLabel);
  });
});