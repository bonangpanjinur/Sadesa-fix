import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";
import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { parseGdcCallbackPaymentDate, validateGdcMpmCallback } from "../_shared/gdcMpmCallback.ts";

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );

  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function hmacSha512Base64(
  secret: string,
  message: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );

  return btoa(
    [...new Uint8Array(signature)]
      .map((byte) => String.fromCharCode(byte))
      .join(""),
  );
}

function safeEqual(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const left = encoder.encode(a);
  const right = encoder.encode(b);

  if (left.length !== right.length) return false;

  let result = 0;
  for (let i = 0; i < left.length; i++) {
    result |= left[i] ^ right[i];
  }

  return result === 0;
}

function parseAmount(value: unknown): number | null {
  const raw = value && typeof value === "object" && !Array.isArray(value) && "value" in value
    ? (value as { value: unknown }).value
    : value;
  if (typeof raw !== "string" && typeof raw !== "number") return null;
  if (typeof raw === "string" && !/^\d+(?:\.\d{1,2})?$/.test(raw)) return null;
  const amount = Number(raw);
  const cents = Math.round(amount * 100);
  return Number.isFinite(amount) && amount > 0 && Number.isSafeInteger(cents) ? cents / 100 : null;
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse(
      { responseCode: "4050000", responseMessage: "Method not allowed" },
      405,
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const clientSecret = Deno.env.get("GDC_CLIENT_SECRET");
  const expectedPartnerId = Deno.env.get("GDC_PARTNER_ID");

  if (!supabaseUrl || !serviceRoleKey || !clientSecret || !expectedPartnerId) {
    console.error("Webhook configuration is incomplete");
    return jsonResponse(
      { responseCode: "5000000", responseMessage: "Configuration error" },
      500,
    );
  }

  const authorization = req.headers.get("authorization") ?? "";
  const timestamp = req.headers.get("x-timestamp") ?? "";
  const partnerId = req.headers.get("x-partner-id") ?? "";
  const externalId = req.headers.get("x-external-id") ?? "";
  const signature = req.headers.get("x-signature") ?? "";

  if (
    !authorization.startsWith("Bearer ") ||
    !timestamp ||
    !partnerId ||
    !externalId ||
    !signature
  ) {
    return jsonResponse(
      { responseCode: "4000000", responseMessage: "Missing required headers" },
      400,
    );
  }

  if (partnerId !== expectedPartnerId) {
    return jsonResponse(
      { responseCode: "4010000", responseMessage: "Invalid partner" },
      401,
    );
  }

  const timestampMs = Date.parse(timestamp);

  if (
    !Number.isFinite(timestampMs) ||
    Math.abs(Date.now() - timestampMs) > 5 * 60 * 1000
  ) {
    return jsonResponse(
      { responseCode: "4010000", responseMessage: "Invalid timestamp" },
      401,
    );
  }

  let rawBody: string;
  let payload: Record<string, unknown>;

  try {
    rawBody = await req.text();
    const parsed: unknown = JSON.parse(rawBody);

    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("Invalid callback body");
    }

    payload = parsed as Record<string, unknown>;
  } catch {
    return jsonResponse(
      { responseCode: "4000000", responseMessage: "Invalid JSON" },
      400,
    );
  }

  const accessToken = authorization.slice("Bearer ".length);
  const minifiedBody = JSON.stringify(payload);
  const bodyHash = await sha256Hex(minifiedBody);
  const path = new URL(req.url).pathname;

  const stringToSign = `POST:${path}:${accessToken}:${bodyHash}:${timestamp}`;
  const expectedSignature = await hmacSha512Base64(clientSecret, stringToSign);

  if (!safeEqual(signature, expectedSignature)) {
    console.error("GDC webhook signature verification failed");
    return jsonResponse(
      { responseCode: "4010000", responseMessage: "Invalid signature" },
      401,
    );
  }

  const partnerReferenceNo = payload.originalPartnerReferenceNo;
  const referenceNo = payload.originalReferenceNo;
  const transactionStatus = payload.latestTransactionStatus;
  const amountPayload = payload.amount ?? payload.paidAmount;
  const paidAmount = parseAmount(amountPayload);

  const additionalInfo =
    payload.additionalInfo && typeof payload.additionalInfo === "object"
      ? (payload.additionalInfo as Record<string, unknown>)
      : {};

  const paymentDate =
    typeof additionalInfo.paymentDate === "string"
      ? additionalInfo.paymentDate
      : new Date().toISOString();

  if (
    typeof partnerReferenceNo !== "string" ||
    typeof referenceNo !== "string" ||
    typeof transactionStatus !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(partnerReferenceNo)
  ) {
    return jsonResponse(
      { responseCode: "4000000", responseMessage: "Invalid callback fields" },
      400,
    );
  }

  // Handle status gagal (06 = FAILED)
  if (transactionStatus === "06") {
    console.warn("GDC reports failed QRIS transaction", {
      partnerReferenceNo,
      referenceNo,
    });

  // QR MPM has its own immutable payment ledger and settlement RPC. Do not
  // route these callbacks through the legacy invoice webhook path.
  const { data: mpmPayment, error: mpmLookupError } = await supabase
    .from("gdc_qris_mpm_payments")
    .select("order_id, partner_reference_no, reference_no, provider_external_id, amount, currency, status")
    .eq("partner_reference_no", partnerReferenceNo)
    .maybeSingle();
  if (mpmLookupError) {
    console.error("Failed to load GDC QR MPM ledger", { code: mpmLookupError.code });
    return jsonResponse({ responseCode: "5000000", responseMessage: "QR MPM ledger unavailable" }, 500);
  }
  if (mpmPayment) {
    const validation = validateGdcMpmCallback(payload, {
      ...mpmPayment,
      external_id: mpmPayment.provider_external_id,
    });
    if (!validation.ok) {
      console.warn("Rejected GDC QR MPM callback", { reason: validation.reason, orderId: mpmPayment.order_id });
      return jsonResponse({ responseCode: "4000000", responseMessage: "QR MPM payment details mismatch" }, 400);
    }
    if (transactionStatus === "06") {
      const { error: failureError } = await supabase.rpc("record_gdc_qris_mpm_failure", {
        p_order_id: mpmPayment.order_id,
        p_partner_reference_no: mpmPayment.partner_reference_no,
        p_reference_no: referenceNo,
        p_external_id: mpmPayment.provider_external_id,
        p_currency: validation.currency,
        p_paid_amount: validation.paidAmount,
      });
      if (failureError) {
        console.error("Failed to record GDC QR MPM failure", { code: failureError.code, orderId: mpmPayment.order_id });
        return jsonResponse({ responseCode: "5000000", responseMessage: "QR MPM failure notification failed" }, 500);
      }
      return jsonResponse({ responseCode: "2000000", responseMessage: "Failure notification acknowledged" });
    }
    if (!paymentDate) {
      return jsonResponse({ responseCode: "4000000", responseMessage: "Invalid payment date" }, 400);
    }
    const { error: settlementError } = await supabase.rpc("settle_gdc_qris_mpm_payment", {
      p_order_id: mpmPayment.order_id,
      p_partner_reference_no: mpmPayment.partner_reference_no,
      p_reference_no: referenceNo,
      p_external_id: mpmPayment.provider_external_id,
      p_currency: validation.currency,
      p_paid_amount: validation.paidAmount,
      p_paid_at: paymentDate,
    });
    if (settlementError) {
      console.error("Failed to settle GDC QR MPM callback", { code: settlementError.code, orderId: mpmPayment.order_id });
      return jsonResponse({ responseCode: "5000000", responseMessage: "QR MPM settlement failed" }, 500);
    }
    return jsonResponse({ responseCode: "2000000", responseMessage: "Successful", data: { order_id: mpmPayment.order_id } });
  }

  // Hanya proses status sukses (00 = SUCCESS)
  if (transactionStatus !== "00") {
    return jsonResponse(
      {
        responseCode: "4000000",
        responseMessage: "Unsupported transaction status",
      },
      400,
    );
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  // 1. Ambil order terkait
  const { data: order, error: fetchError } = await admin
    .from("orders")
    .select("id, total, payment_status")
    .eq("id", partnerReferenceNo)
    .maybeSingle();

  if (fetchError || !order) {
    console.error("Webhook order lookup failed:", fetchError?.message);
    return jsonResponse(
      { responseCode: "4040000", responseMessage: "Order not found" },
      404,
    );
  }

  // Idempotency: Jika order sudah status PAID, return response 200 (Success SNAP Standard)
  if (order.payment_status === "PAID") {
    return jsonResponse({
      responseCode: "2000000",
      responseMessage: "Successful (Already processed)",
    });
  }

  // Verifikasi nominal bayar dengan total order
  if (
    paidAmount !== null &&
    Math.abs(paidAmount - Number(order.total)) > 0.01
  ) {
    console.error("Amount mismatch:", {
      expected: order.total,
      received: paidAmount,
    });
    return jsonResponse(
      { responseCode: "4000000", responseMessage: "Payment amount mismatch" },
      400,
    );
  }

  // 2. Update status order menjadi PAID sesuai skema tabel
  const { error: updateError } = await admin
    .from("orders")
    .update({
      payment_status: "PAID",
      payment_paid_at: paymentDate,
      payment_method: "ONLINE",
      payment_channel: "GDC_QRIS",
      payment_invoice_id: referenceNo,
      payment_external_id: externalId,
      status_updated_at: new Date().toISOString(),
    })
    .eq("id", order.id);

  if (updateError) {
    console.error("Failed to update order status:", updateError.message);
    return jsonResponse(
      { responseCode: "5000000", responseMessage: "Database update failed" },
      500,
    );
  }

  return jsonResponse({
    responseCode: "2000000",
    responseMessage: "Successful",
  });
});
