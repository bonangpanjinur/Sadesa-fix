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
