import { beforeEach, describe, expect, it, vi } from 'vitest';
import { printBridgeClient, PRINT_BRIDGE_URL } from './printBridgeClient';

type MockResponse = {
  ok: boolean;
  status: number;
  json: () => Promise<unknown>;
};

const response = (payload: unknown, ok = true, status = 200): MockResponse => ({
  ok,
  status,
  json: async () => payload,
});

describe('printBridgeClient', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('loads health and configured printers through status()', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(response({ ok: true, service: 'sadesa-pos-print-bridge', version: '0.1.0', queue: 0, time: '2026-09-04T00:00:00.000Z' }))
      .mockResolvedValueOnce(response({ printers: [{ id: 'usb-1', name: 'Printer USB', type: 'serial' }] }));
    vi.stubGlobal('fetch', fetchMock);

    const result = await printBridgeClient.status();

    expect(result.health.ok).toBe(true);
    expect(result.printers).toHaveLength(1);
    expect(fetchMock).toHaveBeenNthCalledWith(1, `${PRINT_BRIDGE_URL}/health`, expect.any(Object));
    expect(fetchMock).toHaveBeenNthCalledWith(2, `${PRINT_BRIDGE_URL}/printers`, expect.any(Object));
  });

  it('replaces browser “Failed to fetch” with an actionable bridge message', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('Failed to fetch')));

    await expect(printBridgeClient.health()).rejects.toThrow(
      `Print Bridge tidak dapat diakses di ${PRINT_BRIDGE_URL}. Jalankan service Print Bridge di komputer kasir, lalu coba lagi.`,
    );
  });

  it('reports a timed-out bridge separately', async () => {
    const timeout = new DOMException('The operation timed out', 'TimeoutError');
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(timeout));

    await expect(printBridgeClient.health()).rejects.toThrow(
      `Print Bridge tidak merespons dalam 2,5 detik (${PRINT_BRIDGE_URL}). Pastikan servicenya aktif.`,
    );
  });

  it('surfaces JSON errors returned by the bridge', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(response({ error: 'Printer default belum dikonfigurasi' }, false, 503)));

    await expect(printBridgeClient.health()).rejects.toThrow('Printer default belum dikonfigurasi');
  });
});
