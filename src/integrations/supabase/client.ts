// Lovable Cloud backend client.
// Replaces the previous Replit /api proxy shim: all database, auth, storage,
// realtime and function calls now go directly to the managed backend.
//
// Note: intentionally created without the generated `Database` generic. Large
// parts of this codebase were written against an untyped proxy shim (dynamic
// update payloads, RPC names, views not present in generated types), so the
// client stays schema-agnostic to keep those call sites valid.
import { createClient } from '@supabase/supabase-js';

// Vite replaces import.meta.env values at build time. Static deployments such
// as Replit/Railway do not have browser runtime environment variables, so keep
// the browser-safe project configuration as a last-resort build fallback.
// These values are public by design; authorization is enforced by Supabase RLS.
const DEFAULT_PUBLIC_CONFIG = {
  url: 'https://xqdbnlcvboelvkdotilj.supabase.co',
  publishableKey: 'sb_publishable_GGm4KeLx3PfUM2JYXldI1Q_lE4noIGz',
} as const;

function requirePublicRuntimeValue(name: string, value: unknown): string {
  if (typeof value !== 'string' || value.trim() === '' || value.startsWith('your_')) {
    throw new Error(`Missing required public runtime configuration: ${name}`);
  }
  return value;
}

export const SUPABASE_URL = requirePublicRuntimeValue(
  'VITE_SUPABASE_URL',
  import.meta.env.VITE_SUPABASE_URL || DEFAULT_PUBLIC_CONFIG.url,
);
export const SUPABASE_PUBLISHABLE_KEY = requirePublicRuntimeValue(
  'VITE_SUPABASE_PUBLISHABLE_KEY',
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || DEFAULT_PUBLIC_CONFIG.publishableKey,
);

export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: {
    storage: localStorage,
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: 'pkce',
  },
});
