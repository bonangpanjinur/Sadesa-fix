import { afterEach, describe, expect, it, vi } from 'vitest';

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('Nominatim request handling', () => {
  it('deduplicates concurrent forward-geocoding requests for the same address', async () => {
    vi.resetModules();
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify([
      { lat: '-7.31', lon: '108.21', display_name: 'Raksasari, Indonesia' },
    ]), { status: 200, headers: { 'Content-Type': 'application/json' } }));
    vi.stubGlobal('fetch', fetchMock);
    const { geocodeAddress } = await import('./useGeocoding');

    const results = await Promise.all([
      geocodeAddress('Taraju', 'Raksasari', 'Tasikmalaya', 'Jawa Barat'),
      geocodeAddress('Taraju', 'Raksasari', 'Tasikmalaya', 'Jawa Barat'),
    ]);

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(results[0]).toEqual({ lat: -7.31, lng: 108.21, displayName: 'Raksasari, Indonesia' });
    expect(results[1]).toEqual(results[0]);
  });

  it('returns a soft miss and backs off when the browser reports a rate-limit/CORS network failure', async () => {
    vi.resetModules();
    const fetchMock = vi.fn().mockRejectedValue(new TypeError('Failed to fetch'));
    vi.stubGlobal('fetch', fetchMock);
    vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    const { geocodeAddress } = await import('./useGeocoding');

    const result = await geocodeAddress('Taraju', 'Raksasari', 'Tasikmalaya', 'Jawa Barat');

    expect(result).toBeNull();
    // The fallback query must not turn one blocked request into another request.
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});
