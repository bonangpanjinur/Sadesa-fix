import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const ALLOWED_ORIGINS = new Set(["https://sadesa.id", "https://www.sadesa.id"]);

const corsHeaders = {
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info, idempotency-key",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  Vary: "Origin",
};

function respond(
  data: Record<string, unknown>,
  status = 200,
  origin: string | null = null,
) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Access-Control-Allow-Origin":
        origin && ALLOWED_ORIGINS.has(origin) ? origin : "https://sadesa.id",
      "Content-Type": "application/json",
    },
  });
}

function getBearerToken(req: Request): string | null {
  const value = req.headers.get("authorization") ?? "";
  return value.startsWith("Bearer ") ? value.slice(7) : null;
}

function pemToBytes(pem: string): Uint8Array {
  const clean = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");

  const binary = atob(clean);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

function base64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function timestampNow(): string {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

async function sha256Hex(value: string): Promise<string> {
  const hash = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );

  return [...new Uint8Array(hash)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function createAccessTokenSignature(
  clientKey: string,
  timestamp: string,
  privateKeyPem: string,
): Promise<string> {
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(privateKeyPem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    privateKey,
    new TextEncoder().encode(`${clientKey}|${timestamp}`),
  );

  return base64(new Uint8Array(signature));
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

  return base64(new Uint8Array(signature));
}

async function getGdcAccessToken(
  baseUrl: string,
  clientKey: string,
  privateKeyPem: string,
): Promise<string> {
  const timestamp = timestampNow();
  const signature = await createAccessTokenSignature(
    clientKey,
    timestamp,
    privateKeyPem,
  );

  const response = await fetch(`${baseUrl}/v1.0/access-token/b2b`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Timestamp": timestamp,
      "Client-Key": clientKey,
      "X-Signature": signature,
    },
    body: JSON.stringify({ grantType: "client_credentials" }),
  });

  const result = await response.json().catch(() => ({}));

  if (!response.ok || typeof result.accessToken !== "string") {
    console.error("GDC token request failed", {
      httpStatus: response.status,
      responseCode: result.responseCode ?? null,
    });
    throw new Error("GDC authentication failed");
  }

  return result.accessToken;
}

async function generateQris(
  baseUrl: string,
  accessToken: string,
  clientSecret: string,
  partnerId: string,
  body: Record<string, unknown>,
  channelId?: string,
  deviceId?: string,
) {
  const path = "/v1.0/qr/qr-mpm-generate";
  const timestamp = timestampNow();
  const externalId = crypto.randomUUID();
  const rawBody = JSON.stringify(body);

  // Confirm the exact signature formula with GDC before production use.
  const bodyHash = await sha256Hex(rawBody);
  const stringToSign = `POST:${path}:${accessToken}:${bodyHash}:${timestamp}`;

  const signature = await hmacSha512Base64(clientSecret, stringToSign);

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Authorization: `Bearer ${accessToken}`,
    "X-TIMESTAMP": timestamp,
    "X-PARTNER-ID": partnerId,
    "X-EXTERNAL-ID": externalId,
    "X-Signature": signature,
  };

  // Optional in the public documentation; include only if GDC
  // has supplied the values for this merchant integration.
  if (channelId) headers["CHANNEL-ID"] = channelId;
  if (deviceId) headers["X-DEVICE-ID"] = deviceId;

  const response = await fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers,
    body: rawBody,
  });

  const result = await response.json().catch(() => ({}));

  if (!response.ok) {
    console.error("GDC QRIS request failed", {
      httpStatus: response.status,
      responseCode: result.responseCode ?? null,
    });
    throw new Error("GDC QRIS request failed");
  }

  if (
    typeof result.responseCode === "string" &&
    !result.responseCode.startsWith("200")
  ) {
    console.error("GDC rejected QRIS request", {
      responseCode: result.responseCode,
    });
    throw new Error("GDC rejected QRIS request");
  }

  return result as Record<string, unknown>;
}

serve(async (req: Request) => {
  const origin = req.headers.get("origin");

  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        ...corsHeaders,
        "Access-Control-Allow-Origin":
          origin && ALLOWED_ORIGINS.has(origin) ? origin : "https://sadesa.id",
      },
    });
  }

  if (req.method !== "POST") {
    return respond(
      { success: false, error: "Method not allowed" },
      405,
      origin,
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  const baseUrl =
    Deno.env.get("GDC_BASE_URL") ?? "https://neo-sandbox-api.gdc.co.id/snap";

  const clientKey = Deno.env.get("GDC_CLIENT_KEY");
  const clientSecret = Deno.env.get("GDC_CLIENT_SECRET");
  const privateKey = Deno.env.get("GDC_PRIVATE_KEY");
  const partnerId = Deno.env.get("GDC_PARTNER_ID");

  // These values are optional; do not invent them.
  const channelId = Deno.env.get("GDC_CHANNEL_ID") || undefined;
  const deviceId = Deno.env.get("GDC_DEVICE_ID") || undefined;
  const accountNumber = Deno.env.get("GDC_ACCOUNT_NUMBER") || undefined;

  if (
    !supabaseUrl ||
    !anonKey ||
    !serviceRoleKey ||
    !clientKey ||
    !clientSecret ||
    !privateKey ||
    !partnerId
  ) {
    console.error("Required payment configuration is missing");
    return respond(
      { success: false, error: "Payment service unavailable" },
      503,
      origin,
    );
  }

  const token = getBearerToken(req);

  if (!token) {
    return respond({ success: false, error: "Unauthorized" }, 401, origin);
  }

  try {
    const userClient = createClient(supabaseUrl, anonKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
      global: {
        headers: { Authorization: `Bearer ${token}` },
      },
    });

    const { data: authData, error: authError } =
      await userClient.auth.getUser();

    if (authError || !authData.user) {
      return respond({ success: false, error: "Unauthorized" }, 401, origin);
    }

    const payload = await req.json().catch(() => null);
    const orderId =
      payload && typeof payload === "object" && !Array.isArray(payload)
        ? (payload as Record<string, unknown>).order_id
        : null;

    if (
      typeof orderId !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(orderId)
    ) {
      return respond(
        { success: false, error: "Invalid order ID" },
        400,
        origin,
      );
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const { data: order, error: orderError } = await admin
      .from("orders")
      .select(
        "id,buyer_id,total,status,payment_status,payment_invoice_id,payment_channel",
      )
      .eq("id", orderId)
      .eq("buyer_id", authData.user.id)
      .maybeSingle();

    if (orderError) {
      console.error("Order lookup failed", orderError.message);
      return respond(
        { success: false, error: "Unable to retrieve order" },
        500,
        origin,
      );
    }

    if (!order) {
      return respond({ success: false, error: "Order not found" }, 404, origin);
    }

    if (
      ["CANCELLED", "CANCELED", "DONE", "REJECTED", "REFUNDED"].includes(
        String(order.status).toUpperCase(),
      ) ||
      order.payment_status === "PAID"
    ) {
      return respond(
        { success: false, error: "Order cannot be paid" },
        409,
        origin,
      );
    }

    if (
      order.payment_channel === "GDC_QRIS" &&
      order.payment_invoice_id &&
      order.payment_status === "PENDING"
    ) {
      return respond(
        {
          success: true,
          reused: true,
          order_id: order.id,
          reference_no: order.payment_invoice_id,
          message: "Existing GDC payment reference found",
        },
        200,
        origin,
      );
    }

    const amount = Number(order.total);

    if (!Number.isSafeInteger(amount) || amount <= 0) {
      return respond(
        { success: false, error: "Invalid order amount" },
        409,
        origin,
      );
    }

    const accessToken = await getGdcAccessToken(baseUrl, clientKey, privateKey);

    const additionalInfo: Record<string, unknown> = {};

    if (accountNumber) {
      additionalInfo.accountNumber = accountNumber;
    }

    // Base request follows the documented QRIS MPM Generate fields.
    // Confirm whether your GDC account requires additional fields.
    const requestBody: Record<string, unknown> = {
      partnerReferenceNo: order.id,
      amount: {
        value: amount.toFixed(2),
        currency: "IDR",
      },
    };

    if (Object.keys(additionalInfo).length > 0) {
      requestBody.additionalInfo = additionalInfo;
    }

    const result = await generateQris(
      baseUrl,
      accessToken,
      clientSecret,
      partnerId,
      requestBody,
      channelId,
      deviceId,
    );

    const extra =
      result.additionalInfo && typeof result.additionalInfo === "object"
        ? (result.additionalInfo as Record<string, unknown>)
        : {};

    const referenceNo =
      typeof result.referenceNo === "string"
        ? result.referenceNo
        : typeof result.originalReferenceNo === "string"
          ? result.originalReferenceNo
          : null;

    const qrContent =
      typeof result.qrContent === "string"
        ? result.qrContent
        : typeof extra.qrContent === "string"
          ? extra.qrContent
          : null;

    const qrImage =
      typeof result.qrImage === "string"
        ? result.qrImage
        : typeof extra.qrImage === "string"
          ? extra.qrImage
          : null;

    const confirmationUrl =
      typeof result.redirectUrl === "string"
        ? result.redirectUrl
        : typeof result.url === "string"
          ? result.url
          : typeof extra.redirectUrl === "string"
            ? extra.redirectUrl
            : null;

    if (!referenceNo || (!qrContent && !qrImage && !confirmationUrl)) {
      console.error("GDC response missing payment details", {
        hasReferenceNo: Boolean(referenceNo),
        hasQrContent: Boolean(qrContent),
        hasQrImage: Boolean(qrImage),
        hasConfirmationUrl: Boolean(confirmationUrl),
      });

      return respond(
        { success: false, error: "Invalid payment response from GDC" },
        502,
        origin,
      );
    }

    const { data: updatedOrder, error: updateError } = await admin
      .from("orders")
      .update({
        payment_invoice_id: referenceNo,
        payment_method: "ONLINE",
        payment_channel: "GDC_QRIS",
        payment_status: "PENDING",
      })
      .eq("id", order.id)
      .eq("buyer_id", authData.user.id)
      .neq("payment_status", "PAID")
      .select("id")
      .maybeSingle();

    if (updateError || !updatedOrder) {
      console.error(
        "Failed to save GDC reference",
        updateError?.message ?? "Order not updated",
      );

      return respond(
        { success: false, error: "Unable to save payment reference" },
        500,
        origin,
      );
    }

    return respond(
      {
        success: true,
        order_id: order.id,
        partner_reference_no: order.id,
        reference_no: referenceNo,
        amount,
        currency: "IDR",
        qr_content: qrContent,
        qr_image: qrImage,
        confirmation_url: confirmationUrl,
      },
      200,
      origin,
    );
  } catch (error) {
    console.error(
      "GDC payment initialization failed",
      error instanceof Error ? error.message : "Unknown error",
    );

    return respond(
      { success: false, error: "Payment service unavailable" },
      502,
      origin,
    );
  }
});
