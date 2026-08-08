import { useState, useEffect, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';

export interface MerchantQuotaStatus {
  merchantId: string;
  merchantName: string;
  canTransact: boolean;
  remainingQuota: number;
  totalQuota: number;
  usedQuota: number;
  expiresAt: string | null;
  packageName: string | null;
  type?: 'free' | 'premium';
}

const DEFAULT_FREE_TIER_LIMIT = 100;

async function getFreeTierLimit(): Promise<number> {
  const { data } = await supabase
    .from('app_settings')
    .select('value')
    .eq('key', 'free_tier_quota')
    .maybeSingle();
  return (data?.value as { limit?: number } | null)?.limit ?? DEFAULT_FREE_TIER_LIMIT;
}

function startOfMonthISO(): string {
  const d = new Date();
  d.setDate(1);
  d.setHours(0, 0, 0, 0);
  return d.toISOString();
}

/**
 * Cek status kuota untuk beberapa merchant sekaligus.
 * Merchant dengan langganan aktif memakai kuota berbayar (type 'premium'),
 * sisanya memakai kuota gratis bulanan (type 'free').
 */
export async function fetchMerchantQuotaStatuses(
  merchantIds: string[],
): Promise<Record<string, MerchantQuotaStatus>> {
  if (merchantIds.length === 0) return {};

  const [freeTierLimit, merchantsRes, subsRes] = await Promise.all([
    getFreeTierLimit(),
    supabase.from('merchants').select('id, name').in('id', merchantIds),
    supabase
      .from('merchant_subscriptions')
      .select('merchant_id, transaction_quota, used_quota, expired_at, transaction_packages(name)')
      .in('merchant_id', merchantIds)
      .eq('status', 'ACTIVE')
      .gte('expired_at', new Date().toISOString()),
  ]);

  if (merchantsRes.error) throw merchantsRes.error;
  if (subsRes.error) throw subsRes.error;

  const nameMap = new Map<string, string>();
  for (const m of merchantsRes.data || []) nameMap.set(m.id, m.name);

  type SubRow = {
    merchant_id: string;
    transaction_quota: number;
    used_quota: number;
    expired_at: string | null;
    transaction_packages?: { name?: string | null } | null;
  };

  const subMap = new Map<string, SubRow[]>();
  for (const rawSub of (subsRes.data || []) as unknown as SubRow[]) {
    const list = subMap.get(rawSub.merchant_id) || [];
    list.push(rawSub);
    subMap.set(rawSub.merchant_id, list);
  }

  const freeTierIds = merchantIds.filter((id) => !subMap.has(id));
  const orderCountMap = new Map<string, number>();

  if (freeTierIds.length > 0) {
    const { data: orderRows, error } = await supabase
      .from('orders')
      .select('merchant_id')
      .in('merchant_id', freeTierIds)
      .gte('created_at', startOfMonthISO());
    if (error) throw error;
    for (const row of orderRows || []) {
      if (row.merchant_id) {
        orderCountMap.set(row.merchant_id, (orderCountMap.get(row.merchant_id) || 0) + 1);
      }
    }
  }

  const statuses: Record<string, MerchantQuotaStatus> = {};

  for (const merchantId of merchantIds) {
    const merchantName = nameMap.get(merchantId) || '';
    const subs = subMap.get(merchantId);

    if (subs && subs.length > 0) {
      const totalQuota = subs.reduce((sum, s) => sum + (s.transaction_quota || 0), 0);
      const usedQuota = subs.reduce((sum, s) => sum + (s.used_quota || 0), 0);
      const remainingQuota = Math.max(0, totalQuota - usedQuota);
      const soonest = subs
        .map((s) => s.expired_at)
        .filter((v): v is string => !!v)
        .sort()[0] ?? null;

      statuses[merchantId] = {
        merchantId,
        merchantName,
        canTransact: remainingQuota > 0,
        remainingQuota,
        totalQuota,
        usedQuota,
        expiresAt: soonest,
        packageName: subs[0]?.transaction_packages?.name ?? null,
        type: 'premium',
      };
      continue;
    }

    const used = orderCountMap.get(merchantId) || 0;
    const remaining = Math.max(0, freeTierLimit - used);
    statuses[merchantId] = {
      merchantId,
      merchantName,
      canTransact: remaining > 0,
      remainingQuota: remaining,
      totalQuota: freeTierLimit,
      usedQuota: used,
      expiresAt: null,
      packageName: 'Kuota Gratis',
      type: 'free',
    };
  }

  return statuses;
}

export function useMerchantQuota(merchantIds: string[]) {
  const [quotaStatuses, setQuotaStatuses] = useState<Record<string, MerchantQuotaStatus>>({});
  const [loading, setLoading] = useState(true);
  const [blockedMerchants, setBlockedMerchants] = useState<MerchantQuotaStatus[]>([]);
  const idsKey = merchantIds.join(',');

  const checkQuotas = useCallback(async () => {
    const ids = idsKey ? idsKey.split(',') : [];
    if (ids.length === 0) {
      setQuotaStatuses({});
      setBlockedMerchants([]);
      setLoading(false);
      return;
    }
    try {
      const statuses = await fetchMerchantQuotaStatuses(ids);
      setQuotaStatuses(statuses);
      setBlockedMerchants(Object.values(statuses).filter((s) => !s.canTransact));
    } catch (error) {
      console.error('Error checking merchant quotas:', error);
    } finally {
      setLoading(false);
    }
  }, [idsKey]);

  useEffect(() => {
    checkQuotas();
    // Polling setiap 5 menit agar status kuota tetap segar
    const interval = setInterval(checkQuotas, 5 * 60 * 1000);
    return () => clearInterval(interval);
  }, [checkQuotas]);

  const canProceedCheckout = blockedMerchants.length === 0 && !loading;

  return {
    quotaStatuses,
    blockedMerchants,
    loading,
    canProceedCheckout,
    refetch: checkQuotas,
  };
}

/**
 * Kurangi kuota merchant setelah order berhasil.
 * Bukan React hook — fungsi biasa yang memanggil RPC deduct_merchant_quota.
 */
export async function deductMerchantQuota(merchantId: string, credits: number = 1): Promise<boolean> {
  try {
    const { data, error } = await supabase.rpc('deduct_merchant_quota', {
      p_merchant_id: merchantId,
      p_credits: credits,
    });
    if (error) throw error;
    return data === true;
  } catch (error) {
    console.error('Error using merchant quota:', error);
    return false;
  }
}

// Kirim notifikasi kuota hampir habis / habis ke pemilik toko
export async function notifyMerchantLowQuota(
  merchantId: string,
  remainingQuota: number,
  type: 'low' | 'empty',
): Promise<void> {
  try {
    const { data: merchant, error } = await supabase
      .from('merchants')
      .select('user_id')
      .eq('id', merchantId)
      .maybeSingle();
    if (error) throw error;
    if (!merchant?.user_id) return;

    const title = type === 'empty' ? 'Kuota Habis!' : 'Kuota Hampir Habis';
    const message = type === 'empty'
      ? 'Kuota Anda habis. Toko Anda tidak dapat menerima pesanan baru. Segera beli paket kuota untuk melanjutkan.'
      : `Kuota Anda tersisa ${remainingQuota}. Segera beli paket kuota agar toko tetap bisa menerima pesanan.`;

    await supabase.rpc('send_notification', {
      p_user_id: merchant.user_id,
      p_title: title,
      p_message: message,
      p_type: type === 'empty' ? 'error' : 'warning',
      p_link: '/merchant/subscription',
    });
  } catch (error) {
    console.error('Error sending quota notification:', error);
  }
}
