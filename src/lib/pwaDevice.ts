import { supabase } from '@/integrations/supabase/client';
import { createTraceId, observe, reportObservability } from '@/lib/observability';

export interface PwaDeviceSession {
  id: string;
  user_id: string;
  tenant_id: string | null;
  device_id: string;
  device_name: string;
  device_type: 'browser' | 'pwa' | 'kiosk';
  platform: string | null;
  ip_address: string | null;
  status: 'active' | 'idle' | 'revoked';
  last_seen_at: string;
  last_sync_at: string | null;
  revoked_at: string | null;
  created_at: string;
  updated_at: string;
}

const DEVICE_KEY = 'desamart:pwa-device-id';

function getDeviceId(): string {
  const existing = localStorage.getItem(DEVICE_KEY);
  if (existing) return existing;
  const id = createTraceId('device');
  localStorage.setItem(DEVICE_KEY, id);
  return id;
}

function getDeviceType(): 'browser' | 'pwa' | 'kiosk' {
  const standalone = window.matchMedia('(display-mode: standalone)').matches || (navigator as Navigator & { standalone?: boolean }).standalone === true;
  return standalone ? 'pwa' : 'browser';
}

/**
 * Reads the browser's public egress IP for audit correlation. This is not a
 * device identity and may be unavailable on VPNs, captive portals, or blocked
 * networks, so registration continues with a null value on failure.
 */
async function getPublicIpAddress(): Promise<string | null> {
  if (typeof AbortController === 'undefined') return null;
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), 2500);
  try {
    const response = await fetch('https://api.ipify.org?format=json', {
      signal: controller.signal,
      headers: { Accept: 'application/json' },
    });
    if (!response.ok) return null;
    const payload = await response.json() as { ip?: unknown };
    return typeof payload.ip === 'string' && payload.ip.trim() ? payload.ip.trim() : null;
  } catch {
    return null;
  } finally {
    window.clearTimeout(timeout);
  }
}

export async function registerPwaDevice(tenantId?: string | null): Promise<PwaDeviceSession | null> {
  const deviceId = getDeviceId();
  const context = { deviceType: getDeviceType(), hasTenant: Boolean(tenantId) };
  return observe('device', 'register', async () => {
    const ipAddress = await getPublicIpAddress();
    const { data, error } = await supabase.rpc('register_pwa_device' as never, {
      p_device_id: deviceId,
      p_device_name: `${getDeviceType() === 'pwa' ? 'PWA' : 'Browser'} ${navigator.platform || 'device'}`,
      p_device_type: getDeviceType(),
      p_platform: navigator.platform || null,
      p_user_agent: navigator.userAgent,
      p_ip_address: ipAddress,
      p_tenant_id: tenantId || null,
    } as never);
    if (error) throw error;
    return data as unknown as PwaDeviceSession;
  }, context);
}

export async function heartbeatPwaDevice(syncAt?: string | null): Promise<PwaDeviceSession | null> {
  if (typeof window === 'undefined') return null;
  try {
    const { data, error } = await supabase.rpc('heartbeat_pwa_device' as never, { p_device_id: getDeviceId(), p_sync_at: syncAt || null } as never);
    if (error) throw error;
    return data as unknown as PwaDeviceSession;
  } catch (error) {
    reportObservability('device', 'heartbeat_failed', 'warn', { hasSyncAt: Boolean(syncAt) }, error);
    return null;
  }
}

export function getLocalPwaDeviceId(): string {
  return getDeviceId();
}
