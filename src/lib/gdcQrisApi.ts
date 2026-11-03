import { supabase, SUPABASE_URL } from '@/integrations/supabase/client';
import { observe } from '@/lib/observability';

export type GdcQrisStatus = 'CREATING' | 'PENDING' | 'SUCCEEDED' | 'FAILED' | 'EXPIRED' | 'UNKNOWN';
export interface GdcQrisAttempt {
  id: string;
  order_id: string;
  merchant_id: string;
  amount: number;
  currency: 'IDR';
  partner_reference_no: string;
  provider_reference_no: string | null;
  status: GdcQrisStatus;
  qr_content: string | null;
  qr_url: string | null;
  qr_image: string | null;
  expires_at: string | null;
}

const API_BASE = `${SUPABASE_URL}/functions/v1/gdc-qris-payment`;

async function authHeaders(idempotencyKey?: string) {
  const { data: { session } } = await supabase.auth.getSession();
  return {
    'Content-Type': 'application/json',
    ...(idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {}),
    ...(session?.access_token ? { Authorization: `Bearer ${session.access_token}` } : {}),
  };
}

async function parseResponse<T>(response: Response): Promise<T> {
  const body = await response.json().catch(() => ({ error: 'GDC payment request failed' }));
  if (!response.ok) throw new Error(body.error || 'GDC payment request failed');
  return body as T;
}

export async function createGdcQrisPayment(orderId: string, idempotencyKey?: string): Promise<{ success: boolean; attempt: GdcQrisAttempt }> {
  return observe('payment', 'gdc_generate', async () => {
    const response = await fetch(`${API_BASE}/generate`, {
      method: 'POST',
      headers: await authHeaders(idempotencyKey || `gdc-qris:${orderId}`),
      body: JSON.stringify({ order_id: orderId }),
    });
    return parseResponse(response);
  }, { provider: 'GDC', operation: 'generate' });
}

export async function queryGdcQrisPayment(attemptId: string): Promise<{ success: boolean; attempt: GdcQrisAttempt }> {
  return observe('payment', 'gdc_query', async () => {
    const response = await fetch(`${API_BASE}/query`, {
      method: 'POST',
      headers: await authHeaders(),
      body: JSON.stringify({ attempt_id: attemptId }),
    });
    return parseResponse(response);
  }, { provider: 'GDC', operation: 'query' });
}
