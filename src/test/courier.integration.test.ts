import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { describe, expect, it, beforeAll, afterAll } from 'vitest';

type Config = {
  url: string; anonKey: string;
  merchantEmail: string; merchantPassword: string;
  buyerEmail: string; buyerPassword: string;
  courierEmail: string; courierPassword: string;
  orderId: string; courierId: string; otherCourierId: string;
};

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function loadConfig(): Config | null {
  if (process.env.RUN_COURIER_INTEGRATION !== 'true') return null;
  return {
    url: process.env.SUPABASE_TEST_URL || required('VITE_SUPABASE_URL'),
    anonKey: process.env.SUPABASE_TEST_ANON_KEY || required('VITE_SUPABASE_PUBLISHABLE_KEY'),
    merchantEmail: required('COURIER_TEST_MERCHANT_EMAIL'),
    merchantPassword: required('COURIER_TEST_MERCHANT_PASSWORD'),
    buyerEmail: required('COURIER_TEST_BUYER_EMAIL'),
    buyerPassword: required('COURIER_TEST_BUYER_PASSWORD'),
    courierEmail: required('COURIER_TEST_COURIER_EMAIL'),
    courierPassword: required('COURIER_TEST_COURIER_PASSWORD'),
    orderId: required('COURIER_TEST_ORDER_ID'),
    courierId: required('COURIER_TEST_COURIER_ID'),
    otherCourierId: required('COURIER_TEST_OTHER_COURIER_ID'),
  };
}

const config = loadConfig();
const describeCourier = config ? describe : describe.skip;

function client(): SupabaseClient {
  return createClient(config!.url, config!.anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function signIn(email: string, password: string) {
  const supabase = client();
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  expect(error, `Unable to sign in ${email}`).toBeNull();
  expect(data.session).not.toBeNull();
  return supabase;
}

describeCourier('Courier P0 integration: concurrency and RLS', () => {
  let merchant: SupabaseClient;
  let buyer: SupabaseClient;
  let courier: SupabaseClient;

  beforeAll(async () => {
    merchant = await signIn(config!.merchantEmail, config!.merchantPassword);
    buyer = await signIn(config!.buyerEmail, config!.buyerPassword);
    courier = await signIn(config!.courierEmail, config!.courierPassword);
  });

  afterAll(async () => {
    await Promise.all([merchant?.auth.signOut(), buyer?.auth.signOut(), courier?.auth.signOut()]);
  });

  it('allows exactly one of two concurrent assignments', async () => {
    const results = await Promise.all([
      merchant.rpc('assign_specific_courier', { p_order_id: config!.orderId, p_courier_id: config!.courierId }),
      merchant.rpc('assign_specific_courier', { p_order_id: config!.orderId, p_courier_id: config!.otherCourierId }),
    ]);
    expect(results.filter((result) => !result.error)).toHaveLength(1);
    expect(results.filter((result) => result.error)).toHaveLength(1);

    const { data, error } = await merchant
      .from('orders').select('courier_id, status').eq('id', config!.orderId).single();
    expect(error).toBeNull();
    expect(data?.status).toBe('ASSIGNED');
    expect([config!.courierId, config!.otherCourierId]).toContain(data?.courier_id);
  });

  it('courier can read own profile but not another courier profile', async () => {
    const { data, error } = await courier
      .from('couriers').select('id, user_id').in('id', [config!.courierId, config!.otherCourierId]);
    expect(error).toBeNull();
    expect((data || []).map((row) => row.id)).toContain(config!.courierId);
    expect((data || []).map((row) => row.id)).not.toContain(config!.otherCourierId);
  });

  it('buyer cannot read courier earning rows', async () => {
    const { data, error } = await buyer.from('courier_earnings').select('id, courier_id, amount').limit(10);
    expect(data || []).toHaveLength(0);
    expect(error === null || error.code === '42501').toBe(true);
  });

  it('anonymous client cannot execute assignment RPC', async () => {
    const { error } = await client().rpc('assign_specific_courier', {
      p_order_id: config!.orderId, p_courier_id: config!.courierId,
    });
    expect(error).not.toBeNull();
  });
});

if (!config) {
  describe('Courier integration configuration', () => {
    it('is skipped unless RUN_COURIER_INTEGRATION=true and staging fixtures are configured', () => {
      expect(true).toBe(true);
    });
  });
}
