import { afterEach, describe, expect, it, vi } from 'vitest';
import { fetchVillages } from './addressApi';

function jsonResponse(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

describe('addressApi EMSIFA v2', () => {
  afterEach(() => {
    vi.restoreAllMocks();
    localStorage.clear();
  });

  it('ignores legacy v1 codes and uses the complete v2 village list', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(jsonResponse([
        { code: '3206132001', name: 'TARAJU' },
        { code: '3206132002', name: 'CIKUBANG' },
      ]))
      .mockResolvedValueOnce(jsonResponse({
        data: [
          { id: '32.06.13.2001', name: 'Taraju' },
          { id: '32.06.13.2002', name: 'Cikubang' },
          { id: '32.06.13.2003', name: 'Deudeul' },
        ],
        meta: { level: 4 },
      }));

    const villages = await fetchVillages('32.06.13');

    expect(villages).toContainEqual({ code: '32.06.13.2003', name: 'Deudeul' });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(String(fetchMock.mock.calls[1][0])).toContain('/v2/villages/32.06.13.json');
  });
});
