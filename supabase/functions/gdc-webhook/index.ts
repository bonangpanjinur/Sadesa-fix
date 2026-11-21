import { serve } from "https://deno.land/std@0.190.0/http/server.ts";

// Deliberately disabled: the legacy callback contract is not the canonical
// QRIS MPM settlement path. Status is queried by gdc-qris-mpm and settled only
// by settle_gdc_qris_mpm_payment after reference and amount validation.
serve(async (_req) => new Response(JSON.stringify({
  responseCode: "4030000",
  responseMessage: "Legacy GDC webhook disabled until provider signature contract is confirmed; use QRIS MPM reconciliation.",
}), { status: 403, headers: { "Content-Type": "application/json" } }));
