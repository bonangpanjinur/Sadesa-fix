import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "https://esm.sh/web-push@3.6.7";

const allowedOrigins = new Set((Deno.env.get("ALLOWED_ORIGINS") ?? "https://sadesa.id")
  .split(",").map((origin) => origin.trim()).filter(Boolean));

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  return {
    "Access-Control-Allow-Origin": allowedOrigins.has(origin) ? origin : "https://sadesa.id",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

interface PushRequest {
  user_id?: string;
  user_ids?: string[];
  role?: string;
  all?: boolean;
  title: string;
  body: string;
  icon?: string;
  url?: string;
  data?: Record<string, unknown>;
}

function isAllowedNotificationUrl(value: string) {
  if (value.startsWith('/') && !value.startsWith('//')) return true;
  try {
    const parsed = new URL(value);
    return parsed.protocol === 'http:' || parsed.protocol === 'https:';
  } catch {
    return false;
  }
}

const PAGE_SIZE = 500;
const DELIVERY_CONCURRENCY = 20;

async function fetchAllPagedRows<T>(
  loadPage: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: unknown }>,
): Promise<T[]> {
  const rows: T[] = [];
  for (let from = 0; ; from += PAGE_SIZE) {
    const { data, error } = await loadPage(from, from + PAGE_SIZE - 1);
    if (error) throw error;
    const page = data ?? [];
    rows.push(...page);
    if (page.length < PAGE_SIZE) return rows;
  }
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: getCorsHeaders(req) });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      headers: { ...getCorsHeaders(req), "Content-Type": "application/json" }, status: 405,
    });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const authHeader = req.headers.get("Authorization");

    if (!authHeader || !supabaseAnonKey) {
      return new Response(
        JSON.stringify({ error: "Authentication required" }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" }, status: 401 }
      );
    }

    const authClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user }, error: authError } = await authClient.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Invalid authentication token" }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" }, status: 401 }
      );
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const recordPushDeliveryLog = async (entry: {
      source: "admin_test" | "admin_broadcast";
      notification_job_id?: string | null;
      push_subscription_id?: string | null;
      recipient_user_id?: string | null;
      title: string;
      status: "sent" | "failed" | "expired";
      provider_status_code?: number | null;
      error_message?: string | null;
    }) => {
      try {
        const { error } = await supabase.from("push_delivery_logs").insert({
          source: entry.source,
          notification_job_id: entry.notification_job_id ?? null,
          push_subscription_id: entry.push_subscription_id ?? null,
          recipient_user_id: entry.recipient_user_id ?? null,
          title: entry.title.trim().slice(0, 160) || "Push notification",
          status: entry.status,
          provider_status_code: entry.provider_status_code ?? null,
          error_message: entry.error_message?.slice(0, 1000) ?? null,
        });
        if (error) console.error("Failed to write push delivery log:", error);
      } catch (error) {
        console.error("Failed to write push delivery log:", error);
      }
    };

    const { data: adminRole, error: roleError } = await supabase
      .from("user_roles")
      .select("user_id")
      .eq("user_id", user.id)
      .eq("role", "admin")
      .maybeSingle();
    if (roleError || !adminRole) {
      return new Response(JSON.stringify({ error: "Admin permission required" }), {
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" }, status: 403,
      });
    }

    const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY");
    const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY");

    const payload: PushRequest = await req.json();
    const { user_id, user_ids, role, all, title, body, icon, url, data } = payload;
    if (typeof title !== "string" || typeof body !== "string"
      || title.trim().length < 1 || title.length > 160
      || body.trim().length < 1 || body.length > 4000) {
      return new Response(JSON.stringify({ error: "Invalid notification content" }), {
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" }, status: 400,
      });
    }
	    if (user_ids && (!Array.isArray(user_ids) || user_ids.length > 5000
	      || user_ids.some((id) => typeof id !== "string" || id.length > 80))) {
      return new Response(JSON.stringify({ error: "Invalid notification recipients" }), {
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" }, status: 400,
      });
    }
	    if (typeof url === "string" && (url.length > 2048 || !isAllowedNotificationUrl(url))) {
      return new Response(JSON.stringify({ error: "Invalid notification URL" }), {
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" }, status: 400,
      });
    }

    const source: "admin_test" | "admin_broadcast" = all === true || Boolean(role) || Boolean(user_ids?.length)
      ? "admin_broadcast"
      : "admin_test";
    const notificationTitle = title.trim().slice(0, 160);

    // Only admins may target a role or broadcast to every subscription.
    if (role || all === true) {
      const { data: adminRole, error: roleError } = await supabase
        .from("user_roles")
        .select("user_id")
        .eq("user_id", user.id)
        .eq("role", "admin")
        .maybeSingle();

      if (roleError || !adminRole) {
        return new Response(
          JSON.stringify({ error: "Admin permission required for broadcast notifications" }),
          { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" }, status: 403 }
        );
      }
    }

    // Validate required fields
    if (!title || !body) {
      return new Response(
        JSON.stringify({ error: "title and body are required" }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" }, status: 400 }
      );
    }

    // Build query to get subscriptions
    let subscriptionQuery = supabase.from("push_subscriptions").select("*");

    if (user_id) {
      subscriptionQuery = subscriptionQuery.eq("user_id", user_id);
    } else if (user_ids && user_ids.length > 0) {
      subscriptionQuery = subscriptionQuery.in("user_id", user_ids);
    } else if (role) {
      // Get users with specific role first
      const roleUsers = await fetchAllPagedRows((from, to) => supabase
        .from("user_roles")
        .select("user_id")
        .eq("role", role)
        .order("user_id", { ascending: true })
        .range(from, to));

      if (!roleUsers || roleUsers.length === 0) {
        await recordPushDeliveryLog({
          source,
          title: notificationTitle,
          status: "failed",
          error_message: "No users with this role",
        });
        return new Response(
          JSON.stringify({ success: true, sent: 0, message: "No users with this role" }),
          { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }

      const userIds = roleUsers.map((u) => u.user_id);
      subscriptionQuery = subscriptionQuery.in("user_id", userIds);
    } else if (all === true) {
      // Broadcast ke seluruh subscription (tanpa filter tambahan)
    } else {
      return new Response(
        JSON.stringify({ error: "user_id, user_ids, role, atau all diperlukan" }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" }, status: 400 }
      );
    }

    if (!vapidPrivateKey || !vapidPublicKey) {
      const message = "VAPID keys not configured";
      await recordPushDeliveryLog({
        source,
        recipient_user_id: user_id ?? null,
        title: notificationTitle,
        status: "failed",
        error_message: message,
      });
      console.log("VAPID keys not configured, skipping push notification");
      return new Response(
        JSON.stringify({ success: false, message }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" }, status: 200 }
      );
    }

    let subscriptions: Array<{
      id: string;
      user_id: string;
      endpoint: string;
      p256dh: string;
      auth: string;
    }>;
    try {
      subscriptions = await fetchAllPagedRows((from, to) => subscriptionQuery
        .order("id", { ascending: true })
        .range(from, to));
    } catch (subError) {
      await recordPushDeliveryLog({
        source,
        recipient_user_id: user_id ?? null,
        title: notificationTitle,
        status: "failed",
        error_message: "Unable to look up push subscriptions",
      });
      throw subError;
    }

    if (!subscriptions || subscriptions.length === 0) {
      await recordPushDeliveryLog({
        source,
        recipient_user_id: user_id ?? null,
        title: notificationTitle,
        status: "failed",
        error_message: "No active push subscriptions found",
      });
      return new Response(
        JSON.stringify({ success: true, sent: 0, message: "No subscriptions found" }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    webpush.setVapidDetails(
      "mailto:admin@sadesa.id",
      vapidPublicKey,
      vapidPrivateKey
    );

    const notificationPayload = JSON.stringify({
      title,
      body,
      icon: icon || "/pwa-192x192.png",
      badge: "/pwa-192x192.png",
      url: url || "/",
      data,
    });

    let sentCount = 0;
    const failedSubscriptions: string[] = [];

    // Bound concurrency to reduce per-device latency without overwhelming the push service.
    for (let offset = 0; offset < subscriptions.length; offset += DELIVERY_CONCURRENCY) {
      const batch = subscriptions.slice(offset, offset + DELIVERY_CONCURRENCY);
      await Promise.all(batch.map(async (sub) => {
        try {
          await webpush.sendNotification(
            {
              endpoint: sub.endpoint,
              keys: {
                p256dh: sub.p256dh,
                auth: sub.auth,
              },
            },
            notificationPayload
          );
          await recordPushDeliveryLog({
            source,
            push_subscription_id: sub.id,
            recipient_user_id: sub.user_id,
            title: notificationTitle,
            status: "sent",
          });
          sentCount++;
        } catch (error: unknown) {
          console.error(`Failed to send to ${sub.endpoint}:`, error);
          const err = error as { statusCode?: number; message?: string };
          const statusCode = typeof err.statusCode === "number" ? err.statusCode : null;
          const expired = statusCode === 410 || statusCode === 404;
          await recordPushDeliveryLog({
            source,
            push_subscription_id: sub.id,
            recipient_user_id: sub.user_id,
            title: notificationTitle,
            status: expired ? "expired" : "failed",
            provider_status_code: statusCode,
            error_message: typeof err.message === "string" ? err.message : "Push provider error",
          });
          if (expired) failedSubscriptions.push(sub.id);
        }
      }));
    }

    // Clean up invalid subscriptions
    if (failedSubscriptions.length > 0) {
      for (let offset = 0; offset < failedSubscriptions.length; offset += PAGE_SIZE) {
        const subscriptionIds = failedSubscriptions.slice(offset, offset + PAGE_SIZE);
        await supabase
          .from("push_subscriptions")
          .delete()
          .in("id", subscriptionIds);
      }
    }

    console.log(`Push notifications sent: ${sentCount}/${subscriptions.length}`);

    return new Response(
      JSON.stringify({
        success: sentCount === subscriptions.length,
        sent: sentCount,
        total: subscriptions.length,
        cleaned: failedSubscriptions.length,
      }),
      { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
    );
  } catch (error: unknown) {
    console.error("Error sending push notification:", error);
    return new Response(
      JSON.stringify({ error: "Unable to send notifications" }),
      { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" }, status: 500 }
    );
  }
});
