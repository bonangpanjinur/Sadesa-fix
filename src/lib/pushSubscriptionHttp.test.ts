import { describe, expect, it } from 'vitest';
import {
  getPushSubscriptionCorsHeaders,
  pushSubscriptionJsonResponse,
} from '../../supabase/functions/push-subscription/http';

const allowedOrigins = new Set(['https://www.sadesa.id', 'https://sadesa.id']);

describe('push-subscription HTTP responses', () => {
  it('reflects the allowed production origin on JSON responses, including server errors', async () => {
    const response = pushSubscriptionJsonResponse(
      'https://www.sadesa.id',
      allowedOrigins,
      { error: 'Internal server error', requestId: 'request-1' },
      500,
    );

    expect(response.status).toBe(500);
    expect(response.headers.get('Access-Control-Allow-Origin')).toBe('https://www.sadesa.id');
    expect(await response.json()).toEqual({
      error: 'Internal server error',
      requestId: 'request-1',
    });
  });

  it('does not reflect an untrusted origin and permits Supabase client headers', () => {
    const headers = getPushSubscriptionCorsHeaders('https://untrusted.example', allowedOrigins);

    expect(headers['Access-Control-Allow-Origin']).toBe('https://www.sadesa.id');
    expect(headers['Access-Control-Allow-Headers']).toContain('authorization');
    expect(headers['Access-Control-Allow-Headers']).toContain('x-supabase-client-runtime-version');
  });
});
