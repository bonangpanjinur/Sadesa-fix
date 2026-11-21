import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";
import { GDC_API_BASE, gdcPost, getGdcCredentials, type GdcCredentials } from "../_shared/gdcSnap.ts";

const API_BASE = GDC_API_BASE;
const GDC_SANDBOX_HOST = "neo-sandbox-api.gdc.co.id";
const API_PATHS = {
  token: "/v1.0/access-token/b2b",
  generate: "/v1.0/qr/qr-mpm-generate",
  query: "/v1.0/qr/qr-mpm-query",
} as const;
const encoder = new TextEncoder();
const corsHeaders = {
  "Access-Control-Allow-Origin": "https://sadesa.id",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
interface PaymentRow {
  order_id: string;
  merchant_id: string;
  partner_reference_no: string;
  external_id: string;
  reference_no: string | null;
  amount: number;
  currency: string;
  qr_content: string | null;
  status: 'CREATING' | 'PENDING' | 'PAID' | 'FAILED' | 'EXPIRED';
  error_code: string | null;
  paid_at: string | null;
}
function allowedOrigins(): Set<string> {
  return new Set((Deno.env.get('ALLOWED_ORIGINS') || 'https://sadesa.id,https://www.sadesa.id')
    .split(',').map((value) => value.trim()).filter(Boolean));
}
function corsFor(req?: Request): Record<string, string> {
  const origin = req?.headers.get('origin') || '';
  const allowed = allowedOrigins();
  return { ...corsHeaders, 'Access-Control-Allow-Origin': allowed.has(origin) ? origin : [...allowed][0] };
}
function json(data: unknown, status = 200, req?: Request): Response {
  return new Response(JSON.stringify(data), { status, headers: { ...corsFor(req), 'Content-Type': 'application/json' } });
}
function getCredentials(): GdcCredentials {
  return getGdcCredentials();
}

function moneyValue(value: number): string {
  if (!Number.isSafeInteger(value) || value <= 0) throw new Error('Nominal order tidak valid.');
  return `${value.toFixed(2)}`;
}
function responsePayment(row: PaymentRow) {
  return {
    order_id: row.order_id,
    status: row.status === 'CREATING' ? 'PENDING' : row.status,
    amount: Number(row.amount),
    currency: 'IDR',
    qr_content: row.qr_content,
    reference_no: row.reference_no,
    paid_at: row.paid_at,
  };
}
function parseAmount(value: string | undefined): number | null {
  if (!value || !/^\d+(?:\.\d{1,6})?$/.test(value)) return null;
  const amount = Number(value);
  return Number.isSafeInteger(Math.round(amount * 100)) ? Math.round(amount * 100) : null;
}
function payment_status_is_pending(value: unknown): boolean { return value !== 'PAID' && value !== 'REFUNDED'; }

async function processRequest(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsFor(req) });
  }
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405, req);
  const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') || '';
  const authHeader = req.headers.get('authorization') || '';
  const missingRuntimeConfig = {
    supabaseUrl: !supabaseUrl,
    serviceRoleKey: !serviceRoleKey,
    anonKey: !anonKey,
  };
  if (Object.values(missingRuntimeConfig).some(Boolean)) {
    console.error('GDC QR MPM Supabase runtime configuration is incomplete', missingRuntimeConfig);
    return json({ error: 'Konfigurasi runtime Supabase Edge Function belum lengkap. Hubungi administrator.' }, 500, req);
  }
  if (!/^Bearer\s+\S+$/i.test(authHeader)) {
    return json({ error: 'Sesi login tidak ditemukan. Silakan masuk kembali lalu coba lagi.' }, 401, req);
  }
  const userClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authHeader } },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) {
    console.warn('GDC QR MPM user session was rejected', { status: authError?.status ?? null });
    return json({ error: 'Sesi login tidak valid atau kedaluwarsa. Silakan masuk kembali lalu coba lagi.' }, 401, req);
  }
  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const input = await req.json().catch(() => null) as { action?: string; order_id?: string; application_id?: string } | null;
  if (!input || !['create', 'status', 'admin_preview'].includes(input.action || '')) {
    return json({ error: 'Permintaan pembayaran tidak valid.' }, 400, req);
  }
  if (input.action === 'admin_preview') {
    if (!input.application_id || !/^[0-9a-f-]{36}$/i.test(input.application_id)) {
      return json({ error: 'Pengajuan QRIS tidak valid.' }, 400, req);
    }
    const previewEnabled = Deno.env.get('GDC_ADMIN_PREVIEW_ENABLED') === 'true';
    if (!previewEnabled || new URL(API_BASE).hostname !== GDC_SANDBOX_HOST) {
      return json({ error: 'Preview QRIS sandbox sedang dinonaktifkan.' }, 409, req);
    }
    const { data: isAdmin, error: adminCheckError } = await userClient.rpc('is_admin');
    if (adminCheckError || isAdmin !== true) return json({ error: 'Akses admin diperlukan untuk uji QRIS.' }, 403, req);
    const { data: application, error: applicationError } = await admin.from('qris_applications')
      .select('gdc_merchant_id, gdc_account_number')
      .eq('id', input.application_id).maybeSingle();
    if (applicationError || !application?.gdc_merchant_id?.trim() || !application?.gdc_account_number?.trim()) {
      return json({ error: 'Mapping MID dan Account Number GDC harus disimpan terlebih dahulu.' }, 409, req);
    }
    try {
      const credentials = getCredentials();
      const amount = 1000;
      const partnerReferenceNo = crypto.randomUUID();
      const externalId = crypto.randomUUID();
      const generated = await gdcPost(credentials, API_PATHS.generate, {
        partnerReferenceNo,
        amount: { value: moneyValue(amount), currency: 'IDR' },
        merchantId: String(application.gdc_merchant_id),
        additionalInfo: { accountNumber: String(application.gdc_account_number) },
      }, externalId);
      if (generated.responseCode !== '2004700'
        || generated.partnerReferenceNo !== partnerReferenceNo
        || !generated.referenceNo
        || !generated.qrContent
        || generated.qrContent.length > 4000) {
        throw new Error('Provider tidak mengembalikan QR uji yang lengkap.');
      }
      return json({
        status: 'PREVIEW',
        amount,
        currency: 'IDR',
        qr_content: generated.qrContent,
        reference_no: generated.referenceNo,
      }, 200, req);
    } catch (error) {
      console.error('GDC QR MPM admin preview failed', error instanceof Error ? error.message : 'unknown');
      return json({ error: error instanceof Error ? error.message : 'QR uji GDC gagal dibuat.' }, 502, req);
    }
  }
  if (!input.order_id || !/^[0-9a-f-]{36}$/i.test(input.order_id)) {
    return json({ error: 'Permintaan pembayaran tidak valid.' }, 400, req);
  }
  const credentials = getCredentials();
  const { data: order, error: orderError } = await admin.from('orders')
    .select('id, buyer_id, merchant_id, total, payment_method, payment_status, status, confirmation_deadline')
    .eq('id', input.order_id).eq('buyer_id', authData.user.id).maybeSingle();
  if (orderError || !order) return json({ error: 'Pesanan tidak ditemukan.' }, 404, req);
  if (order.payment_method !== 'TRANSFER') return json({ error: 'Pesanan ini tidak menggunakan QRIS merchant.' }, 409, req);
  if (['PAID', 'REFUNDED'].includes(String(order.payment_status))) {
    const { data: existing } = await admin.from('gdc_qris_mpm_payments').select('*').eq('order_id', order.id).maybeSingle();
    if (existing) return json(responsePayment(existing as PaymentRow));
    return json({ error: 'Pesanan tidak lagi menunggu pembayaran.' }, 409, req);
  }
  if (input.action === 'create' && (order.payment_status === 'EXPIRED' || order.status === 'CANCELLED' || order.status === 'CANCELED' || order.status === 'REFUNDED')) return json({ error: 'Pesanan telah dibatalkan atau kedaluwarsa.' }, 409, req);
  const deadline = order.confirmation_deadline ? new Date(order.confirmation_deadline).getTime() : null;
  const deadlinePassed = Boolean(deadline && deadline <= Date.now());
  const { data: application, error: applicationError } = await admin.from('qris_applications')
    .select('gdc_merchant_id, gdc_account_number, gdc_mpm_enabled, qris_merchant_name')
    .eq('merchant_id', order.merchant_id).eq('status', 'ACTIVE').eq('gdc_mpm_enabled', true)
    .order('activated_at', { ascending: false }).limit(1).maybeSingle();
  if (applicationError || !application?.gdc_merchant_id || !application?.gdc_account_number) {
    return json({ error: 'QRIS MPM merchant belum aktif atau data akun GDC belum lengkap. Hubungi merchant.' }, 409, req);
  }
  const amount = Number(order.total);
  if (!Number.isSafeInteger(amount) || amount <= 0) return json({ error: 'Nominal pesanan tidak valid.' }, 409, req);
  const { data: paymentRow, error: paymentError } = await admin.from('gdc_qris_mpm_payments').select('*').eq('order_id', order.id).maybeSingle();
  let payment = paymentRow;
  if (paymentError) return json({ error: 'Data pembayaran tidak dapat dimuat.' }, 503, req);
  if (payment && payment.merchant_id !== order.merchant_id) {
    console.error('GDC payment merchant mismatch', { orderId: order.id });
    return json({ error: 'Data pembayaran tidak cocok dengan toko pesanan.' }, 409, req);
  }
  if (payment?.status === 'PENDING' && !(deadlinePassed && input.action === 'status')) return json(responsePayment(payment as PaymentRow));
  if (payment?.status === 'PAID' || payment?.status === 'EXPIRED') return json(responsePayment(payment as PaymentRow));
  if (payment?.status === 'FAILED' && input.action === 'create' && payment.error_code !== 'QR_CREATE_FAILED') {
    return json({ error: 'Pembayaran ini sudah dinyatakan gagal oleh provider. Hubungi merchant untuk instruksi berikutnya.' }, 409, req);
  }
  if (deadlinePassed && !payment) return json({ order_id: order.id, status: 'EXPIRED', amount: Number(order.total), currency: 'IDR', qr_content: null, reference_no: null, paid_at: null }, 200, req);
  if (input.action === 'status' && !payment) return json({ error: 'QRIS pembayaran belum dibuat.' }, 404, req);
  if (!payment) {
    const { data: inserted, error: insertError } = await admin.from('gdc_qris_mpm_payments').insert({
      order_id: order.id,
      merchant_id: order.merchant_id,
      amount,
      currency: 'IDR',
      partner_reference_no: crypto.randomUUID(),
      external_id: crypto.randomUUID(),
      status: 'CREATING',
    }).select('*').single();
    if (insertError) {
      const { data: raced } = await admin.from('gdc_qris_mpm_payments').select('*').eq('order_id', order.id).maybeSingle();
      if (raced) return json(responsePayment(raced as PaymentRow));
      return json({ error: 'QR pembayaran belum dapat disiapkan.' }, 503, req);
    }
    payment = inserted;
  } else if (payment.status === 'FAILED' && input.action === 'create') {
    const { data: retried, error: retryError } = await admin.from('gdc_qris_mpm_payments').update({ status: 'CREATING', error_code: null, updated_at: new Date().toISOString() })
      .eq('order_id', order.id).eq('status', 'FAILED').select('*').maybeSingle();
    if (retryError || !retried) return json({ error: 'QR pembayaran sedang diproses. Coba lagi sebentar.' }, 409, req);
    payment = retried;
  } else if (payment.status === 'CREATING') {
    return json({ error: 'QR pembayaran sedang dibuat. Coba lagi sebentar.' }, 409, req);
  }
  if (input.action === 'create') {
    try {
      const requestBody = {
        partnerReferenceNo: payment.partner_reference_no,
        amount: { value: moneyValue(amount), currency: 'IDR' },
        merchantId: String(application.gdc_merchant_id),
        additionalInfo: { accountNumber: String(application.gdc_account_number) },
      };
      const generated = await gdcPost(credentials, API_PATHS.generate, requestBody, payment.external_id);
      if (generated.responseCode !== '2004700' || generated.partnerReferenceNo !== payment.partner_reference_no || !generated.referenceNo || !generated.qrContent || generated.qrContent.length > 4000) {
        throw new Error('Provider mengembalikan data QR yang tidak lengkap.');
      }
      const { data: saved, error: saveError } = await admin.from('gdc_qris_mpm_payments').update({
        reference_no: generated.referenceNo,
        qr_content: generated.qrContent,
        status: 'PENDING',
        provider_response_code: generated.responseCode,
        updated_at: new Date().toISOString(),
      }).eq('order_id', order.id).eq('status', 'CREATING').select('*').single();
      if (saveError || !saved) throw new Error('QR pembayaran belum dapat disimpan.');
      const { error: markError } = await admin.from('orders').update({ payment_channel: 'QRIS_MPM_GDC' })
        .eq('id', order.id).eq('buyer_id', authData.user.id);
      if (markError) throw new Error('Metode pembayaran QRIS belum dapat disiapkan.');
      return json(responsePayment(saved as PaymentRow), 200, req);
    } catch (error) {
      await admin.from('gdc_qris_mpm_payments').update({ status: 'FAILED', error_code: 'QR_CREATE_FAILED', updated_at: new Date().toISOString() }).eq('order_id', order.id).eq('status', 'CREATING');
      console.error('GDC QR MPM create failed', error instanceof Error ? error.message : 'unknown');
      return json({ error: error instanceof Error ? error.message : 'QR pembayaran gagal dibuat.' }, 502, req);
    }
  }
  const existingPayment = payment as PaymentRow;
  if (!existingPayment.reference_no || !existingPayment.qr_content) return json({ error: 'QR pembayaran belum tersedia.' }, 409, req);
  const throttleKey = `${authData.user.id}:${order.id}`;
  const lastQuery = queryThrottle.get(throttleKey) || 0;
  if (Date.now() - lastQuery < 4000) return json(responsePayment(existingPayment), 200, req);
  queryThrottle.set(throttleKey, Date.now());
  try {
    const queryBody = {
      originalReferenceNo: existingPayment.reference_no,
      originalPartnerReferenceNo: existingPayment.partner_reference_no,
      originalExternalId: existingPayment.external_id,
      serviceCode: '47',
      additionalInfo: {},
    };
    const queried = await gdcPost(credentials, API_PATHS.query, queryBody);
    if (queried.responseCode !== '2005100'
      || queried.originalReferenceNo !== existingPayment.reference_no
      || queried.originalPartnerReferenceNo !== existingPayment.partner_reference_no
      || queried.originalExternalId !== existingPayment.external_id
      || queried.serviceCode !== '47') {
      throw new Error('Respons status pembayaran GDC tidak cocok dengan order.');
    }
    if (queried.latestTransactionStatus === '00') {
      const paidAmount = parseAmount(queried.amount?.value);
      if (queried.amount?.currency !== 'IDR' || paidAmount !== amount) {
        console.error('GDC payment amount mismatch', { orderId: order.id, hasAmount: paidAmount !== null });
        return json({ error: 'Nominal pembayaran tidak cocok. Status memerlukan pemeriksaan admin.' }, 409, req);
      }
      const { data: settled, error: settleError } = await admin.rpc('settle_gdc_qris_mpm_payment', {
        p_order_id: order.id,
        p_partner_reference_no: existingPayment.partner_reference_no,
        p_reference_no: existingPayment.reference_no,
        p_paid_amount: paidAmount,
        p_paid_at: queried.paidTime || null,
      });
      if (settleError) {
        console.error('GDC payment settlement failed', { code: settleError.code || null, orderId: order.id });
        return json({ error: 'Pembayaran terdeteksi tetapi belum dapat direkonsiliasi. Hubungi admin.' }, 503, req);
      }
      const { data: refreshed } = await admin.from('gdc_qris_mpm_payments').select('*').eq('order_id', order.id).maybeSingle();
      const paidPayment = refreshed || { ...existingPayment, status: 'PAID' as const, paid_at: queried.paidTime || new Date().toISOString() };
      return json(responsePayment(paidPayment as PaymentRow), 200, req);
    }
    if (queried.latestTransactionStatus === '06') {
      const { data: failed } = await admin.from('gdc_qris_mpm_payments').update({ status: 'FAILED', provider_response_code: queried.latestTransactionStatus, updated_at: new Date().toISOString() })
        .eq('order_id', order.id).eq('status', 'PENDING').select('*').maybeSingle();
      return json(responsePayment((failed || existingPayment) as PaymentRow), 200, req);
    }
    if (deadlinePassed) {
      const { data: expired } = await admin.from('gdc_qris_mpm_payments').update({ status: 'EXPIRED', error_code: 'PAYMENT_DEADLINE_EXPIRED', updated_at: new Date().toISOString() }).eq('order_id', order.id).eq('status', 'PENDING').select('*').maybeSingle();
      return json(responsePayment((expired || existingPayment) as PaymentRow), 200, req);
    }
    return json(responsePayment(existingPayment), 200, req);
  } catch (error) {
    console.error('GDC QR MPM status query failed', error instanceof Error ? error.message : 'unknown');
    return json({ error: error instanceof Error ? error.message : 'Status pembayaran belum dapat diperiksa.' }, 502, req);
  }
}

serve(async (req) => {
  try {
    return await processRequest(req);
  } catch (error) {
    console.error('GDC QR MPM handler failed', error instanceof Error ? error.message : 'unknown');
    return json({ error: error instanceof Error ? error.message : 'Layanan QRIS belum dikonfigurasi.' }, 503, req);
  }
});
