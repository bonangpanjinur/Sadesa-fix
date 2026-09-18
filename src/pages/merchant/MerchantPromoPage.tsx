import { MerchantLayout } from '@/components/merchant/MerchantLayout';
import { PromoManager } from '@/components/merchant/PromoManager';
import { CashbackRuleManager } from '@/components/merchant/CashbackRuleManager';
import { useMerchantGuard } from '@/hooks/useMerchantGuard';

export default function MerchantPromoPage() {
  const { merchantId, loading } = useMerchantGuard();

  if (loading) {
    return (
      <MerchantLayout title="Promo & Diskon" subtitle="Kelola promosi produk">
        <div className="flex items-center justify-center py-20">
          <div className="animate-spin rounded-full h-10 w-10 border-2 border-primary border-t-transparent" />
        </div>
      </MerchantLayout>
    );
  }

  if (!merchantId) {
    return null;
  }

  return (
    <MerchantLayout title="Promo & Diskon" subtitle="Kelola promosi produk">
      <div className="space-y-6">
        <PromoManager merchantId={merchantId} />
        <CashbackRuleManager merchantId={merchantId} />
      </div>
    </MerchantLayout>
  );
}
