import { afterEach, describe, expect, it, vi } from 'vitest';

const { callGoogleMapsFunction } = vi.hoisted(() => ({
  callGoogleMapsFunction: vi.fn(),
}));

vi.mock('@/lib/maps/googleMapsApi', () => ({ callGoogleMapsFunction }));

import {
  getDeliveryDistanceKm,
  getGoogleRoadRoute,
  haversineDistanceKm,
  isValidRoutePoint,
} from './routeCalculation';

afterEach(() => {
  vi.unstubAllGlobals();
  vi.clearAllMocks();
});

describe('Google Maps route adapter', () => {
  it('validates coordinates and computes the straight-line distance', () => {
    expect(isValidRoutePoint({ lat: -7.3, lng: 108.2 })).toBe(true);
    expect(isValidRoutePoint({ lat: 91, lng: 108.2 })).toBe(false);
    expect(haversineDistanceKm({ lat: 0, lng: 0 }, { lat: 0, lng: 1 })).toBeCloseTo(111.2, 0);
  });

  it('returns normalized Google route points and caches the result briefly', async () => {
    const from = { lat: -7.31111, lng: 108.21111 };
    const to = { lat: -7.32222, lng: 108.22222 };
    const route = {
      distanceKm: 3.4,
      durationMinutes: 12,
      geometry: [from, to],
      provider: 'google' as const,
    };
    callGoogleMapsFunction.mockResolvedValue(route);

    await expect(getGoogleRoadRoute(from, to)).resolves.toEqual(route);
    await expect(getGoogleRoadRoute(from, to)).resolves.toEqual(route);
    expect(callGoogleMapsFunction).toHaveBeenCalledTimes(1);
    expect(callGoogleMapsFunction).toHaveBeenCalledWith({
      action: 'route',
      origin: from,
      destination: to,
    }, undefined);
  });

  it('uses the road fallback when the Google server route is unavailable', async () => {
    const from = { lat: -7.33111, lng: 108.23111 };
    const to = { lat: -7.34222, lng: 108.24222 };
    callGoogleMapsFunction.mockRejectedValue(new Error('edge unavailable'));
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify({
      code: 'Ok',
      routes: [{
        distance: 8_500,
        duration: 900,
        geometry: { coordinates: [[108.23111, -7.33111], [108.24222, -7.34222]] },
      }],
    }), { status: 200, headers: { 'Content-Type': 'application/json' } })));

    await expect(getDeliveryDistanceKm(from, to)).resolves.toEqual({
      distanceKm: 8.5,
      source: 'fallback',
    });
  });

  it('uses straight-line distance when both route providers are unavailable', async () => {
    const from = { lat: -7.35111, lng: 108.25111 };
    const to = { lat: -7.36222, lng: 108.26222 };
    callGoogleMapsFunction.mockRejectedValue(new Error('edge unavailable'));
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('network unavailable')));

    const result = await getDeliveryDistanceKm(from, to);
    expect(result.source).toBe('straight-line');
    expect(result.distanceKm).toBeGreaterThan(0);
  });

  it('does not start a fallback route after cancellation', async () => {
    const controller = new AbortController();
    const from = { lat: -7.37111, lng: 108.27111 };
    const to = { lat: -7.38222, lng: 108.28222 };
    callGoogleMapsFunction.mockRejectedValue(new DOMException('Aborted', 'AbortError'));
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);

    await expect(getDeliveryDistanceKm(from, to, controller.signal)).rejects.toMatchObject({ name: 'AbortError' });
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
