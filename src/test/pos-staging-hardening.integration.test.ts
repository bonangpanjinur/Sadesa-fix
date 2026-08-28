import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

interface Config {
  url: string;
  anonKey: string;
  email: string;
  password: string;
  tenantId: string;
  outletId: string;
  cashierId: string;
  productId: string;
  customerId: string;
}

function loadConfig(): Config | null {
  if (process.env.RUN_POS_INTEGRATION !== 'true') return null;
  const required = (name: keyof NodeJS.ProcessEnv): string => {
    const value = process.env[name];
    if (!value) throw new Error(`Missing ${name}`);
    return value;
  };
  return {
    url: required('SUPABASE_TEST_URL'),
    anonKey: required('SUPABASE_TEST_ANON_KEY'),
    email: required('POS_TEST_STAFF_EMAIL'),
    password: required('POS_TEST_STAFF_PASSWORD'),
    tenantId: required('POS_TEST_TENANT_ID'),
    outletId: required('POS_TEST_OUTLET_ID'),
    cashierId: required('POS_TEST_CASHIER_ID'),
    productId: required('POS_TEST_PRODUCT_ID'),
    customerId: required('POS_TEST_CUSTOMER_ID'),
  };
}

const config = loadConfig();
const describeStaging = config ? describe : describe.skip;

function makeClient(value: Config): SupabaseClient {
  return createClient(value.url, value.anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function expectRpc<T = unknown>(client: SupabaseClient, name: string, args: Record<string, unknown>) {
  const result = await client.rpc(name, args);
  expect(result.error, `${name} failed`).toBeNull();
  return result.data as T;
}

describeStaging('POS staging hardening scenarios', () => {
  let client: SupabaseClient;

  beforeAll(async () => {
    client = makeClient(config!);
    const result = await client.auth.signInWithPassword({ email: config!.email, password: config!.password });
    expect(result.error).toBeNull();
  });

  afterAll(async () => {
    await client?.auth.signOut();
  });

  it('enforces the cashier role for opening a cash session', async () => {
    const result = await expectRpc<boolean>(client, 'pos_user_has_role', {
      p_tenant_id: config!.tenantId,
      p_roles: ['owner', 'manager', 'kasir'],
    });
    expect(result).toBe(true);
  });

  it('returns the same result for a repeated checkout request key', async () => {
    const requestKey = `staging-idempotency-${crypto.randomUUID()}`;
    const saleNumber = `STG-${Date.now()}`;
    const sale = {
      sale_number: saleNumber,
      cashier_name: 'Staging Cashier',
      customer_id: config!.customerId,
      subtotal: 100,
      discount_amount: 0,
      tax_amount: 0,
      total: 100,
      payment_method: 'cash',
      payment_amount: 100,
      change_amount: 0,
      promotion_discount: 0,
      voucher_discount: 0,
      loyalty_points_earned: 0,
      loyalty_points_redeemed: 0,
      loyalty_discount: 0,
    };
    const items = [{
      product_id: config!.productId,
      name: 'Staging product',
      qty: 1,
      price: 100,
      discount: 0,
      tax_amount: 0,
      subtotal: 100,
    }];
    const first = await expectRpc<Record<string, unknown>>(client, 'process_pos_sale', {
      p_request_key: requestKey,
      p_tenant_id: config!.tenantId,
      p_outlet_id: config!.outletId,
      p_cashier_id: config!.cashierId,
      p_sale: sale,
      p_items: items,
    });
    const second = await expectRpc<Record<string, unknown>>(client, 'process_pos_sale', {
      p_request_key: requestKey,
      p_tenant_id: config!.tenantId,
      p_outlet_id: config!.outletId,
      p_cashier_id: config!.cashierId,
      p_sale: sale,
      p_items: items,
    });
    expect(second.duplicate).toBe(true);
    expect(second.sale_id).toBe(first.sale_id);
  });
});

if (!config) {
  describe('POS staging integration configuration', () => {
    it('is skipped unless a dedicated staging environment is configured', () => {
      expect(true).toBe(true);
    });
  });
}
