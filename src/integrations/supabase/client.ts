// Lovable Cloud backend client.
// Replaces the previous Replit /api proxy shim: all database, auth, storage,
// realtime and function calls now go directly to the managed backend.
//
// Note: intentionally created without the generated `Database` generic. Large
// parts of this codebase were written against an untyped proxy shim (dynamic
// update payloads, RPC names, views not present in generated types), so the
// client stays schema-agnostic to keep those call sites valid.
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL as string;
const SUPABASE_PUBLISHABLE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string;

export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: {
    storage: localStorage,
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: 'pkce',
  },
});
