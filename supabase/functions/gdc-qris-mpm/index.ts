import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const API_BASE = (Deno.env.get("GDC_API_BASE_URL") || "https://neo-sandbox-api.gdc.co.id/snap").replace(/\/$/, "");
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
interface GdcCredentials {
  clientKey: string;
  clientSecret: string;
  privateKeyPem: string;
  partnerId: string;
  channelId: string;
  deviceId: string;
}
interface PaymentRow {
  order_id: string;
  merchant_id: string;
  partner_reference_no: string;
  external_id: string;
  reference_no: string | null;
  amount: number;
  currency: string;
  qr_content: string | null;
  status: 'CREATING' | 'PENDING' | 'PAID' | 'FAILED';
  paid_at: string | null;
}
interface GdcResponse {
  responseCode?: string;
  responseMessage?: string;
  accessToken?: string;
  expiresIn?: string;
  partnerReferenceNo?: string;
  referenceNo?: string;
  qrContent?: string;
  originalReferenceNo?: string;
  originalPartnerReferenceNo?: string;
  originalExternalId?: string;
  serviceCode?: string;
  latestTransactionStatus?: string;
  transactionStatusDesc?: string;
  paidTime?: string;
  amount?: { value?: string; currency?: string };
}
let tokenCache: { token: string; expiresAt: number } | null = null;

function json(data: unknown, status = 200, req?: Request): Response {
  const origin = req?.headers.get('origin');
  const allowedOrigin = origin === 'https://sadesa.id' || origin === 'https://www.sadesa.id' || origin?.startsWith('http://localhost:')
    ? origin
    : 'https://sadesa.id';
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Access-Control-Allow-Origin': allowedOrigin, 'Content-Type': 'application/json' },
  });
}
function getCredentials(): GdcCredentials {
  const clientKey = Deno.env.get('GDC_CLIENT_KEY') || '';
  const clientSecret = Deno.env.get('GDC_CLIENT_SECRET') || '';
  const privateKeyPem = Deno.env.get('GDC_PRIVATE_KEY_PEM') || '';
  const partnerId = Deno.env.get('GDC_PARTNER_ID') || '';
  const channelId = Deno.env.get('GDC_CHANNEL_ID') || '';
  const deviceId = Deno.env.get('GDC_DEVICE_ID') || '';
  if (!clientKey || !clientSecret || !privateKeyPem || !partnerId || !channelId || !deviceId) {
    throw new Error('Konfigurasi pembayaran GDC belum lengkap.');
  }
  if (!/^[0-9a-f-]{36}$/i.test(partnerId)) throw new Error('Konfigurasi partner GDC tidak valid.');
  if (!API_BASE.startsWith('https://')) throw new Error('Base URL GDC harus menggunakan HTTPS.');
  return { clientKey, clientSecret, privateKeyPem, partnerId, channelId, deviceId };
}
function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}
function pemBytes(pem: string): Uint8Array {
  const normalized = pem.replace(/\\n/g, '\n');
  const match = normalized.match(/-----BEGIN PRIVATE KEY-----([\s\S]+?)-----END PRIVATE KEY-----/);
  if (!match) throw new Error('Private key GDC harus berformat PKCS#8 PEM.');
  return base64ToBytes(match[1].replace(/\s/g, ''));
}
function toBase64(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
function toBase64Url(bytes: Uint8Array): string {
  return toBase64(bytes).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}
function timestamp(): string {
  return new Date().toISOString();
}
async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}
async function getAccessToken(credentials: GdcCredentials): Promise<string> {
  if (tokenCache && tokenCache.expiresAt > Date.now() + 30_000) return tokenCache.token;
  const requestTime = timestamp();
  const privateKeyBytes = pemBytes(credentials.privateKeyPem);
  const privateKeyBuffer = new ArrayBuffer(privateKeyBytes.byteLength);
  new Uint8Array(privateKeyBuffer).set(privateKeyBytes);
  const key = await crypto.subtle.importKey(
    'pkcs8', privateKeyBuffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  );
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encoder.encode(`${credentials.clientKey}|${requestTime}`));
  const response = await fetch(`${API_BASE}${API_PATHS.token}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Timestamp': requestTime, 'Client-Key': credentials.clientKey, 'X-Signature': toBase64(new Uint8Array(signature)) },
    body: JSON.stringify({ grantType: 'client_credentials' }),
  });
  const body = await response.json().catch(() => ({})) as GdcResponse;
  if (!response.ok || body.responseCode !== '2007300' || !body.accessToken) {
    console.error('GDC access-token request failed', { status: response.status, responseCode: body.responseCode || null });
    throw new Error('Gagal menghubungkan ke layanan QRIS. Silakan coba lagi.');
  }
  const expiresSeconds = Math.max(60, Number(body.expiresIn || 900));
  tokenCache = { token: body.accessToken, expiresAt: Date.now() + expiresSeconds * 1000 };
  return body.accessToken;
}
async function signSnapRequest(credentials: GdcCredentials, token: string, path: string, body: Record<string, unknown>, externalId?: string): Promise<Record<string, string>> {
  const now = timestamp();
  const compactPayload = JSON.stringify(body);
  const payloadHash = await sha256Hex(compactPayload);
  const toSign = `POST:${path}:${token}:${payloadHash}:${now}`;
  const key = await crypto.subtle.importKey('raw', encoder.encode(credentials.clientSecret), { name: 'HMAC', hash: 'SHA-512' }, false, ['sign']);
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(toSign));
  return {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
    'X-TIMESTAMP': now,
    'X-PARTNER-ID': credentials.partnerId,
    'X-EXTERNAL-ID': externalId || crypto.randomUUID(),
    'X-DEVICE-ID': credentials.deviceId,
    'CHANNEL-ID': credentials.channelId,
    'X-Signature': toBase64(new Uint8Array(signature)),
  };
}
async function gdcPost(credentials: GdcCredentials, path: string, body: Record<string, unknown>, externalId?: string): Promise<GdcResponse> {
  const token = await getAccessToken(credentials);
  const headers = await signSnapRequest(credentials, token, path, body, externalId);
  const response = await fetch(`${API_BASE}${path}`, { method: 'POST', headers, body: JSON.stringify(body) });
  const data = await response.json().catch(() => ({})) as GdcResponse;
  if (!response.ok) {
    console.error('GDC transaction request failed', { path, status: response.status, responseCode: data.responseCode || null });
    throw new Error('Layanan QRIS belum dapat memproses pembayaran. Silakan coba lagi.');
  }
  return data;
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
async function processRequest(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') {
    const origin = req.headers.get('origin');
    const allowedOrigin = origin === 'https://sadesa.id' || origin === 'https://www.sadesa.id' || origin?.startsWith('http://localhost:')
      ? origin
      : 'https://sadesa.id';
    return new Response(null, { status: 204, headers: { ...corsHeaders, 'Access-Control-Allow-Origin': allowedOrigin } });
  }
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405, req);
  const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') || '';
  const authHeader = req.headers.get('authorization') || '';
  if (!supabaseUrl || !serviceRoleKey || !anonKey || !authHeader.startsWith('Bearer ')) return json({ error: 'Unauthorized' }, 401, req);
  const userClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authHeader } },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) return json({ error: 'Unauthorized' }, 401, req);
  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const input = await req.json().catch(() => null) as { action?: string; order_id?: string; merchant_id?: string } | null;
  if (!input || !['create', 'status', 'availability'].includes(input.action || '')) {
    return json({ error: 'Permintaan pembayaran tidak valid.' }, 400, req);
  }
  if (input.action === 'availability') {
    if (!input.merchant_id || !/^[0-9a-f-]{36}$/i.test(input.merchant_id)) {
      return json({ error: 'Merchant tidak valid.' }, 400, req);
    }
    const { data: application, error } = await admin.from('qris_applications')
      .select('gdc_merchant_id, gdc_account_number')
      .eq('merchant_id', input.merchant_id)
      .eq('status', 'ACTIVE')
      .order('activated_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error) {
      console.error('GDC QR MPM availability check failed', error.message);
      return json({ error: 'Ketersediaan QRIS MPM tidak dapat diperiksa.' }, 503, req);
    }
    return json({ available: Boolean(application?.gdc_merchant_id?.trim() && application?.gdc_account_number?.trim()) }, 200, req);
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
  if (input.action === 'create' && order.confirmation_deadline && new Date(order.confirmation_deadline).getTime() <= Date.now()) return json({ error: 'Batas pembayaran pesanan telah berakhir.' }, 409, req);
  const { data: application, error: applicationError } = await admin.from('qris_applications')
    .select('gdc_merchant_id, gdc_account_number, qris_merchant_name')
    .eq('merchant_id', order.merchant_id).eq('status', 'ACTIVE')
    .order('activated_at', { ascending: false }).limit(1).maybeSingle();
  if (applicationError || !application?.gdc_merchant_id || !application?.gdc_account_number) {
    return json({ error: 'QRIS MPM merchant belum aktif atau data akun GDC belum lengkap. Hubungi merchant.' }, 409, req);
  }
  const amount = Number(order.total);
  if (!Number.isSafeInteger(amount) || amount <= 0) return json({ error: 'Nominal pesanan tidak valid.' }, 409, req);
  if (input.action === 'create') {
    const { error: markError } = await admin.from('orders').update({ payment_channel: 'QRIS_MPM_GDC' })
      .eq('id', order.id).eq('buyer_id', authData.user.id);
    if (markError) return json({ error: 'Metode pembayaran QRIS belum dapat disiapkan.' }, 503, req);
  }
  const { data: existingPayment, error: paymentError } = await admin.from('gdc_qris_mpm_payments').select('*').eq('order_id', order.id).maybeSingle();
  if (paymentError) return json({ error: 'Data pembayaran tidak dapat dimuat.' }, 503, req);
  let payment = existingPayment;
  if (payment?.status === 'PENDING' || payment?.status === 'PAID') return json(responsePayment(payment as PaymentRow));
  if (payment?.status === 'FAILED' && input.action === 'create' && payment.error_code !== 'QR_CREATE_FAILED') {
    return json({ error: 'Pembayaran ini sudah dinyatakan gagal oleh provider. Hubungi merchant untuk instruksi berikutnya.' }, 409, req);
  }
  if (input.action === 'status' && !payment) return json({ error: 'QRIS pembayaran belum dibuat.' }, 404, req);
  if (!payment) {
    const { data: inserted, error: insertError } = await admin.from('gdc_qris_mpm_payments').insert({
      order_id: order.id,
      merchant_id: order.merchant_id,
      amount,
      currency: 'IDR',
      partner_reference_no: order.id,
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
      return json(responsePayment(saved as PaymentRow), 200, req);
    } catch (error) {
      await admin.from('gdc_qris_mpm_payments').update({ status: 'FAILED', error_code: 'QR_CREATE_FAILED', updated_at: new Date().toISOString() }).eq('order_id', order.id).eq('status', 'CREATING');
      console.error('GDC QR MPM create failed', error instanceof Error ? error.message : 'unknown');
      return json({ error: error instanceof Error ? error.message : 'QR pembayaran gagal dibuat.' }, 502, req);
    }
  }
  const existingPayment = payment as PaymentRow;
  if (!existingPayment.reference_no || !existingPayment.qr_content) return json({ error: 'QR pembayaran belum tersedia.' }, 409, req);
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
