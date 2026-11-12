import { supabase } from "@/integrations/supabase/client";

export interface CreateGdcPaymentRequest {
  orderId: string;
}

export interface GdcPaymentResponse {
  success: boolean;
  referenceNo: string;
  partnerReferenceNo: string;
  qrContent: string;
}

export interface GdcPaymentStatusResponse {
  success: boolean;
  status: "PENDING" | "PAID" | "EXPIRED" | "FAILED";
  referenceNo?: string;
  paidAt?: string;
}

export async function createGdcPayment(
  request: CreateGdcPaymentRequest,
): Promise<GdcPaymentResponse> {
  if (!request.orderId?.trim()) {
    throw new Error("Order ID wajib diisi");
  }

  const { data, error } = await supabase.functions.invoke("gdc-payment", {
    body: {
      order_id: request.orderId,
    },
  });

  if (error) {
    throw new Error(error.message || "Gagal membuat pembayaran GDC");
  }

  if (!data?.success) {
    throw new Error(data?.error || "Gagal membuat pembayaran GDC");
  }

  return {
    success: data.success,
    referenceNo: data.referenceNo,
    partnerReferenceNo: data.partnerReferenceNo,
    qrContent: data.qrContent,
  };
}

export async function checkGdcPaymentStatus(
  referenceNo: string,
): Promise<GdcPaymentStatusResponse> {
  if (!referenceNo.trim()) {
    throw new Error("Reference number wajib diisi");
  }

  const { data, error } = await supabase.functions.invoke("gdc-payment", {
    body: {
      action: "check-status",
      reference_no: referenceNo,
    },
  });

  if (error) {
    throw new Error(error.message || "Gagal memeriksa status pembayaran");
  }

  if (!data?.success) {
    throw new Error(data?.error || "Gagal memeriksa status pembayaran");
  }

  return data;
}
