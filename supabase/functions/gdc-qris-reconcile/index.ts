import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers: { "Content-Type": "application/json" } });
  }
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const auth = req.headers.get("authorization") || "";
  if (!url || !serviceRoleKey || auth !== `Bearer ${serviceRoleKey}`) {
    return new Response(JSON.stringify({ error: "Service role required" }), { status: 401, headers: { "Content-Type": "application/json" } });
  }
  const admin = createClient(url, serviceRoleKey, { auth: { persistSession: false } });
  const { data, error } = await admin.rpc("reconcile_gdc_qris_mpm_payments");
  if (error) {
    console.error("GDC reconciliation failed", { code: error.code || null });
    return new Response(JSON.stringify({ error: "Reconciliation failed" }), { status: 503, headers: { "Content-Type": "application/json" } });
  }
  return new Response(JSON.stringify({ status: "OK", expired: Number(data || 0), settlement: "canonical settle_gdc_qris_mpm_payment" }), { headers: { "Content-Type": "application/json" } });
});
