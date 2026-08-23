import { supabase } from '@/integrations/supabase/client';
import { reportObservability } from '@/lib/observability';

export interface CreatePaymentRequest {
  orderId: string;
}

export interface PaymentInvoice {
  success: boolean;
  invoice_id: string;
  invoice_url: string;
  expiry_date: string;
}

export interface PaymentStatus {
  success: boolean;
  status: 'PENDING' | 'PAID' | 'EXPIRED';
  paid_at?: string;
  payment_method?: string;
}

const API_BASE = '/api';

export async function createPaymentInvoice(request: CreatePaymentRequest): Promise<PaymentInvoice> {
  reportObservability('payment', 'invoice_create_started', 'info', { hasOrderId: Boolean(request.orderId) });
  const { data: { session } } = await supabase.auth.getSession();
  const response = await fetch(`${API_BASE}/xendit/create-invoice`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(session?.access_token ? { Authorization: `Bearer ${session.access_token}` } : {}),
    },
    body: JSON.stringify({ order_id: request.orderId }),
  });

  if (!response.ok) {
    const err = await response.json().catch(() => ({ error: 'Failed to create payment invoice' }));
    const message = err.error || 'Failed to create payment invoice';
    reportObservability('payment', 'invoice_create_failed', 'error', { status: response.status }, new Error(message));
    throw new Error(message);
  }

  reportObservability('payment', 'invoice_create_succeeded');
  return response.json();
}

export async function checkPaymentStatus(invoiceId: string): Promise<PaymentStatus> {
  reportObservability('payment', 'status_check_started', 'info', { hasInvoiceId: Boolean(invoiceId) });
  const { data: { session } } = await supabase.auth.getSession();
  const response = await fetch(`${API_BASE}/xendit/check-status?invoice_id=${encodeURIComponent(invoiceId)}`, {
    headers: session?.access_token ? { Authorization: `Bearer ${session.access_token}` } : {},
  });

  if (!response.ok) {
    const error = new Error('Failed to check payment status');
    reportObservability('payment', 'status_check_failed', 'error', { status: response.status }, error);
    throw error;
  }

  reportObservability('payment', 'status_check_succeeded');
  return response.json();
}

export async function isXenditEnabled(): Promise<boolean> {
  const { data, error } = await supabase
    .from('app_settings')
    .select('value')
    .eq('key', 'payment_xendit')
    .maybeSingle();

  if (error || !data) {
    return false;
  }

  const settings = data.value as { enabled?: boolean };
  return settings.enabled ?? false;
}
