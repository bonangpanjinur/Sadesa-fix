import React, { createContext, useContext, useState, useEffect, useCallback, ReactNode } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';

interface POSTenant {
  id: string;
  name: string;
  store_name?: string;
  logo_url?: string;
  phone?: string;
  address?: string;
  currency: string;
  timezone: string;
}

interface POSOutlet {
  id: string;
  tenant_id: string;
  name: string;
  address?: string;
  phone?: string;
  is_active: boolean;
}

export type POSRole = 'owner' | 'manager' | 'kasir' | 'staff_gudang' | 'purchasing' | 'finance' | 'auditor';
const POS_ROLES: readonly POSRole[] = ['owner', 'manager', 'kasir', 'staff_gudang', 'purchasing', 'finance', 'auditor'];
function isPOSRole(value: unknown): value is POSRole {
  return typeof value === 'string' && POS_ROLES.includes(value as POSRole);
}

interface POSContextType {
  tenant: POSTenant | null;
  posRole: POSRole | null;
  posRoleLoading: boolean;
  activeOutlet: POSOutlet | null;
  outlets: POSOutlet[];
  loading: boolean;
  error: string | null;
  setActiveOutlet: (outlet: POSOutlet) => void;
  refetchTenant: () => Promise<void>;
  refetchOutlets: () => Promise<void>;
  formatCurrency: (amount: number) => string;
}

const POSContext = createContext<POSContextType | undefined>(undefined);

export function POSProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const [tenant, setTenant] = useState<POSTenant | null>(null);
  const [posRole, setPosRole] = useState<POSRole | null>(null);
  const [posRoleLoading, setPosRoleLoading] = useState(true);
  const [outlets, setOutlets] = useState<POSOutlet[]>([]);
  const [activeOutlet, setActiveOutlet] = useState<POSOutlet | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchTenant = useCallback(async () => {
    if (!user) {
      setTenant(null);
      setPosRole(null);
      setPosRoleLoading(false);
      setOutlets([]);
      setActiveOutlet(null);
      setError(null);
      return;
    }

    setError(null);
    try {
      const { data: ownedTenant, error: ownerError } = await supabase
        .from('pos_tenants')
        .select('*')
        .eq('user_id', user.id)
        .maybeSingle();
      if (ownerError) throw new Error(ownerError.message);

      let resolvedTenant = ownedTenant as unknown as POSTenant | null;
      let resolvedRole: POSRole | null = ownedTenant ? 'owner' : null;
      if (!resolvedTenant) {
        const { data: membership, error: membershipError } = await supabase
          .from('pos_users')
          .select('tenant_id, role, is_active')
          .eq('user_id', user.id)
          .eq('is_active', true)
          .limit(1)
          .maybeSingle();
        if (membershipError) throw new Error(membershipError.message);
        if (membership) {
          const { data: memberTenant, error: tenantError } = await supabase
            .from('pos_tenants')
            .select('*')
            .eq('id', membership.tenant_id)
            .maybeSingle();
          if (tenantError) throw new Error(tenantError.message);
          resolvedTenant = memberTenant as unknown as POSTenant | null;
          resolvedRole = isPOSRole(membership.role) ? membership.role : null;
        }
      }

      setTenant(resolvedTenant);
      setPosRole(resolvedRole);
      setPosRoleLoading(false);
      if (!resolvedTenant) return;
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Gagal memuat data usaha';
      console.error('Error fetching POS tenant:', err);
      setTenant(null);
      setPosRole(null);
      setPosRoleLoading(false);
      setOutlets([]);
      setActiveOutlet(null);
      setError(message);
    }
  }, [user]);

  const fetchOutlets = useCallback(async () => {
    if (!tenant) return;
    try {
      let outletQuery = supabase
        .from('pos_outlets')
        .select('*')
        .eq('tenant_id', tenant.id)
        .eq('is_active', true);
      if (posRole && posRole !== 'owner') {
        const { data: assignmentRows, error: assignmentError } = await supabase
          .from('pos_users')
          .select('outlet_id')
          .eq('tenant_id', tenant.id)
          .eq('user_id', user?.id ?? '')
          .eq('is_active', true);
        if (assignmentError) throw new Error(assignmentError.message);
        const assignedOutletIds = (assignmentRows || [])
          .map((row) => row.outlet_id)
          .filter((id): id is string => typeof id === 'string');
        if (assignedOutletIds.length > 0) outletQuery = outletQuery.in('id', assignedOutletIds);
      }
      const { data, error: outletError } = await outletQuery.order('name');
      if (outletError) throw new Error(outletError.message);
      const outletList = (data || []) as unknown as POSOutlet[];
      setOutlets(outletList);
      setActiveOutlet((prev) => prev ?? outletList[0] ?? null);
    } catch (err) {
      console.error('Error fetching outlets:', err);
    }
  }, [tenant, posRole, user?.id]);

  useEffect(() => {
    const init = async () => {
      setLoading(true);
      await fetchTenant();
      setLoading(false);
    };
    if (user) init();
    else setLoading(false);
  }, [user, fetchTenant]);

  useEffect(() => {
    if (tenant) fetchOutlets();
  }, [tenant, fetchOutlets]);

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('id-ID', {
      style: 'currency',
      currency: tenant?.currency || 'IDR',
      minimumFractionDigits: 0,
    }).format(amount);
  };

  return (
    <POSContext.Provider value={{
      tenant,
      posRole,
      posRoleLoading,
      activeOutlet,
      outlets,
      loading,
      error,
      setActiveOutlet,
      refetchTenant: fetchTenant,
      refetchOutlets: fetchOutlets,
      formatCurrency,
    }}>
      {children}
    </POSContext.Provider>
  );
}

export function usePOS() {
  const ctx = useContext(POSContext);
  if (!ctx) throw new Error('usePOS must be used within POSProvider');
  return ctx;
}
