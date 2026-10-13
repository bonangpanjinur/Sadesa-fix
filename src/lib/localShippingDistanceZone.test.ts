import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20261013183000_local_shipping_distance_zone_surcharge.sql'),
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
});
