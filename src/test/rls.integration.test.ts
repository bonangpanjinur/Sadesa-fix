import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { describe, expect, it, beforeAll, afterAll } from 'vitest';

type RlsConfig = {
  url: string;
  anonKey: string;
  buyerEmail: string;
  buyerPassword: string;
  merchantEmail: string;
  merchantPassword: string;
  merchantOwnId: string;
  merchantOtherId: string;
  buyerOwnOrderId: string;
  buyerOtherOrderId: string;
};

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function loadConfig(): RlsConfig | null {
  const enabled = process.env.RUN_RLS_INTEGRATION === 'true';
  if (!enabled) return null;

  return {
    url: process.env.SUPABASE_TEST_URL || required('VITE_SUPABASE_URL'),
    anonKey: process.env.SUPABASE_TEST_ANON_KEY || required('VITE_SUPABASE_PUBLISHABLE_KEY'),
    buyerEmail: required('RLS_TEST_BUYER_EMAIL'),
    buyerPassword: required('RLS_TEST_BUYER_PASSWORD'),
    merchantEmail: required('RLS_TEST_MERCHANT_EMAIL'),
    merchantPassword: required('RLS_TEST_MERCHANT_PASSWORD'),
    merchantOwnId: required('RLS_TEST_MERCHANT_OWN_ID'),
    merchantOtherId: required('RLS_TEST_MERCHANT_OTHER_ID'),
    buyerOwnOrderId: required('RLS_TEST_BUYER_OWN_ORDER_ID'),
    buyerOtherOrderId: required('RLS_TEST_BUYER_OTHER_ORDER_ID'),
  };
}

const config = loadConfig();
const describeRls = config ? describe : describe.skip;

function client(config: RlsConfig): SupabaseClient {
  return createClient(config.url, config.anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function signIn(config: RlsConfig, email: string, password: string) {
  const supabase = client(config);
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  expect(error, `Unable to sign in integration fixture ${email}`).toBeNull();
  expect(data.session, `No session returned for integration fixture ${email}`).not.toBeNull();
  return supabase;
}

describeRls('RLS integration: multi-tenant isolation', () => {
  let buyer: SupabaseClient;
  let merchant: SupabaseClient;

  beforeAll(async () => {
    if (!config) return;
    buyer = await signIn(config, config.buyerEmail, config.buyerPassword);
    merchant = await signIn(config, config.merchantEmail, config.merchantPassword);
  });

  afterAll(async () => {
    await Promise.all([buyer?.auth.signOut(), merchant?.auth.signOut()]);
  });

  it('buyer can read own order but not another buyer order', async () => {
    const { data, error } = await buyer
      .from('orders')
      .select('id, buyer_id')
      .in('id', [config!.buyerOwnOrderId, config!.buyerOtherOrderId]);

    expect(error).toBeNull();
    expect((data || []).map((row) => row.id)).toContain(config!.buyerOwnOrderId);
    expect((data || []).map((row) => row.id)).not.toContain(config!.buyerOtherOrderId);
  });

  it('merchant can read own merchant record but not another tenant', async () => {
    const { data, error } = await merchant
      .from('merchants')
      .select('id, user_id')
      .in('id', [config!.merchantOwnId, config!.merchantOtherId]);

    expect(error).toBeNull();
    expect((data || []).map((row) => row.id)).toContain(config!.merchantOwnId);
    expect((data || []).map((row) => row.id)).not.toContain(config!.merchantOtherId);
  });

  it('merchant cannot read another tenant orders', async () => {
    const { data, error } = await merchant
      .from('orders')
      .select('id, merchant_id')
      .eq('merchant_id', config!.merchantOtherId)
      .limit(10);

    expect(error).toBeNull();
    expect(data || []).toHaveLength(0);
  });

  it('anonymous client cannot read password reset tokens', async () => {
    const { data, error } = await client(config!)
      .from('password_reset_tokens')
      .select('id, token')
      .limit(1);

    expect(data || []).toHaveLength(0);
    expect(error === null || error?.code === '42501').toBe(true);
  });

  it('authenticated users cannot read password reset tokens', async () => {
    const { data, error } = await buyer
      .from('password_reset_tokens')
      .select('id, token')
      .limit(1);

    expect(data || []).toHaveLength(0);
    expect(error === null || error?.code === '42501').toBe(true);
  });
});

if (!config) {
  describe('RLS integration configuration', () => {
    it('is skipped unless RUN_RLS_INTEGRATION=true and fixtures are configured', () => {
      expect(true).toBe(true);
    });
  });
}
