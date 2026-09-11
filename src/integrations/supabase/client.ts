// Lovable Cloud backend client.
// Replaces the previous Replit /api proxy shim: all database, auth, storage,
// realtime and function calls now go directly to the managed backend.
//
// Note: intentionally created without the generated `Database` generic. Large
// parts of this codebase were written against an untyped proxy shim (dynamic
// update payloads, RPC names, views not present in generated types), so the
// client stays schema-agnostic to keep those call sites valid.
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

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

// Store the client on globalThis as well as at module scope. A module-local
// singleton can still be duplicated when lazy chunks/HMR or a stale service
// worker load another copy of this module. GoTrue clients sharing one
// localStorage key can race each other and emit the duplicate-client warning.
const GLOBAL_CLIENT_KEY = '__SADESA_SUPABASE_CLIENT__';
type SupabaseGlobal = typeof globalThis & {
  [GLOBAL_CLIENT_KEY]?: SupabaseClient;
};

const globalScope = globalThis as SupabaseGlobal;
const browserStorage = typeof window !== 'undefined' ? window.localStorage : undefined;

export const supabase = globalScope[GLOBAL_CLIENT_KEY] ?? createClient(
  SUPABASE_URL,
  SUPABASE_PUBLISHABLE_KEY,
  {
    auth: {
      ...(browserStorage ? { storage: browserStorage } : {}),
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      flowType: 'pkce',
    },
  },
);

globalScope[GLOBAL_CLIENT_KEY] = supabase;
