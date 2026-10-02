import { supabase } from '@/integrations/supabase/client';

export const GUEST_CHECKOUT_FEATURE_KEY = 'guest_checkout_enabled';

function stableBucket(value: string): number {
  // FNV-1a gives a stable, non-sensitive bucket for rollout assignment.
  let hash = 2166136261;
  for (const char of value) {
    hash ^= char.charCodeAt(0);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0) % 100;
}

/**
 * Feature flag values are stored as app_settings.value JSON. Unknown or
 * malformed values intentionally disable guest checkout (fail closed).
 */
export function isGuestCheckoutEnabled(value: unknown, actorKey?: string): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') return ['true', '1', 'on'].includes(value.trim().toLowerCase());
  if (!value || typeof value !== 'object' || !('enabled' in value)) return false;

  const config = value as { enabled?: unknown; rollout_percent?: unknown; pilot_user_ids?: unknown };
  if (!isGuestCheckoutEnabled(config.enabled)) return false;

  const pilots = Array.isArray(config.pilot_user_ids)
    ? config.pilot_user_ids.filter((entry): entry is string => typeof entry === 'string')
    : [];
  if (actorKey && pilots.includes(actorKey)) return true;

  const percent = config.rollout_percent === undefined ? 100 : Number(config.rollout_percent);
  if (!Number.isFinite(percent) || percent <= 0) return false;
  if (percent >= 100) return true;
  return Boolean(actorKey) && stableBucket(actorKey as string) < percent;
}

export async function fetchGuestCheckoutEnabled(actorKey?: string): Promise<boolean> {
  try {
    const { data, error } = await supabase
      .from('app_settings')
      .select('value')
      .eq('key', GUEST_CHECKOUT_FEATURE_KEY)
      .maybeSingle();
    if (error) return false;
    return isGuestCheckoutEnabled(data?.value, actorKey);
  } catch {
    return false;
  }
}
