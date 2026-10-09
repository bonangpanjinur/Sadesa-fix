import { DesaLayout } from '@/components/desa/DesaLayout';
import { ReferralCommissionPanel } from '@/components/referral/ReferralCommissionPanel';

export default function DesaReferralEarningsPage() {
  return (
    <DesaLayout title="Komisi Referral Pedagang" subtitle="Pendapatan referral berdasarkan fee merchant yang tertagih">
      <div className="p-4 lg:p-8"><ReferralCommissionPanel ownerRole="ADMIN_DESA" /></div>
    </DesaLayout>
  );
}
