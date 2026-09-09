import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const workerSecret = Deno.env.get("WORKER_CRON_SECRET");
const maxBatch = Math.min(Number(Deno.env.get("CHAT_RETENTION_BATCH_SIZE") ?? "500"), 5000);

if (!supabaseUrl || !serviceRoleKey) throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
const supabase = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
type ExpiredMessage = { id: string; attachment_path: string | null };

function json(data: Record<string, unknown>, status = 200) { return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } }); }
function isAuthorized(req: Request) { const suppliedSecret = req.headers.get("x-worker-secret"); const auth = req.headers.get("authorization") ?? ""; return Boolean(workerSecret && suppliedSecret === workerSecret) || auth === `Bearer ${serviceRoleKey}`; }
function safeAttachmentPath(path: string | null): path is string { return Boolean(path && path.length <= 1024 && !path.includes("..") && !path.startsWith("/") && /^[A-Za-z0-9._/-]+$/.test(path)); }

async function processRetention(runId: string) {
  const { data: softDeleted, error: softDeleteError } = await supabase.rpc("soft_delete_expired_chat_messages", { p_limit: maxBatch });
  if (softDeleteError) throw softDeleteError;
  const { data: candidates, error: candidateError } = await supabase.rpc("list_hard_expired_chat_messages", { p_limit: maxBatch });
  if (candidateError) throw candidateError;
  const expired = (candidates ?? []) as ExpiredMessage[];
  const paths = expired.map((message) => message.attachment_path).filter(safeAttachmentPath).filter((path, index, values) => values.indexOf(path) === index);
  let removedObjects = 0;
  if (paths.length > 0) {
    const { error: storageError } = await supabase.storage.from("chat-images").remove(paths);
    if (storageError) throw storageError;
    removedObjects = paths.length;
  }
  const ids = expired.map((message) => message.id);
  let hardDeleted = 0;
  if (ids.length > 0) {
    const { data, error: hardDeleteError } = await supabase.rpc("hard_delete_chat_messages", { p_message_ids: ids });
    if (hardDeleteError) throw hardDeleteError;
    hardDeleted = Number(data ?? 0);
  }
  const result = { soft_deleted: Number(softDeleted ?? 0), hard_delete_candidates: expired.length, hard_deleted: hardDeleted, attachment_objects_removed: removedObjects };
  const { error: metricError } = await supabase.rpc("record_chat_retention_run", { p_run_id: runId, p_status: "completed", p_soft_deleted: result.soft_deleted, p_hard_delete_candidates: result.hard_delete_candidates, p_hard_deleted: result.hard_deleted, p_attachment_objects_removed: result.attachment_objects_removed });
  if (metricError) throw metricError;
  return result;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!isAuthorized(req)) return json({ error: "Worker authentication required" }, 401);
  const { data: run, error: runError } = await supabase.from("chat_retention_runs").insert({ status: "running" }).select("id").single();
  if (runError || !run) return json({ error: "Unable to start retention run" }, 500);
  try { return json({ ok: true, ...(await processRetention(run.id)) }); }
  catch (error) {
    const errorMessage = error instanceof Error ? error.message : "Unknown error";
    await supabase.rpc("record_chat_retention_run", { p_run_id: run.id, p_status: "failed", p_error_code: "RETENTION_WORKER_FAILED", p_error_message: errorMessage });
    console.error(JSON.stringify({ event: "chat_retention_worker_failed", error_code: "RETENTION_WORKER_FAILED" }));
    return json({ error: "Chat retention worker failed" }, 500);
  }
});
