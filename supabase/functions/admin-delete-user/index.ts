import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://sadesa.id",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json" },
});

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const authHeader = req.headers.get("authorization") ?? "";
  if (!supabaseUrl || !serviceRoleKey || !anonKey || !authHeader.startsWith("Bearer ")) {
    return json({ error: "Unauthorized" }, 401);
  }

  try {
    const token = authHeader.slice(7);
    const userClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: caller, error: callerError } = await userClient.auth.getUser();
    if (callerError || !caller.user) return json({ error: "Unauthorized" }, 401);

    const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
    const { data: adminRole, error: roleLookupError } = await admin
      .from("user_roles")
      .select("role")
      .eq("user_id", caller.user.id)
      .eq("role", "admin")
      .maybeSingle();
    if (roleLookupError || !adminRole) return json({ error: "Forbidden" }, 403);

    const body = await req.json().catch(() => null) as { userId?: unknown } | null;
    const userId = typeof body?.userId === "string" ? body.userId.trim() : "";
    if (!/^[0-9a-f-]{36}$/i.test(userId)) return json({ error: "Invalid user ID" }, 400);
    if (userId === caller.user.id) return json({ error: "Admin tidak dapat menghapus akun sendiri" }, 400);

    const { data: targetRoles, error: targetRolesError } = await admin
      .from("user_roles")
      .select("role")
      .eq("user_id", userId);
    if (targetRolesError) return json({ error: "Unable to inspect target user" }, 500);
    if (targetRoles?.some(({ role }) => role === "admin")) {
      const { count, error: adminCountError } = await admin
        .from("user_roles")
        .select("user_id", { count: "exact", head: true })
        .eq("role", "admin");
      if (adminCountError) return json({ error: "Unable to verify administrator count" }, 500);
      if ((count ?? 0) <= 1) return json({ error: "Administrator terakhir tidak dapat dihapus" }, 400);
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) {
      console.error("Auth user deletion failed", deleteError.message);
      return json({ error: "Gagal menghapus akun. Pastikan data terkait sudah tidak memiliki referensi wajib." }, 409);
    }

    return json({ success: true });
  } catch (error) {
    console.error("Admin user deletion failed", error instanceof Error ? error.message : "unknown");
    return json({ error: "Unable to delete user" }, 500);
  }
});

