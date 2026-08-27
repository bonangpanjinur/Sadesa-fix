import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const workerSecret = Deno.env.get("WORKER_CRON_SECRET");
const maxBatch = Math.min(Number(Deno.env.get("NOTIFICATION_WORKER_BATCH_SIZE") ?? "25"), 100);

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
}

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

type NotificationJob = {
  id: string;
  channel: "whatsapp" | "push" | "email" | "in_app";
  template_key: string;
  payload: Record<string, unknown>;
  attempts: number;
  max_attempts: number;
};

type ProviderResult = { providerMessageId?: string };

async function syncCampaignDelivery(job: NotificationJob, success: boolean, providerMessageId?: string, errorMessage?: string) {
  const deliveryId = typeof job.payload.delivery_id === "string" ? job.payload.delivery_id : null;
  const campaignId = typeof job.payload.campaign_id === "string" ? job.payload.campaign_id : null;
  if (!deliveryId) return;
  await supabase.from("crm_campaign_deliveries").update({
    status: success ? "sent" : "failed",
    provider_message_id: providerMessageId ?? null,
    error_message: success ? null : (errorMessage ?? "Notification delivery failed"),
    sent_at: success ? new Date().toISOString() : null,
  }).eq("id", deliveryId);
  if (campaignId) {
    const { count } = await supabase.from("crm_campaign_deliveries")
      .select("id", { count: "exact", head: true })
      .eq("campaign_id", campaignId).in("status", ["queued", "failed"]);
    if ((count ?? 0) === 0) {
      await supabase.from("crm_campaigns").update({ status: "sent", sent_at: new Date().toISOString() }).eq("id", campaignId).eq("status", "sending");
    }
  }
}

function json(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function isAuthorized(req: Request) {
  const suppliedSecret = req.headers.get("x-worker-secret");
  const auth = req.headers.get("authorization") ?? "";
  return Boolean(workerSecret && suppliedSecret === workerSecret)
    || auth === `Bearer ${serviceRoleKey}`;
}

function normalizePhone(value: unknown) {
  if (typeof value !== "string") return null;
  const phone = value.replace(/[^0-9]/g, "");
  return phone.length >= 8 && phone.length <= 15 ? phone : null;
}

async function sendWhatsApp(job: NotificationJob): Promise<ProviderResult> {
  const token = Deno.env.get("WHATSAPP_ACCESS_TOKEN");
  const phoneNumberId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID");
  const apiVersion = Deno.env.get("WHATSAPP_API_VERSION") ?? "v22.0";
  const payload = job.payload;
  const recipient = normalizePhone(payload.to ?? payload.phone ?? payload.recipient);
  if (!token || !phoneNumberId) throw new Error("WhatsApp provider is not configured");
  if (!recipient) throw new Error("WhatsApp recipient is invalid");

  const message = typeof payload.message === "string" ? payload.message.trim() : "";
  const templateName = typeof payload.template_name === "string" ? payload.template_name.trim() : "";
  const languageCode = typeof payload.language_code === "string" ? payload.language_code : "id";
  const body: Record<string, unknown> = {
    messaging_product: "whatsapp",
    to: recipient,
  };
  if (templateName) {
    body.type = "template";
    body.template = { name: templateName, language: { code: languageCode }, components: Array.isArray(payload.components) ? payload.components : [] };
  } else if (message.length > 0 && message.length <= 4096) {
    body.type = "text";
    body.text = { preview_url: false, body: message };
  } else {
    throw new Error("WhatsApp message or template is required");
  }

  const response = await fetch(`https://graph.facebook.com/${apiVersion}/${phoneNumberId}/messages`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) {
    const providerMessage = typeof result?.error?.message === "string" ? result.error.message.slice(0, 300) : `HTTP ${response.status}`;
    throw new Error(`WhatsApp provider rejected message: ${providerMessage}`);
  }
  const providerMessageId = Array.isArray(result?.messages) && typeof result.messages[0]?.id === "string" ? result.messages[0].id : undefined;
  return { providerMessageId };
}

async function sendJob(job: NotificationJob): Promise<ProviderResult> {
  if (job.channel === "whatsapp") return sendWhatsApp(job);
  if (job.channel === "in_app") return {};
  throw new Error(`Unsupported notification channel: ${job.channel}`);
}

async function processBatch() {
  const { error: dispatchError } = await supabase.rpc("enqueue_due_crm_campaign_jobs", { p_limit: maxBatch });
  if (dispatchError) throw dispatchError;
  const { data: candidates, error: candidateError } = await supabase
    .from("notification_delivery_jobs")
    .select("id")
    .in("status", ["queued", "failed"])
    .lte("next_attempt_at", new Date().toISOString())
    .order("next_attempt_at", { ascending: true })
    .limit(maxBatch);
  if (candidateError) throw candidateError;

  let sent = 0;
  let failed = 0;
  let claimed = 0;
  for (const candidate of candidates ?? []) {
    const { data: job, error: claimError } = await supabase.rpc("claim_notification_delivery_job", { p_job_id: candidate.id });
    if (claimError || !job) continue;
    claimed++;
    try {
      if ((job as NotificationJob).channel === "whatsapp") {
        const { error: entitlementError } = await supabase.rpc("consume_whatsapp_delivery_usage", { p_job_id: job.id });
        if (entitlementError) throw entitlementError;
      }
      const result = await sendJob(job as NotificationJob);
      const { error } = await supabase.rpc("complete_notification_delivery_job", {
        p_job_id: job.id,
        p_success: true,
        p_provider_message_id: result.providerMessageId ?? null,
        p_error: null,
      });
      if (error) throw error;
      await syncCampaignDelivery(job as NotificationJob, true, result.providerMessageId);
      sent++;
    } catch (error) {
      const message = error instanceof Error ? error.message.slice(0, 500) : "Unknown provider error";
      await supabase.rpc("complete_notification_delivery_job", {
        p_job_id: job.id,
        p_success: false,
        p_provider_message_id: null,
        p_error: message,
      });
      await syncCampaignDelivery(job as NotificationJob, false, undefined, message);
      failed++;
      console.error(JSON.stringify({ event: "notification_delivery_failed", job_id: job.id, channel: job.channel, attempts: job.attempts, error: message }));
    }
  }
  return { candidates: candidates?.length ?? 0, claimed, sent, failed };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!isAuthorized(req)) return json({ error: "Worker authentication required" }, 401);
  try {
    return json({ ok: true, ...(await processBatch()) });
  } catch (error) {
    console.error(JSON.stringify({ event: "notification_worker_failed", error: error instanceof Error ? error.message : "Unknown error" }));
    return json({ error: "Notification worker failed" }, 500);
  }
});
