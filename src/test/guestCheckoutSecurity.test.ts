import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const read = (path: string) => readFileSync(resolve(process.cwd(), path), 'utf8');
const phase1 = () => read('supabase/bootstrap/65_20261002170000_guest_checkout_phase1.sql');
const payment = () => read('supabase/bootstrap/66_20261002190000_guest_payment_ui.sql');
const hardening = () => read('supabase/bootstrap/68_20261002210000_guest_checkout_hardening.sql');

describe('guest checkout security contract', () => {
  it('generates a cryptographic token, stores only its digest, and expires it', () => {
    const sql = phase1();
    expect(sql).toContain('gen_random_bytes(32)');
    expect(sql).toContain("digest(v_guest_access_token, 'sha256')");
    expect(sql).toContain("now() + interval '30 days'");
    expect(sql).toContain('guest_access_token_hash');
    expect(sql).not.toContain('guest_access_token text NOT NULL');
  });

  it('scopes status and proof RPCs to order id plus token and rejects invalid access generically', () => {
    const sql = phase1();
    expect(sql).toContain('get_guest_order_status(p_order_id uuid, p_guest_access_token text)');
    expect(sql).toContain('guest_access_token_hash = encode(digest(p_guest_access_token, \'sha256\'), \'hex\')');
    expect(sql).toContain("RAISE EXCEPTION 'Order status unavailable'");
    expect(sql).toContain('guest_submit_payment_proof(p_order_id uuid, p_guest_access_token text');
    expect(sql).toContain("RAISE EXCEPTION 'Order payment unavailable'");
    expect(sql).toContain('GRANT EXECUTE ON FUNCTION public.get_guest_order_status(uuid, text) TO anon');
    expect(sql).toContain('GRANT EXECUTE ON FUNCTION public.guest_submit_payment_proof(uuid, text, text) TO anon');
  });

  it('does not grant anon direct table access and token-scopes proof objects', () => {
    const sql = `${phase1()}\n${payment()}`;
    expect(sql).not.toMatch(/GRANT\s+(SELECT|INSERT|UPDATE|ALL)[^;]*ON\s+(public\.)?(orders|order_items)\s+TO\s+anon/i);
    expect(sql).toContain("length(split_part(name, '/', 3)) = 64");
    expect(sql).toContain('o.guest_access_token_hash = split_part(name, \'/\', 3)');
    expect(sql).toContain('guest_token_expires_at > now()');
  });

  it('keeps guest checkout behind the frontend rollout flag', () => {
    const cart = read('src/pages/CartPage.tsx');
    const checkout = read('src/pages/CheckoutPage.tsx');
    expect(cart).toContain('useGuestCheckoutEnabled');
    expect(cart).toContain("navigate('/auth')");
    expect(checkout).toContain('guestCheckoutFlagLoading');
    expect(checkout).toContain("navigate('/auth', { replace: true })");
  });

  it('covers server-side checkout failure and retry contracts', () => {
    const sql = phase1();
    expect(sql).toContain("Merchant is unavailable");
    expect(sql).toContain("Insufficient stock for product");
    expect(sql).toContain('pg_advisory_xact_lock');
    expect(sql).toContain('IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;');
    expect(sql).toContain('Checkout hanya tersedia untuk satu toko dalam satu transaksi');
  });

  it('keeps all guest checkout surfaces inside the mobile shell', () => {
    for (const path of [
      'src/pages/CartPage.tsx',
      'src/pages/CheckoutPage.tsx',
      'src/pages/GuestOrderStatusPage.tsx',
      'src/pages/PaymentConfirmationPage.tsx',
    ]) {
      expect(read(path)).toContain('mobile-shell');
    }
  });

  it('rejects online guest payment and arbitrary guest proof URLs server-side', () => {
    const sql = hardening();
    expect(sql).toContain("NEW.buyer_id IS NULL AND NEW.guest_access_token_hash IS NOT NULL");
    expect(sql).toContain("NEW.payment_method <> 'TRANSFER'");
    expect(sql).toContain("/payment-proofs/orders/' || NEW.id::text || '/' || NEW.guest_access_token_hash || '/");
    expect(sql).toContain('BEFORE INSERT OR UPDATE OF payment_method, payment_proof_url');
  });

  it('does not expose online payment as a guest checkout option', () => {
    const checkout = read('src/pages/CheckoutPage.tsx');
    expect(checkout).toContain("if (!user) return 'TRANSFER'");
    expect(checkout).toContain('{user && xenditAvailable && (');
  });
});
