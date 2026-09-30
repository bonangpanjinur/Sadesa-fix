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
  ON_DELIVERY: 'Dalam perjalanan',
  SENT: 'Siap diambil pembeli',
  DELIVERING: 'Sedang diantarkan',
  DELIVERED: 'Sudah sampai',
  DONE: 'Selesai',
  CANCELED: 'Dibatalkan',
  REJECTED: 'Ditolak toko',
  REJECTED_BY_BUYER: 'Dibatalkan pembeli',
  CANCELLED: 'Dibatalkan',
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

export const ORDER_STATUS_GROUPS = {
  pending: ['NEW', 'PENDING_PAYMENT', 'PENDING_CONFIRMATION'],
  processing: ['PROCESSED', 'READY', 'ASSIGNED', 'COURIER_ASSIGNED', 'COURIER_ACCEPTED', 'PICKED_UP'],
  shipping: ['SENT', 'DELIVERING', 'ON_DELIVERY', 'DELIVERED'],
  completed: ['DONE'],
  canceled: ['CANCELED', 'CANCELLED', 'REJECTED', 'REJECTED_BY_BUYER', 'REFUNDED'],
} as const;

export const ORDER_STATUS_GROUP_LABELS: Record<keyof typeof ORDER_STATUS_GROUPS, string> = {
  pending: 'Menunggu',
  processing: 'Diproses',
  shipping: 'Pengiriman',
  completed: 'Selesai',
  canceled: 'Dibatalkan',
};

export function getOrderStatusGroup(status: string | null | undefined) {
  if (!status) return 'all' as const;
  for (const [group, statuses] of Object.entries(ORDER_STATUS_GROUPS)) {
    if ((statuses as readonly string[]).includes(status)) return group;
  }
  return 'all' as const;
}

export function isTerminalOrderStatus(status: string | null | undefined) {
  return getOrderStatusGroup(status) === 'completed' || getOrderStatusGroup(status) === 'canceled';
}

export function canBuyerCancelOrder(status: string | null | undefined) {
  return BUYER_CANCELLABLE_STATUSES.includes(status as (typeof BUYER_CANCELLABLE_STATUSES)[number]);
}

export function canUseOnlinePaymentForMerchantCount(merchantCount: number) {
  return Number.isInteger(merchantCount) && merchantCount === 1;
}

export function orderStatusLabel(status: string | null | undefined) {
  return ORDER_STATUS_LABELS[status || ''] || status || 'Belum diketahui';
}

export const MERCHANT_ORDER_STATUS_FILTER_OPTIONS = Object.entries(ORDER_STATUS_GROUPS)
  .flatMap(([group, statuses]) => (statuses as readonly string[]).map((status) => ({
    value: status,
    label: `${ORDER_STATUS_GROUP_LABELS[group as keyof typeof ORDER_STATUS_GROUPS]} · ${orderStatusLabel(status)}`,
  })));
