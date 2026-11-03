import { supabase } from '@/integrations/supabase/client';

export interface GdcQrisMpmPayment {
  order_id: string;
  status: 'PENDING' | 'PAID' | 'FAILED';
  amount: number;
  currency: 'IDR';
  qr_content: string | null;
  reference_no: string | null;
  paid_at: string | null;
  reconciliation_required?: boolean;
}

function isValidPayment(data: unknown, expectedOrderId: string): data is GdcQrisMpmPayment {
  if (!data || typeof data !== 'object') return false;
  const value = data as Partial<GdcQrisMpmPayment>;
  if (value.order_id !== expectedOrderId || !['PENDING', 'PAID', 'FAILED'].includes(String(value.status))) return false;
  if (typeof value.amount !== 'number' || !Number.isSafeInteger(value.amount) || value.amount <= 0) return false;
  if (value.currency !== 'IDR') return false;
  if (value.status === 'PENDING' && (typeof value.qr_content !== 'string' || !value.qr_content.trim())) return false;
  if (value.status !== 'PENDING' && value.reference_no !== null && typeof value.reference_no !== 'string') return false;
  if (value.status === 'PAID' && (typeof value.reference_no !== 'string' || !value.reference_no || typeof value.paid_at !== 'string' || Number.isNaN(Date.parse(value.paid_at)))) return false;
  return true;
}

async function requestPayment(action: 'create' | 'status', orderId: string): Promise<GdcQrisMpmPayment> {
  const { data, error } = await supabase.functions.invoke('gdc-qris-mpm', {
    body: { action, order_id: orderId },
  });
  if (error) throw new Error(error.message || 'Layanan QRIS dinamis tidak tersedia.');
  if (data && typeof data === 'object' && typeof data.error === 'string') throw new Error(data.error);
  if (!isValidPayment(data, orderId)) {
    throw new Error('Respons pembayaran QRIS tidak valid.');
  }
  return data as GdcQrisMpmPayment;
}

export async function isGdcQrisMpmAvailable(merchantId: string): Promise<boolean> {
  const { data, error } = await supabase.functions.invoke('gdc-qris-mpm', {
    body: { action: 'availability', merchant_id: merchantId },
  });
  if (error) throw new Error(error.message || 'Ketersediaan QRIS MPM tidak dapat diperiksa.');
  if (!data || typeof data !== 'object' || typeof data.available !== 'boolean') {
    throw new Error('Respons ketersediaan QRIS MPM tidak valid.');
  }
  return data.available;
}

export function createOrGetGdcQrisMpm(orderId: string): Promise<GdcQrisMpmPayment> {
  return requestPayment('create', orderId);
}

export function queryGdcQrisMpmStatus(orderId: string): Promise<GdcQrisMpmPayment> {
  return requestPayment('status', orderId);
}
