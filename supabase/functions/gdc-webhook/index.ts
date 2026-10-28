import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";
import { serve } from "https://deno.land/std@0.190.0/http/server.ts";

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
  if (!value || typeof value !== "object" || !("value" in value)) {
    return null;
  }

  const raw = (value as { value: unknown }).value;

  if (typeof raw !== "string" && typeof raw !== "number") {
    return null;
  }

  const amount = Number(raw);

  return Number.isFinite(amount) && amount > 0 ? amount : null;
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

  // GDC documentation defines Authorization as Bearer accessToken.
  // Verify the signature before trusting callback contents.
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

  // Confirm with GDC whether callback verification uses this same
  // transactional signature formula and the callback's URL path.
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
  const paidAmount = parseAmount(payload.paidAmount);

  const additionalInfo =
    payload.additionalInfo && typeof payload.additionalInfo === "object"
      ? (payload.additionalInfo as Record<string, unknown>)
      : {};

  const paymentMethod =
    typeof additionalInfo.paymentMethod === "string"
      ? additionalInfo.paymentMethod
      : "qris";

  const paymentDate =
    typeof additionalInfo.paymentDate === "string"
      ? additionalInfo.paymentDate
      : null;

  const currency =
    payload.paidAmount &&
    typeof payload.paidAmount === "object" &&
    "currency" in payload.paidAmount
      ? (payload.paidAmount as { currency?: unknown }).currency
      : null;

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

  // GDC QRIS callback status codes:
  // 00 = SUCCESS, 06 = FAILED.
  // The existing database RPC accepts PAID, EXPIRED and PENDING only.
  // Do not misrepresent FAILED as EXPIRED.
  if (transactionStatus === "06") {
    console.warn("GDC reports failed QRIS transaction", {
      partnerReferenceNo,
      referenceNo,
      externalId,
    });

    return jsonResponse({
      responseCode: "2000000",
      responseMessage: "Failure notification acknowledged",
    });
  }

  if (transactionStatus !== "00") {
    return jsonResponse(
      {
        responseCode: "4000000",
        responseMessage: "Unsupported transaction status",
      },
      400,
    );
  }

  if (
    !paidAmount ||
    currency !== "IDR" ||
    !paymentDate ||
    Number.isNaN(Date.parse(paymentDate))
  ) {
    return jsonResponse(
      { responseCode: "4000000", responseMessage: "Invalid payment details" },
      400,
    );
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  // The existing RPC checks the order, invoice reference and exact amount,
  // and deduplicates events by provider + event key.
  const { data, error } = await supabase.rpc("process_payment_webhook_event", {
    p_provider: "gdc",
    p_event_key: externalId,
    p_invoice_id: referenceNo,
    p_order_id: partnerReferenceNo,
    p_status: "PAID",
    p_paid_at: paymentDate,
    p_payment_method: "QRIS",
    p_payment_channel: paymentMethod,
    p_paid_amount: paidAmount,
  });

  if (error) {
    console.error("Failed to process GDC payment event", {
      code: error.code,
      message: error.message,
    });

    return jsonResponse(
      { responseCode: "5000000", responseMessage: "Payment processing failed" },
      500,
    );
  }

  return jsonResponse({
    responseCode: "2000000",
    responseMessage: "Successful",
    data,
  });
});
