import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { describe, expect, it, beforeAll, afterAll } from 'vitest';

type Config = {
  url: string;
  anonKey: string;
  email: string;
  password: string;
  tenantId: string;
  outletId: string;
  productId: string;
  customerId: string;
  cashierId: string;
};

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function loadConfig(): Config | null {
  if (process.env.RUN_POS_INTEGRATION !== 'true') return null;
  return {
    url: process.env.SUPABASE_TEST_URL || required('VITE_SUPABASE_URL'),
    anonKey: process.env.SUPABASE_TEST_ANON_KEY || required('VITE_SUPABASE_PUBLISHABLE_KEY'),
    email: required('POS_TEST_STAFF_EMAIL'),
    password: required('POS_TEST_STAFF_PASSWORD'),
    tenantId: required('POS_TEST_TENANT_ID'),
    outletId: required('POS_TEST_OUTLET_ID'),
    productId: required('POS_TEST_PRODUCT_ID'),
    customerId: required('POS_TEST_CUSTOMER_ID'),
    cashierId: required('POS_TEST_CASHIER_ID'),
  };
}

const config = loadConfig();
const describeIntegration = config ? describe : describe.skip;

function client(value: Config): SupabaseClient {
  return createClient(value.url, value.anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
}

async function rpc(clientValue: SupabaseClient, functionName: string, args: Record<string, unknown>) {
  const result = await clientValue.rpc(functionName, args);
  expect(result.error, `${functionName} failed`).toBeNull();
  return result.data as Record<string, unknown>;
}

describeIntegration('POS price book and loyalty atomic integration', () => {
  let supabase: SupabaseClient;

  beforeAll(async () => {
    supabase = client(config!);
    const { data, error } = await supabase.auth.signInWithPassword({ email: config!.email, password: config!.password });
    expect(error).toBeNull();
    expect(data.session).not.toBeNull();
  });

  afterAll(async () => {
    await supabase?.auth.signOut();
  });

  it('resolves a tenant/outlet-scoped effective price through the RPC', async () => {
    const result = await rpc(supabase, 'get_effective_pos_price', {
      p_tenant_id: config!.tenantId,
      p_outlet_id: config!.outletId,
      p_product_id: config!.productId,
      p_variant_id: null,
      p_segment: 'retail',
    });
    expect(Number(result)).toBeGreaterThanOrEqual(0);
  });

  it('is idempotent for repeated earn requests with the same key', async () => {
    const key = `integration-earn-${crypto.randomUUID()}`;
    const first = await rpc(supabase, 'earn_pos_loyalty_points', {
      p_tenant_id: config!.tenantId,
      p_customer_id: config!.customerId,
      p_amount: 100000,
      p_sale_id: null,
      p_actor_id: config!.cashierId,
      p_idempotency_key: key,
    });
    const second = await rpc(supabase, 'earn_pos_loyalty_points', {
      p_tenant_id: config!.tenantId,
      p_customer_id: config!.customerId,
      p_amount: 100000,
      p_sale_id: null,
      p_actor_id: config!.cashierId,
      p_idempotency_key: key,
    });
    expect(second.duplicate).toBe(true);
    expect(second.entry_id).toBe(first.entry_id);
  });

  it('serializes concurrent redemption so both calls cannot spend the same balance', async () => {
    const { data: account, error } = await supabase
      .from('pos_loyalty_points')
      .select('total_points, used_points, expired_points')
      .eq('tenant_id', config!.tenantId)
      .eq('customer_id', config!.customerId)
      .maybeSingle();
    expect(error).toBeNull();
    const balance = Math.max(0, Number(account?.total_points || 0) - Number(account?.used_points || 0) - Number(account?.expired_points || 0));
    if (balance < 1) return;

    const attempts = await Promise.allSettled([1, 2].map((suffix) => supabase.rpc('redeem_pos_loyalty_points', {
      p_tenant_id: config!.tenantId,
      p_customer_id: config!.customerId,
      p_points: balance,
      p_sale_id: null,
      p_actor_id: config!.cashierId,
      p_idempotency_key: `integration-redeem-${crypto.randomUUID()}-${suffix}`,
    })));
    const succeeded = attempts.filter((attempt) => attempt.status === 'fulfilled' && !attempt.value.error);
    expect(succeeded).toHaveLength(1);
  });
});

if (!config) {
  describe('POS integration configuration', () => {
    it('is skipped unless RUN_POS_INTEGRATION=true and dedicated staging fixtures are configured', () => {
      expect(true).toBe(true);
    });
  });
}
