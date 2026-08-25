import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const workerSecret = Deno.env.get("WORKER_CRON_SECRET");
const maxBatch = Math.min(Number(Deno.env.get("SUBSCRIPTION_WORKER_BATCH_SIZE") ?? "25"), 100);

if (!supabaseUrl || !serviceRoleKey) throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
const supabase = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });

function json(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}

function authorized(req: Request) {
  const auth = req.headers.get("authorization") ?? "";
  return Boolean(workerSecret && req.headers.get("x-worker-secret") === workerSecret) || auth === `Bearer ${serviceRoleKey}`;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!authorized(req)) return json({ error: "Worker authentication required" }, 401);
  try {
    const results: Array<Record<string, unknown>> = [];
    for (let index = 0; index < maxBatch; index += 1) {
      const { data, error } = await supabase.rpc("process_one_subscription_billing_event");
      if (error) throw error;
      const result = (data ?? {}) as Record<string, unknown>;
      results.push(result);
      if (result.reason === "empty" || result.processed === false) break;
    }
    const processed = results.filter((result) => result.processed === true).length;
    const failed = results.filter((result) => result.status === "failed").length;
    return json({ ok: true, processed, failed, attempts: results.length });
  } catch (error) {
    console.error(JSON.stringify({ event: "subscription_worker_failed", error: error instanceof Error ? error.message : "Unknown error" }));
    return json({ error: "Subscription event processor failed" }, 500);
  }
});
