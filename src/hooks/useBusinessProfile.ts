import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { BUSINESS_PROFILE, type BusinessProfile } from '@/config/businessProfile';

type SettingValue = string | number | boolean | Record<string, unknown> | null;
type SettingRow = { key: string; value: SettingValue };

function asString(value: unknown): string | undefined {
  if (typeof value === 'string' || typeof value === 'number') {
    const normalized = String(value).trim();
    return normalized || undefined;
  }
  if (value && typeof value === 'object' && 'value' in value) return asString((value as { value?: unknown }).value);
  return undefined;
}

function getValue(settings: Map<string, SettingValue>, keys: string[]): string | undefined {
  for (const key of keys) {
    const value = asString(settings.get(key));
    if (value) return value;
  }
  return undefined;
}

function readSiteInfo(settings: Map<string, SettingValue>): Record<string, unknown> {
  const candidates = ['site_info', 'business_profile', 'contact_info', 'company_info'];
  return candidates.reduce<Record<string, unknown>>((result, key) => {
    const value = settings.get(key);
    if (value && typeof value === 'object' && !Array.isArray(value)) Object.assign(result, value);
    return result;
  }, {});
}

function resolveProfile(rows: SettingRow[]): BusinessProfile {
  const settings = new Map(rows.map((row) => [row.key, row.value]));
  const siteInfo = readSiteInfo(settings);
  const nested = (keys: string[]) => keys.map((key) => siteInfo[key]).map(asString).find(Boolean);
  const resolve = (keys: string[], fallback: string) => getValue(settings, keys) || nested(keys) || fallback;

  return {
    brandName: resolve(['site_name', 'name'], BUSINESS_PROFILE.brandName),
    legalName: resolve(['company_legal_name', 'legal_name', 'company_name'], BUSINESS_PROFILE.legalName),
    tagline: resolve(['site_tagline', 'tagline'], BUSINESS_PROFILE.tagline),
    address: resolve(['business_address', 'address', 'company_address'], BUSINESS_PROFILE.address),
    phone: resolve(['business_phone', 'support_phone', 'phone'], BUSINESS_PROFILE.phone),
    whatsapp: resolve(['business_whatsapp', 'support_whatsapp', 'whatsapp'], BUSINESS_PROFILE.whatsapp),
    email: resolve(['business_email', 'support_email', 'email'], BUSINESS_PROFILE.email),
    operatingHours: resolve(['business_operating_hours', 'operating_hours', 'hours'], BUSINESS_PROFILE.operatingHours),
    serviceArea: resolve(['business_service_area', 'service_area', 'coverage_area'], BUSINESS_PROFILE.serviceArea),
  };
}

export function useBusinessProfile() {
  const [profile, setProfile] = useState<BusinessProfile>(BUSINESS_PROFILE);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  const fetchProfile = useCallback(async () => {
    setLoading(true);
    setError(false);
    const { data, error: queryError } = await supabase
      .from('app_settings')
      .select('key, value')
      .limit(250);

    if (queryError) {
      console.error('Error fetching public business profile:', queryError);
      setError(true);
      setLoading(false);
      return;
    }

    setProfile(resolveProfile((data || []) as SettingRow[]));
    setLoading(false);
  }, []);

  useEffect(() => {
    void fetchProfile();
  }, [fetchProfile]);

  return { profile, loading, error, refetch: fetchProfile };
}

export { resolveProfile };
