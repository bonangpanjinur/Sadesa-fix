import { supabase } from '@/integrations/supabase/client';

export interface GdcQrisMpmPayment {
  order_id: string;
  status: 'PENDING' | 'PAID' | 'FAILED';
  amount: number;
  currency: 'IDR';
  qr_content: string | null;
  reference_no: string | null;
  paid_at: string | null;
}

export interface GdcQrisMpmPreview {
  status: 'PREVIEW';
  amount: 1000;
  currency: 'IDR';
  qr_content: string;
  reference_no: string;
}

async function previewFunctionErrorMessage(error: unknown): Promise<string> {
  const fallback = 'Layanan preview QRIS sandbox tidak tersedia.';
  if (!error || typeof error !== 'object') return fallback;
  const functionError = error as { message?: unknown; context?: unknown };
  const context = functionError.context;
  if (context instanceof Response) {
    try {
      const payload: unknown = await context.clone().json();
      if (payload && typeof payload === 'object') {
        const body = payload as Record<string, unknown>;
        if (typeof body.error === 'string' && body.error.trim()) return body.error;
        if (typeof body.message === 'string' && body.message.trim()) return body.message;
      }
    } catch {
      // Fall back to the Supabase function error when the response isn't JSON.
    }
  }
  return typeof functionError.message === 'string' && functionError.message.trim()
    ? functionError.message
    : fallback;
}

function parsePayment(value: unknown): GdcQrisMpmPayment {
  if (!value || typeof value !== 'object') throw new Error('Respons pembayaran QRIS tidak valid.');
  const payment = value as Record<string, unknown>;
  if (typeof payment.error === 'string') throw new Error(payment.error);
  if (typeof payment.order_id !== 'string'
    || !['PENDING', 'PAID', 'FAILED'].includes(String(payment.status))
    || typeof payment.amount !== 'number'
    || !Number.isFinite(payment.amount)
    || payment.currency !== 'IDR'
    || (payment.qr_content !== null && typeof payment.qr_content !== 'string')
    || (payment.reference_no !== null && typeof payment.reference_no !== 'string')
    || (payment.paid_at !== null && typeof payment.paid_at !== 'string')) {
    throw new Error('Respons pembayaran QRIS tidak valid.');
  }
  return payment as unknown as GdcQrisMpmPayment;
}

async function requestPayment(action: 'create' | 'status', orderId: string): Promise<GdcQrisMpmPayment> {
  const { data, error } = await supabase.functions.invoke('gdc-qris-mpm', {
    body: { action, order_id: orderId },
  });
  if (error) throw new Error(error.message || 'Layanan QRIS dinamis tidak tersedia.');
  return parsePayment(data);
}

export function createOrGetGdcQrisMpm(orderId: string): Promise<GdcQrisMpmPayment> {
  return requestPayment('create', orderId);
}

export function queryGdcQrisMpmStatus(orderId: string): Promise<GdcQrisMpmPayment> {
  return requestPayment('status', orderId);
}

export async function previewGdcQrisMpm(applicationId: string): Promise<GdcQrisMpmPreview> {
  const { data, error } = await supabase.functions.invoke('gdc-qris-mpm', {
    body: { action: 'admin_preview', application_id: applicationId },
  });
  if (error) throw new Error(await previewFunctionErrorMessage(error));
  if (!data || typeof data !== 'object') throw new Error('Respons QR uji GDC tidak valid.');
  const preview = data as Record<string, unknown>;
  if (typeof preview.error === 'string') throw new Error(preview.error);
  if (preview.status !== 'PREVIEW'
    || preview.amount !== 1000
    || preview.currency !== 'IDR'
    || typeof preview.qr_content !== 'string'
    || !preview.qr_content.trim()
    || typeof preview.reference_no !== 'string'
    || !preview.reference_no.trim()) {
    throw new Error('Respons QR uji GDC tidak valid.');
  }
  return preview as unknown as GdcQrisMpmPreview;
}
