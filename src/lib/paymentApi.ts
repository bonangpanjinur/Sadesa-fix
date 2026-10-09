import { supabase, SUPABASE_URL } from '@/integrations/supabase/client';
import { reportObservability } from '@/lib/observability';

export interface CreatePaymentRequest {
  orderId: string;
  idempotencyKey?: string;
}

export interface CreateWalletTopupInvoiceRequest {
  topupRequestId: string;
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

const API_BASE = `${SUPABASE_URL}/functions/v1/xendit-payment`;

export function getPaymentIdempotencyKey(orderId: string, suppliedKey?: string): string {
  return suppliedKey?.trim() || `payment-invoice:${orderId}`;
}

export async function createPaymentInvoice(request: CreatePaymentRequest): Promise<PaymentInvoice> {
  reportObservability('payment', 'invoice_create_started', 'info', { hasOrderId: Boolean(request.orderId) });
  const { data: { session } } = await supabase.auth.getSession();
  const idempotencyKey = getPaymentIdempotencyKey(request.orderId, request.idempotencyKey);
  const response = await fetch(`${API_BASE}/create-invoice`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Idempotency-Key': idempotencyKey,
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
  const response = await fetch(`${API_BASE}/check-status?invoice_id=${encodeURIComponent(invoiceId)}`, {
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

export async function createWalletTopupInvoice(request: CreateWalletTopupInvoiceRequest): Promise<PaymentInvoice> {
  const { data: { session } } = await supabase.auth.getSession();
  const response = await fetch(`${API_BASE}/create-wallet-topup-invoice`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(session?.access_token ? { Authorization: `Bearer ${session.access_token}` } : {}),
    },
    body: JSON.stringify({ topup_request_id: request.topupRequestId }),
  });
  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: 'Gagal membuat invoice top-up' }));
    throw new Error(error.error || 'Gagal membuat invoice top-up');
  }
  return response.json();
}

export async function isXenditEnabled(): Promise<boolean> {
  const { data, error } = await supabase.rpc('is_payment_provider_enabled', {
    p_provider: 'xendit',
  });
  return error ? false : data === true;
}
