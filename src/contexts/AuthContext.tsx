import React, { createContext, useContext, useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { AppRole } from '@/types/auth';
import { ensureBuyerFallback, mergeCourierRole, mergeMerchantRole, shouldFetchRolesForAuthEvent } from '@/lib/authRoles';
import { normalizeEmail, signupEmailSchema } from '@/lib/emailValidation';

const AUTH_CHANNEL_NAME = 'desamart_auth';
const AUTH_INIT_TIMEOUT_MS = 8_000;
const AUTH_ROLE_RECOVERY_TIMEOUT_MS = 8_000;

function withTimeout<T>(promise: PromiseLike<T>, timeoutMs: number, message: string): Promise<T> {
  let timeoutId: number | undefined;
  const timeout = new Promise<T>((_, reject) => {
    timeoutId = window.setTimeout(() => reject(new Error(message)), timeoutMs);
  });

  return Promise.race([Promise.resolve(promise), timeout]).finally(() => {
    if (timeoutId !== undefined) window.clearTimeout(timeoutId);
  });
}

interface AuthUser {
  id: string;
  email: string;
  user_metadata?: { full_name?: string };
}

function preserveAuthUserReference(currentUser: AuthUser | null, nextUser: AuthUser | null): AuthUser | null {
  if (currentUser?.id === nextUser?.id
    && currentUser?.email === nextUser?.email
    && currentUser?.user_metadata?.full_name === nextUser?.user_metadata?.full_name) {
    return currentUser;
  }
  return nextUser;
}

interface AuthSession {
  user: AuthUser;
  access_token: string;
}

interface AuthContextType {
  user: AuthUser | null;
  session: AuthSession | null;
  roles: AppRole[];
  loading: boolean;
  rolesLoading: boolean;
  merchantRoleRecoveryLoading: boolean;
  signUp: (email: string, password: string, fullName: string) => Promise<{
    data: { user: unknown; session: unknown };
    error: Error | null;
  }>;
  signIn: (email: string, password: string) => Promise<{ error: Error | null }>;
  signOut: () => Promise<void>;
  hasRole: (role: AppRole) => boolean;
  hasAnyRole: (roles: AppRole[]) => boolean;
  isAdmin: boolean;
  isVerifikator: boolean;
  isMerchant: boolean;
  isCourier: boolean;
  isAdminDesa: boolean;
  isServiceProvider: boolean;
  refetchRoles: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [session, setSession] = useState<AuthSession | null>(null);
  const [roles, setRoles] = useState<AppRole[]>([]);
  const [loading, setLoading] = useState(true);
  const [rolesLoading, setRolesLoading] = useState(true);
  const [merchantRoleRecoveryLoading, setMerchantRoleRecoveryLoading] = useState(false);
  const broadcastRef = useRef<BroadcastChannel | null>(null);
  const rolesRequestRef = useRef(0);
  const activeUserIdRef = useRef<string | null>(null);
  const rolesInFlightRef = useRef(new Map<string, Promise<void>>());

  const fetchUserRoles = useCallback(async (userId: string) => {
    const inFlight = rolesInFlightRef.current.get(userId);
    if (inFlight) {
      await inFlight;
      return;
    }

    const requestId = ++rolesRequestRef.current;
    activeUserIdRef.current = userId;
    const request = (async () => {
      setRolesLoading(true);
      setMerchantRoleRecoveryLoading(false);
      const { data, error } = await withTimeout(
        supabase
          .from('user_roles')
          .select('role')
          .eq('user_id', userId),
        AUTH_INIT_TIMEOUT_MS,
        'Timed out while loading user roles',
      );

      if (error) throw error;
      const userRoles = (data || []).map(r => r.role as AppRole);

      if (requestId !== rolesRequestRef.current || activeUserIdRef.current !== userId) return;
      const needsMerchantRecovery = !userRoles.includes('merchant');
      setMerchantRoleRecoveryLoading(needsMerchantRecovery);
      // The authoritative role result is enough to finish auth initialization.
      // Legacy profile recovery below may enrich this list, but must not keep
      // route guards and the whole application in a loading state.
      setRoles(ensureBuyerFallback(userRoles));
      setRolesLoading(false);

      // These checks only repair legacy accounts which were created before
      // role rows were guaranteed. They must never block authentication.
      // Do not query both profile tables for every authenticated user. The
      // authoritative role row is enough for normal accounts; only legacy
      // accounts missing a role need the corresponding recovery lookup.
      const needsCourierRecovery = !userRoles.includes('courier');
      const [merchantResult, courierResult] = await Promise.all([
        needsMerchantRecovery
          ? withTimeout(
              supabase.from('merchants').select('id').eq('user_id', userId).limit(1).maybeSingle(),
              AUTH_ROLE_RECOVERY_TIMEOUT_MS,
              'Timed out while checking merchant profile for role recovery',
            ).catch((error: unknown) => ({ data: null, error }))
          : Promise.resolve({ data: null, error: null }),
        needsCourierRecovery
          ? withTimeout(
              supabase.from('couriers').select('id').eq('user_id', userId).limit(1).maybeSingle(),
              AUTH_ROLE_RECOVERY_TIMEOUT_MS,
              'Timed out while checking courier profile for role recovery',
            ).catch((error: unknown) => ({ data: null, error }))
          : Promise.resolve({ data: null, error: null }),
      ]);
      if (merchantResult.error) console.warn('Unable to check merchant profile for role recovery:', merchantResult.error);
      if (courierResult.error) console.warn('Unable to check courier profile for role recovery:', courierResult.error);

      if (requestId !== rolesRequestRef.current || activeUserIdRef.current !== userId) return;
      const rolesWithProfiles = mergeCourierRole(
        mergeMerchantRole(userRoles, Boolean(merchantResult.data)),
        Boolean(courierResult.data),
      );
      setRoles(ensureBuyerFallback(rolesWithProfiles));
    })();
    rolesInFlightRef.current.set(userId, request);

    try {
      await request;
    } catch (err) {
      console.warn('Unable to load user roles; using buyer fallback:', err);
      if (requestId !== rolesRequestRef.current || activeUserIdRef.current !== userId) return;
      setRoles(['buyer']);
      // A transient user_roles failure must not send a merchant to
      // /unauthorized before we have tried the existing profile fallback.
      setMerchantRoleRecoveryLoading(true);
      try {
        const { data: merchant, error } = await withTimeout(
          supabase.from('merchants').select('id').eq('user_id', userId).limit(1).maybeSingle(),
          AUTH_ROLE_RECOVERY_TIMEOUT_MS,
          'Timed out while checking merchant profile after role lookup failed',
        );
        if (error) throw error;
        if (merchant && requestId === rolesRequestRef.current && activeUserIdRef.current === userId) {
          setRoles(['merchant', 'buyer']);
        }
      } catch (recoveryError) {
        console.warn('Unable to recover merchant role after role lookup failed:', recoveryError);
      }
    } finally {
      if (rolesInFlightRef.current.get(userId) === request) rolesInFlightRef.current.delete(userId);
      if (requestId === rolesRequestRef.current && activeUserIdRef.current === userId) {
        setRolesLoading(false);
        setMerchantRoleRecoveryLoading(false);
      }
    }
  }, []);

  const refetchRoles = useCallback(async () => {
    if (user) {
      await fetchUserRoles(user.id);
    }
  }, [user, fetchUserRoles]);

  useEffect(() => {
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      async (event, session) => {
        const previousUserId = activeUserIdRef.current;
        const nextUserId = session?.user?.id ?? null;
        const nextUser = (session?.user as AuthUser | undefined) ?? null;
        setSession(session as AuthSession | null);
        setUser((currentUser) => preserveAuthUserReference(currentUser, nextUser));
        activeUserIdRef.current = nextUserId;

        setLoading(false);
        if (session?.user) {
          if (shouldFetchRolesForAuthEvent(event, previousUserId, nextUserId)) {
            void fetchUserRoles(session.user.id);
          }
        } else {
          ++rolesRequestRef.current;
          activeUserIdRef.current = null;
          setRoles([]);
          setMerchantRoleRecoveryLoading(false);
          setRolesLoading(false);
        }
      }
    );

    void withTimeout(
      supabase.auth.getSession(),
      AUTH_INIT_TIMEOUT_MS,
      'Timed out while loading authentication session',
    ).then(({ data: { session } }) => {
      setSession(session as AuthSession | null);
      setUser((currentUser) => preserveAuthUserReference(
        currentUser,
        (session?.user as AuthUser | undefined) ?? null,
      ));
      activeUserIdRef.current = session?.user?.id ?? null;
      setLoading(false);

      if (session?.user) {
        void fetchUserRoles(session.user.id);
      } else {
        setRolesLoading(false);
      }
    }).catch((error: unknown) => {
      console.error('Error loading authentication session:', error);
      setSession(null);
      setUser(null);
      ++rolesRequestRef.current;
      activeUserIdRef.current = null;
      setRoles([]);
      setMerchantRoleRecoveryLoading(false);
      setRolesLoading(false);
      setLoading(false);
    });

    return () => subscription.unsubscribe();
  }, [fetchUserRoles]);

  // R-03: Multi-tab auth sync via BroadcastChannel
  useEffect(() => {
    if (typeof BroadcastChannel === 'undefined') return;

    const channel = new BroadcastChannel(AUTH_CHANNEL_NAME);
    broadcastRef.current = channel;

    channel.onmessage = (event: MessageEvent) => {
      const { type } = event.data as { type: 'LOGOUT' | 'LOGIN' };

      if (type === 'LOGOUT') {
        // Tab lain logout — bersihkan state di tab ini tanpa memanggil signOut lagi
        supabase.auth.signOut().catch(() => {});
        setUser(null);
        setSession(null);
        ++rolesRequestRef.current;
        activeUserIdRef.current = null;
        setRoles([]);
        setMerchantRoleRecoveryLoading(false);
        setLoading(false);
        setRolesLoading(false);
        // Arahkan ke halaman auth
        window.location.href = '/auth';
      } else if (type === 'LOGIN') {
        // Tab lain login — refresh session agar tab ini ikut terotentikasi
        supabase.auth.getSession().then(async ({ data: { session } }) => {
          if (session?.user) {
            setSession(session as AuthSession | null);
            setUser((currentUser) => preserveAuthUserReference(currentUser, session.user as AuthUser));
            await fetchUserRoles(session.user.id);
            setLoading(false);
          }
        });
      }
    };

    return () => {
      channel.close();
      broadcastRef.current = null;
    };
  }, [fetchUserRoles]);

  const signUp = async (email: string, password: string, fullName: string) => {
    const emailResult = signupEmailSchema.safeParse(email);
    if (!emailResult.success) {
      return {
        data: { user: null, session: null },
        error: new Error(emailResult.error.issues[0]?.message ?? 'Email tidak valid'),
      };
    }

    const { data, error } = await supabase.auth.signUp({
      email: normalizeEmail(email),
      password,
      options: {
        emailRedirectTo: window.location.origin,
        data: {
          full_name: fullName,
        },
      },
    });
    return { data, error };
  };

  const signIn = async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    if (!error) {
      broadcastRef.current?.postMessage({ type: 'LOGIN' });
    }
    return { error };
  };

  const signOut = async () => {
    await supabase.auth.signOut();
    setRoles([]);
    // R-03: Beritahu semua tab lain agar ikut logout
    broadcastRef.current?.postMessage({ type: 'LOGOUT' });
  };

  const hasRole = useCallback((role: AppRole): boolean => {
    return roles.includes(role);
  }, [roles]);

  const hasAnyRole = useCallback((checkRoles: AppRole[]): boolean => {
    return checkRoles.some(role => roles.includes(role));
  }, [roles]);

  const isAdmin = hasRole('admin');
  const isVerifikator = hasRole('verifikator');
  const isMerchant = hasRole('merchant');
  const isCourier = hasRole('courier');
  const isAdminDesa = hasRole('admin_desa');
  const isServiceProvider = hasRole('service_provider');

  return (
    <AuthContext.Provider
      value={{
        user,
        session,
        roles,
        loading,
        rolesLoading,
        merchantRoleRecoveryLoading,
        signUp,
        signIn,
        signOut,
        hasRole,
        hasAnyRole,
        isAdmin,
        isVerifikator,
        isMerchant,
        isCourier,
        isAdminDesa,
        isServiceProvider,
        refetchRoles,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
