import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://sadesa.id",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-callback-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface XenditInvoiceCallback {
  id: string;
  external_id: string;
  status: "PAID" | "EXPIRED" | "PENDING";
  paid_at?: string;
  payment_method?: string;
  payment_channel?: string;
  paid_amount?: number;
}

interface XenditSettings {
  callback_token?: string;
}

function logWebhook(event: string, context: Record<string, string | number | boolean | null> = {}, error?: unknown) {
  console.log(JSON.stringify({
    source: 'xendit-webhook',
    event,
    at: new Date().toISOString(),
    context,
    error: error instanceof Error ? { name: error.name, message: error.message.slice(0, 240) } : undefined,
  }));
}

function secureEqual(left: string, right: string): boolean {
  const leftBytes = new TextEncoder().encode(left);
  const rightBytes = new TextEncoder().encode(right);
  if (leftBytes.length !== rightBytes.length) return false;
  let difference = 0;
  for (let index = 0; index < leftBytes.length; index += 1) difference |= leftBytes[index] ^ rightBytes[index];
  return difference === 0;
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function getSettings(supabaseUrl: string, serviceRoleKey: string): Promise<XenditSettings | null> {
  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
  const { data, error } = await admin.from("app_settings").select("value").eq("key", "payment_xendit").maybeSingle();
  if (error || !data) return null;
  return data.value as XenditSettings;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceRoleKey) {
    logWebhook('configuration_missing', { hasSupabaseUrl: Boolean(supabaseUrl), hasServiceRoleKey: Boolean(serviceRoleKey) });
    return json({ error: "Webhook unavailable" }, 503);
  }

  try {
    const settings = await getSettings(supabaseUrl, serviceRoleKey);
    const callbackToken = req.headers.get("x-callback-token");
    if (!settings?.callback_token || !callbackToken || !secureEqual(callbackToken, settings.callback_token)) {
      logWebhook('authentication_failed', { hasCallbackToken: Boolean(callbackToken) });
      return json({ error: "Unauthorized" }, 401);
    }

    const body = (await req.json()) as Partial<XenditInvoiceCallback>;
    logWebhook('received', { hasInvoiceId: Boolean(body.id), hasOrderId: Boolean(body.external_id), status: body.status ?? null });
    const walletTopupMatch = body.external_id?.match(/^wallet-topup-([0-9a-f-]{36})$/i);
    const isWalletTopup = Boolean(walletTopupMatch);
    if (
      !body.id || !body.external_id || !body.status ||
      !['PAID', 'EXPIRED', 'PENDING'].includes(body.status) ||
      (!isWalletTopup && !/^[0-9a-f-]{36}$/i.test(body.external_id))
    ) {
      return json({ error: "Invalid webhook" }, 400);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

    // Xendit provides a stable delivery/event identifier when available.
    // The deterministic fallback preserves idempotency for older callbacks.
    const providerEventId = req.headers.get('webhook-id')?.trim();
    const eventKey = providerEventId
      ? `xendit:webhook:${providerEventId}`
      : `xendit:invoice:${body.id}:${body.status}:${body.paid_at || ""}`;
    const paidAmount = body.paid_amount === undefined ? null : Number(body.paid_amount);
    const { data: result, error: processError } = isWalletTopup
      ? await admin.rpc('process_commission_wallet_topup_payment', {
        p_request_id: walletTopupMatch![1],
        p_event_key: eventKey,
        p_invoice_id: body.id,
        p_status: body.status,
        p_paid_amount: paidAmount,
        p_payment_method: body.payment_method || null,
        p_payment_channel: body.payment_channel || null,
      })
      : await admin.rpc('process_payment_webhook_event', {
        p_provider: 'xendit',
        p_event_key: eventKey,
        p_invoice_id: body.id,
        p_order_id: body.external_id,
        p_status: body.status,
        p_paid_at: body.paid_at || null,
        p_payment_method: body.payment_method || null,
        p_payment_channel: body.payment_channel || null,
        p_paid_amount: paidAmount,
      });

    if (processError) {
      const code = processError.code;
      if (code === 'P0002') return json({ error: isWalletTopup ? 'Top-up request not found' : 'Order not found' }, 404);
      if (code === '23P01') return json({ error: 'Invoice mismatch' }, 409);
      if (code === '22003') return json({ error: 'Payment amount mismatch' }, 409);
      if (code === '22023') return json({ error: 'Invalid payment event' }, 409);
      console.error('Atomic webhook processing failed', { code });
      return json({ error: 'Webhook unavailable' }, 503);
    }

    const outcome = result as { duplicate?: boolean; ignored?: boolean; processed?: boolean } | null;
    if (outcome?.duplicate) {
      logWebhook('duplicate_ignored', { status: body.status });
      return json({ success: true, duplicate: true });
    }
    if (outcome?.ignored) return json({ success: true, ignored: true });

    logWebhook('processed', { status: body.status, paymentUpdated: Boolean(outcome?.processed) });
    return json({ success: true });
  } catch (error) {
    logWebhook('processing_failed', {}, error);
    console.error("Webhook processing failed", error instanceof Error ? error.message : "unknown");
    return json({ error: "Webhook unavailable" }, 500);
  }
});
