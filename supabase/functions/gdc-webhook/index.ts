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

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

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
  const paymentDate = parseGdcCallbackPaymentDate(payload);

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

  // Handle status gagal (06 = FAILED) for observability only; the ledger
  // update happens after the MPM record is validated below.
  if (transactionStatus === "06") {
    console.warn("GDC reports failed QRIS transaction", {
      partnerReferenceNo,
      referenceNo,
    });
  }

  // QR MPM has its own immutable payment ledger and settlement RPC. This is
  // the only supported GDC callback path; legacy invoice callbacks are not
  // processed here.
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
    if (transactionStatus !== "00") {
      return jsonResponse(
        { responseCode: "4000000", responseMessage: "Unsupported transaction status" },
        400,
      );
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

  return jsonResponse(
    { responseCode: "4040000", responseMessage: "QR MPM payment not found" },
    404,
  );
});
