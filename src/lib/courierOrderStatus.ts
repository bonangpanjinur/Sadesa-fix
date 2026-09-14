export type DeliveryStatus = 'ASSIGNED' | 'COURIER_ACCEPTED' | 'PICKED_UP' | 'SENT' | 'DELIVERING' | 'DELIVERED';
export type RideStatus = 'SEARCHING' | 'ACCEPTED' | 'PICKED_UP' | 'IN_TRANSIT' | 'COMPLETED';

export const DELIVERY_STATUS_LABEL: Record<string, string> = {
  ASSIGNED: 'Ditugaskan', COURIER_ACCEPTED: 'Menuju toko', PICKED_UP: 'Diambil',
  SENT: 'Dalam perjalanan', DELIVERING: 'Dalam perjalanan', DELIVERED: 'Selesai',
};

export const DELIVERY_NEXT_STATUS: Record<string, { label: string; nextStatus: DeliveryStatus }> = {
  COURIER_ACCEPTED: { label: 'Ambil pesanan', nextStatus: 'PICKED_UP' },
  PICKED_UP: { label: 'Mulai antar', nextStatus: 'SENT' },
  SENT: { label: 'Selesaikan', nextStatus: 'DELIVERED' },
  DELIVERING: { label: 'Selesaikan', nextStatus: 'DELIVERED' },
};

export const RIDE_STATUS_LABEL: Record<string, string> = {
  SEARCHING: 'Mencari driver', ACCEPTED: 'Menuju penjemputan', PICKED_UP: 'Penumpang dijemput',
  IN_TRANSIT: 'Dalam perjalanan', COMPLETED: 'Selesai',
};

export function getRpcErrorMessage(error: unknown, fallback = 'Silakan coba lagi.') {
  const message = error instanceof Error ? error.message : String((error as { message?: string })?.message || '');
  const normalized = message.toLowerCase();
  if (normalized.includes('no longer active') || normalized.includes('expired')) return 'Tawaran sudah kedaluwarsa. Daftar akan diperbarui.';
  if (normalized.includes('already') || normalized.includes('assigned')) return 'Pesanan sudah diambil atau ditugaskan ke driver lain.';
  if (normalized.includes('offline') || normalized.includes('available')) return 'Anda sedang offline. Aktifkan status online terlebih dahulu.';
  if (normalized.includes('reason')) return 'Alasan wajib diisi.';
  return message || fallback;
}

export function formatRemainingTime(expiresAt: string, now = Date.now()) {
  const seconds = Math.max(0, Math.ceil((new Date(expiresAt).getTime() - now) / 1000));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}
