import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";
import { gdcPost, getGdcCredentials, type GdcResponse } from "../_shared/gdcSnap.ts";

const QUERY_PATH = "/v1.0/qr/qr-mpm-query";
type Payment = {
  order_id: string; partner_reference_no: string; external_id: string;
  reference_no: string | null; amount: number; status: string;
};
function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
async function queryGdc(payment: Payment): Promise<GdcResponse> {
  const credentials = getGdcCredentials();
  if (!payment.reference_no) throw new Error("GDC payment reference is missing");
  const data = await gdcPost(credentials, QUERY_PATH, {
    originalReferenceNo: payment.reference_no,
    originalPartnerReferenceNo: payment.partner_reference_no,
    originalExternalId: payment.external_id,
    serviceCode: "47",
    additionalInfo: {},
  }, payment.external_id);
  if (data.responseCode !== "2005100"
    || data.originalReferenceNo !== payment.reference_no
    || data.originalPartnerReferenceNo !== payment.partner_reference_no
    || data.originalExternalId !== payment.external_id
    || data.serviceCode !== "47") throw new Error("GDC response reference mismatch");
  return data;
}
function amount(value: unknown): number | null {
  if (!value || typeof value !== "object") return null;
  const raw = (value as { value?: unknown }).value;
  if (typeof raw !== "string" && typeof raw !== "number") return null;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? Math.round(parsed * 100) : null;
}
const LATE_PAYMENT_WINDOW_HOURS = 24;
const PAID_AFTER_EXPIRY_FLAG = "PAID_AFTER_EXPIRY_NEEDS_REVIEW";
const SELECT_COLUMNS = "order_id, partner_reference_no, external_id, reference_no, amount, status";

type Outcome = "settled" | "failed" | "flagged" | "pending";

async function reconcileOne(admin: ReturnType<typeof createClient>, payment: Payment): Promise<Outcome> {
  const queried = await queryGdc(payment);
  if (queried.latestTransactionStatus === "00") {
    const paidAmount = amount(queried.amount);
    if (queried.amount && (queried.amount as { currency?: unknown }).currency !== "IDR" || paidAmount !== Math.round(Number(payment.amount) * 100)) throw new Error("GDC amount mismatch");
    const { error: settleError } = await admin.rpc("settle_gdc_qris_mpm_payment", { p_order_id: payment.order_id, p_partner_reference_no: payment.partner_reference_no, p_reference_no: payment.reference_no, p_paid_amount: Number(payment.amount), p_paid_at: typeof queried.paidTime === "string" ? queried.paidTime : null });
    if (!settleError) return "settled";
    // 22023 = order no longer eligible (cancelled/expired/refunded) while the provider reports money received.
    if (payment.status === "EXPIRED" && settleError.code === "22023") {
      await admin.from("gdc_qris_mpm_payments").update({ error_code: PAID_AFTER_EXPIRY_FLAG, provider_response_code: "00", updated_at: new Date().toISOString() }).eq("order_id", payment.order_id).eq("status", "EXPIRED");
      console.error("GDC payment received after order became ineligible; manual refund review required", { orderId: payment.order_id });
      return "flagged";
    }
    throw settleError;
  }
  if (queried.latestTransactionStatus === "06" && payment.status === "PENDING") {
    await admin.from("gdc_qris_mpm_payments").update({ status: "FAILED", provider_response_code: "06", updated_at: new Date().toISOString() }).eq("order_id", payment.order_id).eq("status", "PENDING");
    return "failed";
  }
  return "pending";
}

async function run(admin: ReturnType<typeof createClient>) {
  // Oldest first so a backlog larger than the batch size cannot starve the same rows forever.
  const { data: pending, error } = await admin.from("gdc_qris_mpm_payments").select(SELECT_COLUMNS)
    .eq("status", "PENDING").not("reference_no", "is", null)
    .order("updated_at", { ascending: true }).limit(20);
  if (error) throw error;
  // Payments already expired locally can still be paid at the provider; keep checking them for a bounded window.
  const since = new Date(Date.now() - LATE_PAYMENT_WINDOW_HOURS * 3600_000).toISOString();
  const { data: lateCandidates, error: lateError } = await admin.from("gdc_qris_mpm_payments").select(SELECT_COLUMNS)
    .eq("status", "EXPIRED").eq("error_code", "PAYMENT_DEADLINE_EXPIRED").not("reference_no", "is", null)
    .gte("updated_at", since).order("updated_at", { ascending: true }).limit(10);
  if (lateError) throw lateError;
  const counts = { checked: 0, settled: 0, failed: 0, flagged: 0 };
  for (const payment of [...((pending || []) as Payment[]), ...((lateCandidates || []) as Payment[])]) {
    counts.checked += 1;
    try {
      const outcome = await reconcileOne(admin, payment);
      if (outcome === "settled") counts.settled += 1;
      else if (outcome === "failed") counts.failed += 1;
      else if (outcome === "flagged") counts.flagged += 1;
    } catch (error) {
      console.error("GDC reconciliation item failed", { orderId: payment.order_id, message: error instanceof Error ? error.message : (error as { code?: string })?.code || "unknown" });
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  const { data: expired, error: expireError } = await admin.rpc("reconcile_gdc_qris_mpm_payments");
  if (expireError) throw expireError;
  return { ...counts, expired: Number(expired || 0) };
}

serve(async (req) => {
  if (req.method !== "POST") return response({ error: "Method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const cronSecret = Deno.env.get("CRON_SECRET");
  const supplied = req.headers.get("x-cron-secret") || "";
  if (!url || !serviceRoleKey || !cronSecret || supplied !== cronSecret) return response({ error: "CRON_SECRET required" }, 401);
  try {
    const admin = createClient(url, serviceRoleKey, { auth: { persistSession: false } });
    return response({ status: "OK", ...(await run(admin)) });
  } catch (error) {
    console.error("GDC reconciliation failed", error instanceof Error ? error.message : "unknown");
    return response({ error: "Reconciliation failed" }, 503);
  }
});
