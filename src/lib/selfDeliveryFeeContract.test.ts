import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'archive/supabase/migrations/20261013050000_self_delivery_admin_fee.sql'),
  'utf8',
);
const lifecycleHardeningMigration = readFileSync(
  resolve(process.cwd(), 'archive/supabase/migrations/20261013220000_self_delivery_lifecycle_hardening.sql'),
  'utf8',
);
const adminPage = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminWalletCommissionPage.tsx'), 'utf8');

describe('self-delivery admin fee contract', () => {
  it('starts free and does not use the old two-attempt rule or 10% fallback', () => {
    expect(migration).toContain('"percent": 0, "enabled": false');
    expect(migration).not.toContain('v_attempt > 2');
    expect(migration).not.toContain('COALESCE((value->>\'percent\')::numeric, 10)');
  });

  it('snapshots the configured fee on the first self-delivery transition', () => {
    expect(migration).toContain("IF p_to_status = 'DELIVERING' THEN");
    expect(migration).toContain('self_delivery_fee_amount = v_fee_amount');
    expect(migration).toContain('percent_snapshot, fee_amount, status');
    expect(migration).toContain('IF NOT EXISTS (');
    expect(migration).toContain('l.order_id = p_order_id');
    expect(migration).toContain("v_fee_status := CASE WHEN v_fee_enabled AND v_fee_amount > 0 THEN 'DUE' ELSE 'WAIVED' END");
  });

  it('exposes an admin control for percentage and activation', () => {
    expect(adminPage).toContain('Antar Sendiri — Fee Admin');
    expect(adminPage).toContain('self-delivery-fee-percent');
    expect(adminPage).toContain('self-delivery-fee-enabled');
    expect(adminPage).toContain("eq('key', 'self_delivery_fee')");
  });

  it('makes a committed self-delivery transition safe to retry without a second attempt or ledger row', () => {
    expect(lifecycleHardeningMigration).toContain("v_from = 'DELIVERING'");
    expect(lifecycleHardeningMigration).toContain('AND COALESCE(v_order.is_self_delivery, false)');
    expect(lifecycleHardeningMigration).toContain('RETURN v_order;');
    expect(lifecycleHardeningMigration).toContain('WHERE NOT EXISTS (');
    expect(lifecycleHardeningMigration).toContain('l.order_id = p_order_id');
  });

  it('waives a due self-delivery fee when the order is canceled or refunded', () => {
    expect(lifecycleHardeningMigration).toContain("NEW.status IN ('CANCELED', 'REFUNDED')");
    expect(lifecycleHardeningMigration).toContain("SET status = 'WAIVED'");
    expect(lifecycleHardeningMigration).toContain("SET self_delivery_fee_status = 'WAIVED'");
    expect(lifecycleHardeningMigration).toContain("v_from = 'DELIVERING' AND COALESCE(v_order.is_self_delivery, false) AND p_to_status = 'CANCELED'");
    expect(lifecycleHardeningMigration).toContain("self_delivery_fee_status = 'DUE' THEN 'WAIVED'");
  });
});
