import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const allowedRoles = new Set(["admin", "verifikator", "merchant", "courier", "admin_desa", "buyer"]);
const corsHeaders = {
  "Access-Control-Allow-Origin": "https://desamart.id",
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

    const body = await req.json().catch(() => null) as {
      email?: unknown;
      password?: unknown;
      fullName?: unknown;
      phone?: unknown;
      role?: unknown;
    } | null;
    const email = typeof body?.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = typeof body?.password === "string" ? body.password : "";
    const fullName = typeof body?.fullName === "string" ? body.fullName.trim() : "";
    const phone = typeof body?.phone === "string" ? body.phone.trim() : null;
    const role = typeof body?.role === "string" ? body.role : "buyer";

    if (!/^\S+@\S+\.\S+$/.test(email) || email.length > 254) return json({ error: "Invalid email" }, 400);
    if (password.length < 12 || password.length > 128) return json({ error: "Password must be 12-128 characters" }, 400);
    if (fullName.length < 2 || fullName.length > 120) return json({ error: "Invalid full name" }, 400);
    if (phone && phone.length > 32) return json({ error: "Invalid phone" }, 400);
    if (!allowedRoles.has(role)) return json({ error: "Invalid role" }, 400);

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName },
    });
    if (createError || !created.user) return json({ error: "Unable to create user" }, 400);

    const userId = created.user.id;
    try {
      if (phone) {
        const { error } = await admin.from("profiles").update({ phone }).eq("user_id", userId);
        if (error) throw error;
      }
      if (role !== "buyer") {
        const { error } = await admin.from("user_roles").insert({ user_id: userId, role });
        if (error) throw error;
      }
    } catch (error) {
      await admin.auth.admin.deleteUser(userId);
      console.error("User provisioning failed", error instanceof Error ? error.message : "unknown");
      return json({ error: "Unable to provision user" }, 500);
    }

    return json({ user: { id: userId, email, fullName, role } }, 201);
  } catch (error) {
    console.error("Admin user creation failed", error instanceof Error ? error.message : "unknown");
    return json({ error: "Unable to create user" }, 500);
  }
});
