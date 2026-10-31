import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const encoder = new TextEncoder();
const jsonHeaders = { "Content-Type": "application/json", "Cache-Control": "no-store" };

type Attempt = {
  id: string; order_id: string; merchant_id: string; profile_id: string; amount: number; currency: string;
  partner_reference_no: string; provider_reference_no: string | null; service_code: string | null;
  status: string; qr_content: string | null; qr_url: string | null; qr_image: string | null;
  expires_at: string | null;
};

type Profile = {
  id: string; merchant_id: string; provider_merchant_id: string; provider_account_number: string;
  nmid: string | null; store_id: string | null; terminal_id: string | null; service_code: string | null;
};

function cors(req: Request): Record<string, string> {
  const origin = req.headers.get("origin");
  const allowed = origin === "https://sadesa.id" || origin === "https://www.sadesa.id" ? origin : "https://www.sadesa.id";
  return { "Access-Control-Allow-Origin": allowed, "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, idempotency-key, x-callback-token", "Access-Control-Allow-Methods": "GET, POST, OPTIONS", Vary: "Origin" };
}
function response(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors(req), ...jsonHeaders } });
}
function bearer(req: Request) { const value = req.headers.get("authorization") || ""; return value.startsWith("Bearer ") ? value.slice(7) : null; }
function adminClient(url: string, key: string) { return createClient(url, key, { auth: { persistSession: false } }); }
function userClient(url: string, key: string, token: string): SupabaseClient { return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false }, global: { headers: { Authorization: `Bearer ${token}` } } }); }
function text(value: unknown) { return typeof value === "string" && value.trim() ? value.trim() : null; }
function first(obj: Record<string, unknown>, keys: string[]) { for (const key of keys) { const value = obj[key]; if (value !== undefined && value !== null && value !== "") return value; } return null; }

async function hmac(secret: string, value: string) {
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const bytes = new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(value)));
  return Array.from(bytes).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
async function gdcRequest(path: string, body: Record<string, unknown>, requestId: string) {
  const base = Deno.env.get("GDC_API_BASE_URL")?.replace(/\/$/, "");
  if (!base) throw new Error("GDC_API_BASE_URL is not configured");
  const timestamp = new Date().toISOString();
  const rawBody = JSON.stringify(body);
  const signatureMode = (Deno.env.get("GDC_SIGNATURE_MODE") || "hmac_sha256").toLowerCase();
  const signatureSecret = Deno.env.get("GDC_SIGNATURE_SECRET") || "";
  const signature = signatureMode === "none" ? "" : signatureSecret ? await hmac(signatureSecret, `${timestamp}.${rawBody}`) : null;
  if (signature === null) throw new Error("GDC_SIGNATURE_SECRET is not configured");
  const headers: Record<string, string> = { "Content-Type": "application/json", "Accept": "application/json", "X-Request-Id": requestId, "X-Timestamp": timestamp };
  const partnerId = Deno.env.get("GDC_PARTNER_ID");
  const accessToken = Deno.env.get("GDC_ACCESS_TOKEN");
  if (partnerId) headers["X-Partner-Id"] = partnerId;
  if (accessToken) headers.Authorization = `Bearer ${accessToken}`;
  if (signature) headers["X-Signature"] = signature;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), Number(Deno.env.get("GDC_TIMEOUT_MS") || 15000));
  try {
    const result = await fetch(`${base}${path.startsWith("/") ? path : `/${path}`}`, { method: "POST", headers, body: rawBody, signal: controller.signal });
    const raw = await result.text();
    let parsed: unknown = null; try { parsed = raw ? JSON.parse(raw) : null; } catch { parsed = { raw: raw.slice(0, 2000) }; }
    return { ok: result.ok, status: result.status, data: parsed };
  } finally { clearTimeout(timer); }
}
function normalisePayload(data: unknown): Record<string, unknown> {
  if (!data || typeof data !== "object") return {};
  const root = data as Record<string, unknown>;
  const nested = root.data && typeof root.data === "object" ? root.data as Record<string, unknown> : root;
  return { ...root, ...nested };
}
function normaliseStatus(value: unknown): string {
  const status = String(value || "").toUpperCase();
  if (["SUCCESS", "SUCCEEDED", "PAID", "SETTLED", "COMPLETED"].includes(status)) return "SUCCEEDED";
  if (["EXPIRED", "TIMEOUT"].includes(status)) return "EXPIRED";
  if (["FAILED", "FAIL", "REJECTED", "CANCELLED", "CANCELED"].includes(status)) return "FAILED";
  if (["UNKNOWN"].includes(status)) return "UNKNOWN";
  return "PENDING";
}
async function currentUser(req: Request, url: string, anonKey: string) {
  const token = bearer(req); if (!token) return null;
  const client = userClient(url, anonKey, token);
  const { data } = await client.auth.getUser();
  return data.user || null;
}
async function ownedOrder(admin: SupabaseClient, orderId: string, userId: string) {
  const { data, error } = await admin.from("orders").select("id, buyer_id, merchant_id, total, payment_status, status").eq("id", orderId).eq("buyer_id", userId).maybeSingle();
  if (error || !data) return null;
  return data;
}
async function getAttempt(admin: SupabaseClient, id: string): Promise<Attempt | null> {
  const { data } = await admin.from("gdc_qris_payment_attempts").select("*").eq("id", id).maybeSingle();
  return data as Attempt | null;
}
async function recordEvent(admin: SupabaseClient, attemptId: string | null, eventType: string, fields: Record<string, unknown> = {}) {
  await admin.rpc("record_gdc_qris_observability", {
    p_attempt_id: attemptId,
    p_event_type: eventType,
    p_internal_status: typeof fields.internalStatus === "string" ? fields.internalStatus : null,
    p_provider_http_status: typeof fields.providerHttpStatus === "number" ? fields.providerHttpStatus : null,
    p_duration_ms: typeof fields.durationMs === "number" ? Math.max(0, Math.round(fields.durationMs)) : null,
    p_error_code: typeof fields.errorCode === "string" ? fields.errorCode : null,
  });
}
async function updateStatus(admin: SupabaseClient, attempt: Attempt, data: unknown) {
  const payload = normalisePayload(data);
  const status = normaliseStatus(first(payload, ["status", "transactionStatus", "transaction_status", "paymentStatus"]));
  const paidAmountValue = first(payload, ["paidAmount", "paid_amount", "amount"]);
  const paidAmount = paidAmountValue === null ? null : Number(paidAmountValue);
  const { data: result, error } = await admin.rpc("process_gdc_qris_status", {
    p_attempt_id: attempt.id,
    p_status: status,
    p_provider_reference_no: text(first(payload, ["referenceNo", "reference_no", "providerReferenceNo", "transactionId"])),
    p_provider_status: text(first(payload, ["status", "transactionStatus", "transaction_status"])),
    p_provider_code: text(first(payload, ["responseCode", "response_code", "code"])),
    p_provider_message: text(first(payload, ["responseMessage", "response_message", "message"])),
    p_paid_at: text(first(payload, ["paidAt", "paid_at", "transactionDate"])),
    p_paid_amount: Number.isFinite(paidAmount) ? paidAmount : null,
    p_event_key: null,
  });
  if (error) throw error;
  return { status, result };
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: { ...cors(req), ...jsonHeaders } });
  const url = Deno.env.get("SUPABASE_URL") || "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
  if (!url || !serviceKey || !anonKey) return response(req, { error: "GDC function is not configured" }, 503);
  const admin = adminClient(url, serviceKey);
  const action = new URL(req.url).pathname.split("/").filter(Boolean).pop() || "";

  try {
    if (action === "callback") {
      if (req.method !== "POST") return response(req, { error: "Method not allowed" }, 405);
      const expected = Deno.env.get("GDC_CALLBACK_TOKEN");
      const provided = req.headers.get("x-callback-token");
      if (!expected || !provided || provided !== expected) return response(req, { error: "Unauthorized" }, 401);
      const body = await req.json() as Record<string, unknown>;
      const payload = normalisePayload(body);
      const partnerReference = text(first(payload, ["partnerReferenceNo", "partner_reference_no", "externalId"]));
      if (!partnerReference) return response(req, { error: "Missing partner reference" }, 400);
      const { data: attempt } = await admin.from("gdc_qris_payment_attempts").select("*").eq("partner_reference_no", partnerReference).maybeSingle();
      if (!attempt) { await recordEvent(admin, null, "CALLBACK_REJECTED", { errorCode: "ATTEMPT_NOT_FOUND" }); return response(req, { error: "Attempt not found" }, 404); }
      const result = await updateStatus(admin, attempt as Attempt, payload);
      await recordEvent(admin, attempt.id, "CALLBACK_PROCESSED", { internalStatus: result.status });
      return response(req, { success: true, ...result });
    }

    const user = await currentUser(req, url, anonKey);
    if (!user) return response(req, { error: "Unauthorized" }, 401);
    const body = req.method === "POST" ? await req.json().catch(() => ({})) as Record<string, unknown> : {};
    const orderId = text(body.order_id);
    const attemptId = text(body.attempt_id);
    if (action === "generate") {
      if (!orderId) return response(req, { error: "order_id is required" }, 400);
      const order = await ownedOrder(admin, orderId, user.id);
      if (!order) return response(req, { error: "Order not found" }, 404);
      const requestKey = req.headers.get("idempotency-key")?.trim() || `gdc-qris:${orderId}`;
      const { data: reservation, error: reservationError } = await admin.rpc("reserve_gdc_qris_attempt", { p_order_id: orderId, p_request_key: requestKey });
      if (reservationError || !reservation) return response(req, { error: reservationError?.message || "Unable to reserve payment" }, 409);
      const reserved = reservation as { attempt_id: string; partner_reference_no: string; status: string; existing: boolean };
      let attempt = await getAttempt(admin, reserved.attempt_id);
      if (!attempt) return response(req, { error: "Payment attempt not found" }, 500);
      if (attempt.status === "PENDING" && (attempt.qr_content || attempt.qr_url || attempt.qr_image)) return response(req, { success: true, attempt });
      const { data: profileData, error: profileError } = await admin.from("gdc_payment_profiles").select("*").eq("id", attempt.profile_id).single();
      if (profileError || !profileData) return response(req, { error: "GDC profile not found" }, 500);
      const profile = profileData as Profile;
      const requestPayload = {
        partnerReferenceNo: attempt.partner_reference_no,
        amount: { value: String(attempt.amount), currency: attempt.currency },
        merchantId: profile.provider_merchant_id,
        additionalInfo: { accountNumber: profile.provider_account_number, ...(profile.store_id ? { storeId: profile.store_id } : {}), ...(profile.terminal_id ? { terminalId: profile.terminal_id } : {}) },
        ...(attempt.service_code || Deno.env.get("GDC_SERVICE_CODE") ? { serviceCode: attempt.service_code || Deno.env.get("GDC_SERVICE_CODE") } : {}),
      };
      try {
        const startedAt = Date.now();
        await recordEvent(admin, attempt.id, "GENERATE_STARTED");
        const result = await gdcRequest(Deno.env.get("GDC_GENERATE_PATH") || "/v1.0/qr/qr-mpm-generate", requestPayload, attempt.partner_reference_no);
        const payload = normalisePayload(result.data);
        const ok = result.ok && Boolean(first(payload, ["qrContent", "qr_content", "qrUrl", "qr_url", "qrImage", "qr_image"]));
        const { data: completed, error: completionError } = await admin.rpc("complete_gdc_qris_generate", {
          p_attempt_id: attempt.id, p_success: ok,
          p_provider_reference_no: text(first(payload, ["referenceNo", "reference_no", "providerReferenceNo"])),
          p_qr_content: text(first(payload, ["qrContent", "qr_content"])), p_qr_url: text(first(payload, ["qrUrl", "qr_url"])), p_qr_image: text(first(payload, ["qrImage", "qr_image"])),
          p_expires_at: text(first(payload, ["expiresAt", "expires_at", "expiryDate"])), p_provider_status: text(first(payload, ["status", "responseCode"])),
          p_provider_code: text(first(payload, ["responseCode", "response_code", "code"])), p_provider_message: text(first(payload, ["responseMessage", "response_message", "message"])),
          p_request_payload: requestPayload, p_response_payload: payload, p_error: ok ? null : `GDC HTTP ${result.status}`,
        });
        if (completionError) throw completionError;
        await recordEvent(admin, attempt.id, ok ? "GENERATE_SUCCEEDED" : "GENERATE_FAILED", { internalStatus: ok ? "PENDING" : "UNKNOWN", providerHttpStatus: result.status, durationMs: Date.now() - startedAt, errorCode: ok ? undefined : `HTTP_${result.status}` });
        return response(req, { success: ok, attempt: completed, provider_http_status: result.status }, ok ? 200 : 502);
      } catch (error) {
        await admin.rpc("complete_gdc_qris_generate", { p_attempt_id: attempt.id, p_success: false, p_request_payload: requestPayload, p_error: error instanceof Error ? error.message.slice(0, 500) : "GDC request failed" });
        await recordEvent(admin, attempt.id, "GENERATE_FAILED", { internalStatus: "UNKNOWN", errorCode: "PROVIDER_UNAVAILABLE" });
        return response(req, { error: "GDC payment provider unavailable", attempt_id: attempt.id }, 503);
      }
    }

    if (action === "query") {
      if (!attemptId) return response(req, { error: "attempt_id is required" }, 400);
      const { data: attemptData } = await admin.from("gdc_qris_payment_attempts").select("*").eq("id", attemptId).maybeSingle();
      if (!attemptData) return response(req, { error: "Attempt not found" }, 404);
      const attempt = attemptData as Attempt;
      const order = await ownedOrder(admin, attempt.order_id, user.id);
      if (!order) return response(req, { error: "Attempt not found" }, 404);
      if (attempt.status === "SUCCEEDED" || attempt.status === "EXPIRED" || attempt.status === "FAILED") return response(req, { success: true, attempt });
      const queryPayload = { partnerReferenceNo: attempt.partner_reference_no, referenceNo: attempt.provider_reference_no, serviceCode: attempt.service_code || Deno.env.get("GDC_SERVICE_CODE") || undefined };
      const startedAt = Date.now();
      const result = await gdcRequest(Deno.env.get("GDC_QUERY_PATH") || "/v1.0/qr/qr-mpm-query", queryPayload, attempt.partner_reference_no);
      const statusResult = await updateStatus(admin, attempt, result.data);
      const refreshed = await getAttempt(admin, attempt.id);
      await recordEvent(admin, attempt.id, result.ok ? "QUERY_SUCCEEDED" : "QUERY_FAILED", { internalStatus: statusResult.status, providerHttpStatus: result.status, durationMs: Date.now() - startedAt, errorCode: result.ok ? undefined : `HTTP_${result.status}` });
      return response(req, { success: result.ok, ...statusResult, attempt: refreshed }, result.ok ? 200 : 502);
    }

    return response(req, { error: "Unknown action" }, 404);
  } catch (error) {
    console.error("GDC QRIS request failed", error instanceof Error ? error.message : "unknown");
    return response(req, { error: "GDC payment request failed" }, 500);
  }
});
