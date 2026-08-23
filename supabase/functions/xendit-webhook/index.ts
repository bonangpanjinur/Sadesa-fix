import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://desamart.id",
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
    if (
      !body.id ||
      !body.external_id ||
      !body.status ||
      !['PAID', 'EXPIRED', 'PENDING'].includes(body.status) ||
      !/^[0-9a-f-]{36}$/i.test(body.external_id)
    ) {
      return json({ error: "Invalid webhook" }, 400);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
    const { data: order, error: orderError } = await admin
      .from("orders")
      .select("id, total, payment_invoice_id, payment_status, status")
      .eq("id", body.external_id)
      .maybeSingle();
    if (orderError || !order) return json({ error: "Order not found" }, 404);

    // The provider invoice must be the invoice recorded for this order.
    if (!order.payment_invoice_id || order.payment_invoice_id !== body.id) {
      return json({ error: "Invoice mismatch" }, 409);
    }
    const orderTotal = Number(order.total);
    const paidAmount = body.paid_amount === undefined ? null : Number(body.paid_amount);
    if (!Number.isSafeInteger(orderTotal) || orderTotal <= 0) return json({ error: "Invalid order" }, 409);
    if (body.status === "PAID" && paidAmount !== orderTotal) {
      return json({ error: "Payment amount mismatch" }, 409);
    }

    const currentStatus = order.payment_status || "UNPAID";
    // A paid order is terminal. A later callback must never overwrite its
    // payment metadata or downgrade it to a non-paid state.
    if (currentStatus === "PAID") return json({ success: true, ignored: true });
    if (currentStatus === "EXPIRED" && body.status === "PENDING") return json({ success: true, ignored: true });

    // Xendit provides a stable delivery/event identifier when available.
    // The deterministic fallback preserves idempotency for older callbacks.
    const providerEventId = req.headers.get('webhook-id')?.trim();
    const eventKey = providerEventId
      ? `xendit:webhook:${providerEventId}`
      : `xendit:invoice:${body.id}:${body.status}:${body.paid_at || ""}`;
    const { error: eventError } = await admin
      .from("payment_webhook_events")
      .insert({ provider: "xendit", event_key: eventKey, invoice_id: body.id, order_id: order.id, status: body.status });
    if (eventError?.code === "23505") {
      logWebhook('duplicate_ignored', { status: body.status });
      return json({ success: true, duplicate: true });
    }
    if (eventError) {
      console.error("Webhook idempotency insert failed", { code: eventError.code });
      return json({ error: "Webhook unavailable" }, 503);
    }

    const updateData: Record<string, unknown> = {
      payment_status: body.status,
      payment_paid_at: body.status === "PAID" ? body.paid_at || new Date().toISOString() : null,
      payment_method: body.payment_method || null,
      payment_channel: body.payment_channel || null,
    };
    if (body.status === "PAID") updateData.status = "CONFIRMED";
    if (body.status === "EXPIRED" && currentStatus !== "PAID") updateData.status = "CANCELLED";

    const { error: updateError } = await admin.from("orders").update(updateData).eq("id", order.id).eq("payment_invoice_id", body.id);
    if (updateError) {
      // Do not leave an idempotency row behind when the business update fails;
      // the provider must be able to retry the callback safely.
      await admin.from("payment_webhook_events").delete().eq("provider", "xendit").eq("event_key", eventKey);
      console.error("Webhook order update failed", { orderId: order.id, code: updateError.code });
      return json({ error: "Webhook unavailable" }, 503);
    }

    logWebhook('processed', { status: body.status, paymentUpdated: true });
    return json({ success: true });
  } catch (error) {
    logWebhook('processing_failed', {}, error);
    console.error("Webhook processing failed", error instanceof Error ? error.message : "unknown");
    return json({ error: "Webhook unavailable" }, 500);
  }
});
