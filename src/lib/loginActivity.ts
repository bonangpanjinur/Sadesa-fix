import { supabase } from '@/integrations/supabase/client';
import { createTraceId } from '@/lib/observability';

const DEVICE_KEY = 'sadesa:login-device-id';

function getPlatform() {
  const navigatorWithUAData = navigator as Navigator & { userAgentData?: { platform?: string } };
  return navigatorWithUAData.userAgentData?.platform || navigator.platform || 'Perangkat';
}

function getLoginDeviceId() {
  const existing = window.localStorage.getItem(DEVICE_KEY);
  if (existing) return existing;
  const deviceId = createTraceId('login-device');
  window.localStorage.setItem(DEVICE_KEY, deviceId);
  return deviceId;
}

function getDeviceType(): 'browser' | 'pwa' {
  const standalone = window.matchMedia('(display-mode: standalone)').matches
    || (navigator as Navigator & { standalone?: boolean }).standalone === true;
  return standalone ? 'pwa' : 'browser';
}

function getDeviceName(deviceType: 'browser' | 'pwa') {
  const platform = getPlatform();
  return `${deviceType === 'pwa' ? 'PWA' : 'Browser'} · ${platform}`;
}

export async function recordAdminLoginActivity() {
  if (typeof window === 'undefined') return;
  const deviceType = getDeviceType();
  const { error } = await supabase.rpc('record_admin_login_activity' as never, {
    p_device_id: getLoginDeviceId(),
    p_device_name: getDeviceName(deviceType),
    p_device_type: deviceType,
    p_platform: getPlatform(),
    p_user_agent: navigator.userAgent,
  } as never);
  if (error) console.warn('Unable to record admin login activity:', error.message);
}

export async function touchAdminLoginActivity() {
  if (typeof window === 'undefined') return;
  const { error } = await supabase.rpc('touch_admin_login_activity' as never, {
    p_device_id: getLoginDeviceId(),
  } as never);
  if (error) console.warn('Unable to update admin login activity:', error.message);
}
