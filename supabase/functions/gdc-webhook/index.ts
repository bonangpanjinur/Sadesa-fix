import { serve } from "https://deno.land/std@0.190.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://sadesa.id",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-timestamp, x-partner-id, x-external-id, x-signature, channel-id, x-device-id",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  Vary: "Origin",
};

interface GdcQrisCallback {
  originalPartnerReferenceNo: string;
  originalReferenceNo: string;
  latestTransactionStatus: string;
  transactionStatusDesc: string;
  paidAmount: {
    value: string;
    currency: string;
  };
  feeAmount: {
    value: string;
    currency: string;
  };
  additionalInfo: {
    paymentDate: string;
    paymentMethod: string;
    remarks?: string;
    transactionType: string;
  };
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function logEvent(
  event: string,
  context: Record<string, string | number | boolean | null> = {},
) {
  console.log(
    JSON.stringify({
      source: "gdc-webhook",
      event,
      at: new Date().toISOString(),
      context,
    }),
  );
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isMoney(value: unknown): value is { value: string; currency: string } {
  if (typeof value !== "object" || value === null) return false;

  const money = value as Record<string, unknown>;

  return (
    typeof money.value === "string" &&
    Number.isFinite(Number(money.value)) &&
    Number(money.value) >= 0 &&
    money.currency === "IDR"
  );
}

function isValidCallback(body: unknown): body is GdcQrisCallback {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return false;
  }

  const payload = body as Record<string, unknown>;
  const additionalInfo = payload.additionalInfo;

  if (
    typeof additionalInfo !== "object" ||
    additionalInfo === null ||
    Array.isArray(additionalInfo)
  ) {
    return false;
  }

  const info = additionalInfo as Record<string, unknown>;

  return (
    isNonEmptyString(payload.originalPartnerReferenceNo) &&
    isNonEmptyString(payload.originalReferenceNo) &&
    ["00", "06"].includes(String(payload.latestTransactionStatus)) &&
    isNonEmptyString(payload.transactionStatusDesc) &&
    isMoney(payload.paidAmount) &&
    isMoney(payload.feeAmount) &&
    isNonEmptyString(info.paymentDate) &&
    isNonEmptyString(info.paymentMethod) &&
    isNonEmptyString(info.transactionType)
  );
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: corsHeaders,
    });
  }

  if (req.method !== "POST") {
    return jsonResponse(
      { responseCode: "4000000", responseMessage: "Method not allowed" },
      405,
    );
  }

  // GDC callback signature verification is intentionally not implemented yet.
  // Never trust a callback or update an order until signature verification
  // follows GDC's exact specification.
  const requiredHeaders = [
    "authorization",
    "x-timestamp",
    "x-partner-id",
    "x-external-id",
    "x-signature",
    "channel-id",
  ];

  const missingHeaders = requiredHeaders.filter(
    (name) => !req.headers.get(name),
  );

  if (missingHeaders.length > 0) {
    logEvent("required_headers_missing", {
      count: missingHeaders.length,
    });

    return jsonResponse(
      {
        responseCode: "4000000",
        responseMessage: "Required callback headers missing",
      },
      400,
    );
  }

  let body: unknown;

  try {
    body = await req.json();
  } catch {
    return jsonResponse(
      { responseCode: "4000000", responseMessage: "Invalid JSON" },
      400,
    );
  }

  if (!isValidCallback(body)) {
    logEvent("invalid_payload");

    return jsonResponse(
      { responseCode: "4000000", responseMessage: "Invalid callback payload" },
      400,
    );
  }

  logEvent("callback_received_unverified", {
    hasPartnerReference: true,
    hasProviderReference: true,
    status: body.latestTransactionStatus,
    currency: body.paidAmount.currency,
  });

  // Do not process payment yet. Headers are only checked for presence;
  // their cryptographic authenticity has NOT been verified.
  return jsonResponse(
    {
      responseCode: "4010000",
      responseMessage: "Callback signature verification is not configured",
    },
    401,
  );
});
