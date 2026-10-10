import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const page = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminWalletCommissionPage.tsx'), 'utf8');

describe('admin commission wallet UX contract', () => {
  it('guides admins through legacy reconciliation, wallet funding, and fee setup', () => {
    expect(page).toContain('Alur aman sebelum komisi diaktifkan');
    expect(page).toContain('Top-up dianjurkan lebih dulu');
    expect(page).toContain('Tinjau permintaan lama');
    expect(page).toContain('Lihat antrean top-up');
    expect(page).toContain('Atur tarif');
    expect(page).toContain('Saldo kuota lama tidak dikonversi');
  });

  it('explains debt consequences and distinguishes funded wallets from low or empty wallets', () => {
    expect(page).toContain('Jika saldo tidak cukup saat transaksi selesai');
    expect(page).toContain('Wallet aktif siap digunakan');
    expect(page).toContain('Saldo rendah atau nol');
    expect(page).toContain("Number(wallet.balance_rupiah || 0) > 0 && Number(wallet.debt_rupiah || 0) === 0");
  });
});
