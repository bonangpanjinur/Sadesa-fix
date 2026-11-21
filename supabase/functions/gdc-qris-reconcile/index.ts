import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const encoder = new TextEncoder();
const API_BASE = (Deno.env.get("GDC_API_BASE_URL") || "https://neo-sandbox-api.gdc.co.id/snap").replace(/\/$/, "");
const QUERY_PATH = "/v1.0/qr/qr-mpm-query";
let tokenCache: { token: string; expiresAt: number } | null = null;

type Payment = {
  order_id: string; partner_reference_no: string; external_id: string;
  reference_no: string | null; amount: number; status: string;
};

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
function base64(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
function pemBytes(pem: string) {
  const normalized = pem.replace(/\\n/g, "\n");
  const match = normalized.match(/-----BEGIN PRIVATE KEY-----([\s\S]+?)-----END PRIVATE KEY-----/);
  if (!match) throw new Error("GDC private key must be PKCS#8 PEM");
  const binary = atob(match[1].replace(/\s/g, ""));
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}
async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
function timestamp() { return new Date().toISOString(); }
async function accessToken() {
  const clientKey = Deno.env.get("GDC_CLIENT_KEY") || "";
  const clientSecret = Deno.env.get("GDC_CLIENT_SECRET") || "";
  const privatePem = Deno.env.get("GDC_PRIVATE_KEY_PEM") || "";
  if (!clientKey || !clientSecret || !privatePem) throw new Error("GDC credentials incomplete");
  if (tokenCache && tokenCache.expiresAt > Date.now() + 30_000) return tokenCache.token;
  const now = timestamp();
  const keyBytes = pemBytes(privatePem);
  const keyBuffer = new ArrayBuffer(keyBytes.byteLength);
  new Uint8Array(keyBuffer).set(keyBytes);
  const key = await crypto.subtle.importKey("pkcs8", keyBuffer, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, encoder.encode(`${clientKey}|${now}`));
  const result = await fetch(`${API_BASE}/v1.0/access-token/b2b`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Timestamp": now, "Client-Key": clientKey, "X-Signature": base64(new Uint8Array(signature)) },
    body: JSON.stringify({ grantType: "client_credentials" }),
  });
  const data = await result.json().catch(() => ({})) as { responseCode?: string; accessToken?: string; expiresIn?: string };
  if (!result.ok || data.responseCode !== "2007300" || !data.accessToken) throw new Error("GDC access token failed");
  tokenCache = { token: data.accessToken, expiresAt: Date.now() + Math.max(60, Number(data.expiresIn || 900)) * 1000 };
  return data.accessToken;
}
async function queryGdc(payment: Payment) {
  const partnerId = Deno.env.get("GDC_PARTNER_ID") || "";
  const channelId = Deno.env.get("GDC_CHANNEL_ID") || "";
  const deviceId = Deno.env.get("GDC_DEVICE_ID") || "";
  const secret = Deno.env.get("GDC_CLIENT_SECRET") || "";
  if (!payment.reference_no || !partnerId || !channelId || !deviceId || !secret) throw new Error("GDC query configuration incomplete");
  const token = await accessToken();
  const body = { originalReferenceNo: payment.reference_no, originalPartnerReferenceNo: payment.partner_reference_no, originalExternalId: payment.external_id, serviceCode: "47", additionalInfo: {} };
  const now = timestamp();
  const payloadHash = await sha256(JSON.stringify(body));
  const signingKey = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-512" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", signingKey, encoder.encode(`POST:${QUERY_PATH}:${token}:${payloadHash}:${now}`));
  const result = await fetch(`${API_BASE}${QUERY_PATH}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", "X-TIMESTAMP": now, "X-PARTNER-ID": partnerId, "X-EXTERNAL-ID": payment.external_id, "X-DEVICE-ID": deviceId, "CHANNEL-ID": channelId, "X-Signature": base64(new Uint8Array(signature)) },
    body: JSON.stringify(body),
  });
  const data = await result.json().catch(() => ({})) as Record<string, unknown>;
  if (!result.ok || data.responseCode !== "2005100" || data.originalReferenceNo !== payment.reference_no || data.originalPartnerReferenceNo !== payment.partner_reference_no || data.originalExternalId !== payment.external_id || data.serviceCode !== "47") throw new Error("GDC response reference mismatch");
  return data;
}
function amount(value: unknown): number | null {
  if (!value || typeof value !== "object") return null;
  const raw = (value as { value?: unknown }).value;
  if (typeof raw !== "string" && typeof raw !== "number") return null;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? Math.round(parsed * 100) : null;
}
async function run(admin: ReturnType<typeof createClient>) {
  const { data: payments, error } = await admin.from("gdc_qris_mpm_payments").select("order_id, partner_reference_no, external_id, reference_no, amount, status").eq("status", "PENDING").not("reference_no", "is", null).limit(20);
  if (error) throw error;
  let checked = 0; let settled = 0; let failed = 0;
  for (const payment of (payments || []) as Payment[]) {
    checked += 1;
    try {
      const queried = await queryGdc(payment);
      if (queried.latestTransactionStatus === "00") {
        const paidAmount = amount(queried.amount);
        if (queried.amount && (queried.amount as { currency?: unknown }).currency !== "IDR" || paidAmount !== Math.round(Number(payment.amount) * 100)) throw new Error("GDC amount mismatch");
        const { error: settleError } = await admin.rpc("settle_gdc_qris_mpm_payment", { p_order_id: payment.order_id, p_partner_reference_no: payment.partner_reference_no, p_reference_no: payment.reference_no, p_paid_amount: Number(payment.amount), p_paid_at: typeof queried.paidTime === "string" ? queried.paidTime : null });
        if (settleError) throw settleError;
        settled += 1;
      } else if (queried.latestTransactionStatus === "06") {
        await admin.from("gdc_qris_mpm_payments").update({ status: "FAILED", provider_response_code: "06", updated_at: new Date().toISOString() }).eq("order_id", payment.order_id).eq("status", "PENDING");
        failed += 1;
      }
    } catch (error) {
      console.error("GDC reconciliation item failed", { orderId: payment.order_id, message: error instanceof Error ? error.message : "unknown" });
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  const { data: expired, error: expireError } = await admin.rpc("reconcile_gdc_qris_mpm_payments");
  if (expireError) throw expireError;
  return { checked, settled, failed, expired: Number(expired || 0) };
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
