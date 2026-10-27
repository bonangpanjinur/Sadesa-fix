import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://sadesa.id",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, idempotency-key",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  Vary: "Origin",
};

function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
  origin?: string | null,
): Response {
  const allowedOrigin =
    origin === "https://sadesa.id" || origin === "https://www.sadesa.id"
      ? origin
      : "https://sadesa.id";

  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Access-Control-Allow-Origin": allowedOrigin,
      "Content-Type": "application/json",
    },
  });
}

function getBearerToken(req: Request): string | null {
  const authorization = req.headers.get("authorization") ?? "";

  if (!authorization.startsWith("Bearer ")) {
    return null;
  }

  return authorization.slice(7);
}

serve(async (req: Request) => {
  const origin = req.headers.get("origin");

  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        ...corsHeaders,
        "Access-Control-Allow-Origin":
          origin === "https://www.sadesa.id" ? origin : "https://sadesa.id",
      },
    });
  }

  if (req.method !== "POST") {
    return jsonResponse(
      { success: false, error: "Method not allowed" },
      405,
      origin,
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const token = getBearerToken(req);

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    console.error("Supabase environment is not configured");

    return jsonResponse(
      { success: false, error: "Payment service unavailable" },
      503,
      origin,
    );
  }

  if (!token) {
    return jsonResponse({ success: false, error: "Unauthorized" }, 401, origin);
  }

  try {
    // Authenticate the buyer.
    const userClient = createClient(supabaseUrl, anonKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
      global: {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      },
    });

    const {
      data: { user },
      error: authError,
    } = await userClient.auth.getUser();

    if (authError || !user) {
      return jsonResponse(
        { success: false, error: "Unauthorized" },
        401,
        origin,
      );
    }

    // Read the order securely on the server.
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    let body: unknown;

    try {
      body = await req.json();
    } catch {
      return jsonResponse(
        { success: false, error: "Invalid JSON body" },
        400,
        origin,
      );
    }

    if (typeof body !== "object" || body === null || Array.isArray(body)) {
      return jsonResponse(
        { success: false, error: "Invalid request body" },
        400,
        origin,
      );
    }

    const payload = body as Record<string, unknown>;
    const orderId = payload.order_id;

    if (typeof orderId !== "string" || !/^[0-9a-f-]{36}$/i.test(orderId)) {
      return jsonResponse(
        { success: false, error: "Invalid order ID" },
        400,
        origin,
      );
    }

    const { data: order, error: orderError } = await supabaseAdmin
      .from("orders")
      .select("id, buyer_id, total, status, payment_status")
      .eq("id", orderId)
      .eq("buyer_id", user.id)
      .maybeSingle();

    if (orderError) {
      console.error("Failed to read order", {
        orderId,
        message: orderError.message,
      });

      return jsonResponse(
        { success: false, error: "Unable to retrieve order" },
        500,
        origin,
      );
    }

    if (!order) {
      return jsonResponse(
        { success: false, error: "Order not found" },
        404,
        origin,
      );
    }

    if (
      ["CANCELLED", "DONE"].includes(order.status) ||
      order.payment_status === "PAID"
    ) {
      return jsonResponse(
        { success: false, error: "Order cannot be paid" },
        409,
        origin,
      );
    }

    const amount = Number(order.total);

    if (!Number.isSafeInteger(amount) || amount <= 0) {
      return jsonResponse(
        { success: false, error: "Invalid order amount" },
        409,
        origin,
      );
    }

    // GDC integration is intentionally not called yet.
    // Credentials are still under review, and the correct QRIS
    // payment flow must be confirmed before creating transactions.
    return jsonResponse(
      {
        success: false,
        code: "GDC_NOT_CONFIGURED",
        message:
          "GDC payment is not enabled yet. Please use another available payment method.",
      },
      503,
      origin,
    );
  } catch (error) {
    console.error(
      "GDC payment initialization failed",
      error instanceof Error ? error.message : "Unknown error",
    );

    return jsonResponse(
      { success: false, error: "Payment service unavailable" },
      500,
      origin,
    );
  }
});
