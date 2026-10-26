const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Method not allowed" }, 405);
  }

  try {
    const body: unknown = await req.json();

    if (typeof body !== "object" || body === null || Array.isArray(body)) {
      return jsonResponse(
        { success: false, error: "Invalid request body" },
        400,
      );
    }

    const payload = body as Record<string, unknown>;

    if (
      typeof payload.order_id !== "string" ||
      payload.order_id.trim() === ""
    ) {
      return jsonResponse(
        { success: false, error: "Order ID wajib diisi" },
        400,
      );
    }

    // Belum memproses pembayaran.
    // Validasi signature GDC harus diterapkan sebelum memercayai callback.
    return jsonResponse({
      success: true,
      received: true,
      message: "Payload diterima untuk tahap validasi",
      order_id: payload.order_id,
    });
  } catch {
    return jsonResponse({ success: false, error: "Invalid JSON body" }, 400);
  }
});
