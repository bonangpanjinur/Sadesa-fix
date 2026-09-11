import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin");
  const allowedOrigin = origin === "https://sadesa.id" || origin === "https://www.sadesa.id"
    ? origin
    : "https://www.sadesa.id";
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, idempotency-key",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Vary": "Origin",
  };
}

interface CreateInvoiceRequest {
  order_id: string;
}

interface OrderRecord {
  id: string;
  buyer_id: string;
  total: number;
  status: string;
  payment_status: string | null;
  payment_invoice_id: string | null;
  payment_invoice_url: string | null;
}

interface XenditSettings {
  enabled: boolean;
  secret_key?: string;
}

interface InvoiceRequestReservation {
  can_process: boolean;
  status: 'processing' | 'completed' | 'failed';
  request_key: string;
  invoice_id: string | null;
  invoice_url: string | null;
  last_error: string | null;
}

function json(data: unknown, status = 200, req?: Request) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...getCorsHeaders(req ?? new Request("https://www.sadesa.id")), "Content-Type": "application/json" },
  });
}

function getBearerToken(req: Request): string | null {
  const value = req.headers.get("authorization") || "";
  return value.startsWith("Bearer ") ? value.slice(7) : null;
}

function getUserClient(supabaseUrl: string, anonKey: string, token: string): SupabaseClient {
  return createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
}

async function getXenditSettings(supabaseUrl: string, serviceRoleKey: string): Promise<XenditSettings> {
  const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const { data, error } = await supabaseAdmin
    .from("app_settings")
    .select("value")
    .eq("key", "payment_xendit")
    .maybeSingle();

  if (error || !data) throw new Error("Payment provider is unavailable");
  const settings = data.value as XenditSettings;
  if (!settings.enabled || !settings.secret_key) throw new Error("Payment provider is unavailable");
  return settings;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: getCorsHeaders(req) });

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const token = getBearerToken(req);
  if (!supabaseUrl || !serviceRoleKey || !anonKey || !token) return json({ error: "Unauthorized" }, 401, req);

  try {
    const userClient = getUserClient(supabaseUrl, anonKey, token);
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) return json({ error: "Unauthorized" }, 401, req);
    const user = userData.user;
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
    const settings = await getXenditSettings(supabaseUrl, serviceRoleKey);
    const authHeader = `Basic ${btoa(`${settings.secret_key}:`)}`;
    const url = new URL(req.url);
    const action = url.pathname.split("/").pop();

    if (action === "create-invoice" && req.method === "POST") {
      const body = (await req.json()) as Partial<CreateInvoiceRequest>;
      if (!body.order_id || !/^[0-9a-f-]{36}$/i.test(body.order_id)) {
        return json({ error: "Invalid order" }, 400);
      }

      const { data: order, error: orderError } = await supabaseAdmin
        .from("orders")
        .select("id, buyer_id, total, status, payment_status, payment_invoice_id, payment_invoice_url")
        .eq("id", body.order_id)
        .eq("buyer_id", user.id)
        .maybeSingle();
      if (orderError || !order) return json({ error: "Order not found" }, 404);

      const current = order as OrderRecord;
      if ((["CANCELLED", "DONE"].includes(current.status) && current.payment_status !== 'EXPIRED') || current.payment_status === "PAID") {
        return json({ error: "Order cannot be paid" }, 409);
      }
      const orderTotal = Number(current.total);
      if (!Number.isSafeInteger(orderTotal) || orderTotal <= 0) return json({ error: "Invalid order total" }, 409);

      // Reuse an active invoice for retries instead of creating duplicates.
      // An EXPIRED invoice must be reset so the buyer can receive a fresh URL.
      if (current.payment_status === 'EXPIRED') {
        await supabaseAdmin
          .from('payment_invoice_requests')
          .update({ status: 'failed', invoice_id: null, invoice_url: null, last_error: 'invoice:expired', updated_at: new Date().toISOString() })
          .eq('provider', 'xendit')
          .eq('order_id', current.id);
        await supabaseAdmin
          .from('orders')
          .update({ payment_invoice_id: null, payment_invoice_url: null, payment_status: 'UNPAID', status: 'PENDING_PAYMENT' })
          .eq('id', current.id)
          .eq('buyer_id', user.id)
          .eq('payment_status', 'EXPIRED');
        current.payment_invoice_id = null;
        current.payment_invoice_url = null;
        current.payment_status = 'UNPAID';
        current.status = 'PENDING_PAYMENT';
      }
      if (current.payment_invoice_id && current.payment_invoice_url) {
        return json({
          success: true,
          invoice_id: current.payment_invoice_id,
          invoice_url: current.payment_invoice_url,
        });
      }

      // Keep retries deterministic even when the browser does not provide an
      // idempotency key. The order-level key also lets us recover a provider
      // invoice after a crash between provider creation and order persistence.
      const requestKey = req.headers.get('idempotency-key')?.trim() || `sadesa-order-${current.id}`;
      if (requestKey.length < 16 || requestKey.length > 128) {
        return json({ error: 'Invalid idempotency key' }, 400);
      }

      const { data: reservationData, error: reservationError } = await supabaseAdmin.rpc(
        'reserve_payment_invoice_request',
        { p_provider: 'xendit', p_order_id: current.id, p_request_key: requestKey },
      );
      if (reservationError || !reservationData) {
        console.error('Failed to reserve payment invoice request', { orderId: current.id });
        return json({ error: 'Unable to initialize payment' }, 503);
      }
      const reservation = reservationData as unknown as InvoiceRequestReservation;
      if (reservation.invoice_id && reservation.invoice_url) {
        const { data: repairedOrder, error: repairError } = await supabaseAdmin
          .from('orders')
          .update({ payment_invoice_id: reservation.invoice_id, payment_invoice_url: reservation.invoice_url, payment_status: 'PENDING' })
          .eq('id', current.id)
          .eq('buyer_id', user.id)
          .neq('payment_status', 'PAID')
          .is('payment_invoice_id', null)
          .select('id')
          .maybeSingle();
        if (!repairError && repairedOrder) {
          await supabaseAdmin.from('payment_invoice_requests').update({
            status: 'completed', last_error: null, updated_at: new Date().toISOString(),
          }).eq('provider', 'xendit').eq('order_id', current.id).eq('request_key', requestKey);
          return json({ success: true, invoice_id: reservation.invoice_id, invoice_url: reservation.invoice_url });
        }
      }
      if (!reservation.can_process) {
        if (reservation.status === 'completed' && reservation.invoice_id && reservation.invoice_url) {
          return json({ success: true, invoice_id: reservation.invoice_id, invoice_url: reservation.invoice_url });
        }
        return json({ error: 'Payment initialization already in progress' }, 409);
      }

      const origin = req.headers.get("origin");
      const allowedOrigin = origin === "https://sadesa.id" ? origin : "https://sadesa.id";
      const response = await fetch("https://api.xendit.co/v2/invoices", {
        method: "POST",
        headers: {
          Authorization: authHeader,
          "Content-Type": "application/json",
          // Xendit may honor this provider-side key; our DB reservation remains
          // the authoritative duplicate-prevention boundary.
          "Idempotency-Key": requestKey,
        },
        body: JSON.stringify({
          external_id: current.id,
          amount: orderTotal,
          payer_email: user.email,
          description: `Pembayaran pesanan ${current.id}`,
          invoice_duration: 86400,
          currency: "IDR",
          success_redirect_url: `${allowedOrigin}/orders?payment=success`,
          failure_redirect_url: `${allowedOrigin}/orders?payment=failed`,
        }),
      });
      if (!response.ok) {
        await supabaseAdmin
          .from('payment_invoice_requests')
          .update({ status: 'failed', last_error: `provider:${response.status}`, updated_at: new Date().toISOString() })
          .eq('provider', 'xendit')
          .eq('order_id', current.id)
          .eq('request_key', requestKey);
        console.error("Xendit invoice request failed", { status: response.status, orderId: current.id });
        return json({ error: "Payment provider error" }, 502);
      }

      const invoice = await response.json() as { id?: string; invoice_url?: string; expiry_date?: string };
      if (!invoice.id || !invoice.invoice_url) {
        await supabaseAdmin
          .from('payment_invoice_requests')
          .update({ status: 'failed', last_error: 'provider:invalid_invoice_response', updated_at: new Date().toISOString() })
          .eq('provider', 'xendit')
          .eq('order_id', current.id)
          .eq('request_key', requestKey);
        return json({ error: "Invalid payment provider response" }, 502);
      }

      // Persist provider identifiers before updating the order so a retry can
      // repair the order if the process crashes between these two writes.
      await supabaseAdmin
        .from('payment_invoice_requests')
        .update({ invoice_id: invoice.id, invoice_url: invoice.invoice_url, updated_at: new Date().toISOString() })
        .eq('provider', 'xendit')
        .eq('order_id', current.id)
        .eq('request_key', requestKey);

      const { data: persistedOrder, error: updateError } = await supabaseAdmin
        .from("orders")
        .update({ payment_invoice_id: invoice.id, payment_invoice_url: invoice.invoice_url, payment_status: "PENDING" })
        .eq("id", current.id)
        .eq("buyer_id", user.id)
        .neq("payment_status", "PAID")
        .is("payment_invoice_id", null)
        .select("id, payment_invoice_id, payment_invoice_url")
        .maybeSingle();
      if (updateError || !persistedOrder) {
        await supabaseAdmin
          .from('payment_invoice_requests')
          .update({ status: 'failed', last_error: 'order:persist_failed', updated_at: new Date().toISOString() })
          .eq('provider', 'xendit')
          .eq('order_id', current.id)
          .eq('request_key', requestKey);
        console.error("Failed to persist payment invoice", { orderId: current.id, error: updateError?.message });
        return json({ error: "Unable to initialize payment" }, 500);
      }

      await supabaseAdmin
        .from('payment_invoice_requests')
        .update({ status: 'completed', invoice_id: invoice.id, invoice_url: invoice.invoice_url, last_error: null, updated_at: new Date().toISOString() })
        .eq('provider', 'xendit')
        .eq('order_id', current.id)
        .eq('request_key', requestKey);

      return json({ success: true, invoice_id: invoice.id, invoice_url: invoice.invoice_url, expiry_date: invoice.expiry_date });
    }

    if (action === "check-status" && req.method === "GET") {
      const invoiceId = url.searchParams.get("invoice_id");
      if (!invoiceId || invoiceId.length > 200) return json({ error: "Invalid invoice" }, 400);

      const { data: order, error: orderError } = await supabaseAdmin
        .from("orders")
        .select("id, payment_invoice_id")
        .eq("payment_invoice_id", invoiceId)
        .eq("buyer_id", user.id)
        .maybeSingle();
      if (orderError || !order) return json({ error: "Invoice not found" }, 404);

      const response = await fetch(`https://api.xendit.co/v2/invoices/${encodeURIComponent(invoiceId)}`, {
        headers: { Authorization: authHeader },
      });
      if (!response.ok) return json({ error: "Payment provider error" }, 502);
      const invoice = await response.json();
      return json({ success: true, status: invoice.status, paid_at: invoice.paid_at, payment_method: invoice.payment_method });
    }

    return json({ error: "Invalid action" }, 400);
  } catch (error) {
    console.error("Payment function error", error instanceof Error ? error.message : "unknown");
    return json({ error: "Payment service unavailable" }, 500);
  }
});
