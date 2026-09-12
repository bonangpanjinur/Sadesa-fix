export const ORDER_STATUS_LABELS: Record<string, string> = {
  NEW: 'Pesanan baru',
  PENDING_CONFIRMATION: 'Menunggu konfirmasi toko',
  PENDING_PAYMENT: 'Menunggu pembayaran',
  PROCESSED: 'Sedang disiapkan',
  READY: 'Siap dikirim/diambil',
  ASSIGNED: 'Menunggu kurir',
  COURIER_ASSIGNED: 'Kurir dipilih',
  COURIER_ACCEPTED: 'Kurir menuju toko',
  PICKED_UP: 'Sudah diambil kurir',
  SENT: 'Siap diambil pembeli',
  DELIVERING: 'Sedang diantarkan',
  DELIVERED: 'Sudah sampai',
  DONE: 'Selesai',
  CANCELED: 'Dibatalkan',
  REJECTED: 'Ditolak toko',
  REJECTED_BY_BUYER: 'Dibatalkan pembeli',
  REFUNDED: 'Dana dikembalikan',
};

export const ORDER_STATUS_FLOW = [
  'NEW',
  'PROCESSED',
  'READY',
  'COURIER_ACCEPTED',
  'PICKED_UP',
  'DELIVERING',
  'DELIVERED',
  'DONE',
] as const;

export const BUYER_CANCELLABLE_STATUSES = [
  'NEW',
  'PENDING_PAYMENT',
  'PENDING_CONFIRMATION',
] as const;

export function canBuyerCancelOrder(status: string | null | undefined) {
  return BUYER_CANCELLABLE_STATUSES.includes(status as (typeof BUYER_CANCELLABLE_STATUSES)[number]);
}

export function canUseOnlinePaymentForMerchantCount(merchantCount: number) {
  return Number.isInteger(merchantCount) && merchantCount === 1;
}

export function orderStatusLabel(status: string | null | undefined) {
  return ORDER_STATUS_LABELS[status || ''] || status || 'Belum diketahui';
}
