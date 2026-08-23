/**
 * Jembatan ke endpoint POS/QR lama (`/api/*`) yang dulu dilayani server Express.
 *
 * Server tersebut tidak lagi dijalankan dan tabel pendukungnya (pos_products,
 * pos_sales, pos_orders, pos_tables, sesi QR Pay) belum ada di database, jadi
 * setiap pemanggilan sengaja gagal dengan pesan yang jelas alih-alih HTTP 500
 * yang membingungkan pengguna.
 */
import { reportObservability } from '@/lib/observability';

export const POS_BRIDGE_UNAVAILABLE_MESSAGE =
  'Fitur POS/QR ini belum tersedia karena layanan POS belum aktif. Hubungi admin untuk mengaktifkannya.';

export class PosBridgeUnavailableError extends Error {
  constructor(path: string) {
    super(POS_BRIDGE_UNAVAILABLE_MESSAGE);
    this.name = 'PosBridgeUnavailableError';
    reportObservability('pos_webhook', 'bridge_unavailable', 'warn', { path: path.split('?')[0] });
    console.warn(`[pos-bridge] endpoint tidak tersedia: ${path.split('?')[0]}`);
  }
}

/** Drop-in pengganti `fetch()` untuk endpoint POS/QR lama. */
export async function posBridgeFetch(path: string, _init?: RequestInit): Promise<Response> {
  throw new PosBridgeUnavailableError(path);
}
