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

async function requestPayment(action: 'create' | 'status', orderId: string): Promise<GdcQrisMpmPayment> {
  const { data, error } = await supabase.functions.invoke('gdc-qris-mpm', {
    body: { action, order_id: orderId },
  });
  if (error) throw new Error(error.message || 'Layanan QRIS dinamis tidak tersedia.');
  if (!data || typeof data !== 'object' || !('status' in data)) {
    throw new Error('Respons pembayaran QRIS tidak valid.');
  }
  if (typeof data.error === 'string') throw new Error(data.error);
  return data as GdcQrisMpmPayment;
}

export function createOrGetGdcQrisMpm(orderId: string): Promise<GdcQrisMpmPayment> {
  return requestPayment('create', orderId);
}

export function queryGdcQrisMpmStatus(orderId: string): Promise<GdcQrisMpmPayment> {
  return requestPayment('status', orderId);
}
