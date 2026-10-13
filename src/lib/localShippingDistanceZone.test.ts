import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20261013183000_local_shipping_distance_zone_surcharge.sql'),
  'utf8',
);
const validationMigration = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20261013210000_validate_shipping_settings_and_snapshot_courier_fees.sql'),
  'utf8',
);
const checkout = readFileSync(resolve(process.cwd(), 'src/pages/CheckoutPage.tsx'), 'utf8');
const adminSettings = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminSettingsPage.tsx'), 'utf8');

describe('local shipping distance plus zone surcharge contract', () => {
  it('uses distance as the base and zone fee as an additional surcharge', () => {
    expect(migration).toContain("'contract', 'LOCAL_COURIER_DISTANCE_ZONE_V1'");
    expect(migration).toContain("+ v_zone_fee");
    expect(migration).toContain("'zone_surcharge', v_zone_fee");
    expect(migration).toContain("WHERE key = 'shipping_zones'");
  });

  it('uses the same zone selection and surcharge in the checkout estimate', () => {
    expect(checkout).toContain("'shipping_base_fee', 'shipping_zones'");
    expect(checkout).toContain('const zoneSurcharge = Math.max(0, zone?.fee ?? 0);');
    expect(checkout).toContain('baseFee + Math.round(distanceKm * perKmFee) + zoneSurcharge');
  });

  it('documents that the admin zone fee is for difficult roads', () => {
    expect(adminSettings).toContain('surcharge untuk jalan yang lebih sulit');
    expect(adminSettings).toContain('Surcharge zona');
  });

  it('enforces valid shipping rates and ordered, non-overlapping zones in the database', () => {
    expect(validationMigration).toContain('validate_shipping_pricing_setting');
    expect(validationMigration).toContain('app_settings_validate_shipping_pricing');
    expect(validationMigration).toContain('v_value < 0 OR trunc(v_value) <> v_value');
    expect(validationMigration).toContain('v_distance <= v_previous_distance');
    expect(validationMigration).toContain('v_fee < 0 OR trunc(v_fee) <> v_fee');
  });

  it('snapshots courier delivery commission from the same gross base used by the wallet charge', () => {
    expect(validationMigration).toContain('orders_snapshot_courier_delivery_earnings');
    expect(validationMigration).toContain('NULLIF(NEW.courier_earning_estimate, 0), NEW.shipping_cost');
    expect(validationMigration).toContain('NEW.courier_platform_fee := CASE');
    expect(validationMigration).toContain('charge_courier_delivery');
  });

  it('records shipping-setting changes in an admin-readable audit log', () => {
    expect(validationMigration).toContain('shipping_pricing_change_log');
    expect(validationMigration).toContain('shipping_pricing_change_log_admin_read');
    expect(validationMigration).toContain('auth.uid()');
    expect(validationMigration).toContain('AFTER INSERT OR UPDATE OR DELETE ON public.app_settings');
  });
});
