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

interface POSContextType {
  tenant: POSTenant | null;
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
  const [outlets, setOutlets] = useState<POSOutlet[]>([]);
  const [activeOutlet, setActiveOutlet] = useState<POSOutlet | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchTenant = useCallback(async () => {
    if (!user) {
      setTenant(null);
      setOutlets([]);
      setActiveOutlet(null);
      setError(null);
      return;
    }

    setError(null);
    try {
      const { data, error: queryError } = await supabase
        .from('pos_tenants')
        .select('*')
        .eq('user_id', user.id)
        .maybeSingle();
      if (queryError) throw new Error(queryError.message);
      setTenant(data as unknown as POSTenant | null);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Gagal memuat data usaha';
      console.error('Error fetching POS tenant:', err);
      setTenant(null);
      setOutlets([]);
      setActiveOutlet(null);
      setError(message);
    }
  }, [user]);

  const fetchOutlets = useCallback(async () => {
    if (!tenant) return;
    try {
      const { data } = await supabase
        .from('pos_outlets')
        .select('*')
        .eq('tenant_id', tenant.id)
        .eq('is_active', true)
        .order('name');
      const outletList = (data || []) as unknown as POSOutlet[];
      setOutlets(outletList);
      setActiveOutlet((prev) => prev ?? outletList[0] ?? null);
    } catch (err) {
      console.error('Error fetching outlets:', err);
    }
  }, [tenant]);

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
