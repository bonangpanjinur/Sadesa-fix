import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { CreditCard, Check, Clock, Upload, Loader2, AlertTriangle, Gift, Download, Tag } from 'lucide-react';
import { MerchantLayout } from '@/components/merchant/MerchantLayout';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { ImageUpload } from '@/components/ui/ImageUpload';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import { formatPrice } from '@/lib/utils';
import { getSettingByKey } from '@/lib/adminApi';
import { getPOSSubscriptionState, POS_SUBSCRIPTION_STATE_LABEL } from '@/lib/posSubscription';

interface POSSubscription {
  id: string;
  merchant_id: string;
  package_id: string | null;
  status: string;
  is_trial: boolean;
  payment_amount: number | null;
  payment_status: string | null;
  payment_proof_url: string | null;
  started_at: string | null;
  expired_at: string | null;
  grace_ends_at: string | null;
  rejection_reason: string | null;
  original_amount?: number | null;
  discount_amount?: number | null;
  promotion_code?: string | null;
}

interface POSConfig {
  trial_days?: number;
}

interface POSPackage {
  id: string;
  name: string;
  description: string | null;
  duration_months: number;
  price: number;
  is_active: boolean;
  max_outlets?: number;
  max_users?: number;
  add_on_user_price?: number;
  priority_support?: boolean;
  onboarding_discount_percent?: number;
  onboarding_discount_expires_at?: string | null;
}

export default function MerchantPOSSubscribePage() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [merchantId, setMerchantId] = useState<string | null>(null);
  const [packages, setPackages] = useState<POSPackage[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedPkg, setSelectedPkg] = useState<string | null>(null);
  const [paymentProof, setPaymentProof] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [existingSub, setExistingSub] = useState<POSSubscription | null>(null);
  const [promoCode, setPromoCode] = useState('');
  const [promoPreview, setPromoPreview] = useState<{
    code: string; name: string; partner_type: string | null; discount_percent: number;
    discount_amount: number; original_amount: number; final_amount: number; expires_at: string;
  } | null>(null);
  const [promoLoading, setPromoLoading] = useState(false);
  const [trialDays, setTrialDays] = useState(30);
  const [hasUsedTrial, setHasUsedTrial] = useState(false);
  const [hasPOSWorkspace, setHasPOSWorkspace] = useState(false);

  useEffect(() => {
    async function loadData() {
      if (!user) return;
      try {
        const { data: merchant } = await supabase
          .from('merchants')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

        if (!merchant) { setLoading(false); return; }
        setMerchantId(merchant.id);

        const [{ data: pkgs }, { data: tenant }] = await Promise.all([
          supabase
            .from('pos_packages')
            .select('*')
            .eq('is_active', true)
            .order('sort_order'),
          supabase
            .from('pos_tenants')
            .select('id')
            .eq('merchant_id', merchant.id)
            .maybeSingle(),
        ]);
        setPackages(pkgs || []);
        setHasPOSWorkspace(Boolean(tenant));

        // Check existing subscription
        const { data: sub } = await supabase
          .from('pos_subscriptions')
          .select('*')
          .eq('merchant_id', merchant.id)
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle();
        setExistingSub(sub as POSSubscription | null);

        // Check if trial was used
        const { count } = await supabase
          .from('pos_subscriptions')
          .select('*', { count: 'exact', head: true })
          .eq('merchant_id', merchant.id)
          .eq('is_trial', true);
        setHasUsedTrial((count || 0) > 0);

        // Get trial days config
        const config = await getSettingByKey('pos_config');
        if (config?.value) {
          const posConfig = config.value as POSConfig;
          setTrialDays(posConfig.trial_days || 30);
        }
      } catch (err) {
        console.error(err);
      } finally {
        setLoading(false);
      }
    }
    loadData();
  }, [user]);

  const handleActivateTrial = async () => {
    if (!merchantId) return;
    setSubmitting(true);
    try {
      const now = new Date();
      const expiry = new Date(now);
      expiry.setDate(expiry.getDate() + trialDays);

      const { error } = await supabase.from('pos_subscriptions').insert({
        merchant_id: merchantId,
        status: 'ACTIVE',
        is_trial: true,
        payment_amount: 0,
        payment_status: 'FREE',
        started_at: now.toISOString(),
        expired_at: expiry.toISOString(),
      });
      if (error) throw error;
      toast.success(`Trial ${trialDays} hari berhasil diaktifkan!`);
      window.location.reload();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Gagal mengaktifkan trial');
    } finally {
      setSubmitting(false);
    }
  };

  const handleSubscribe = async () => {
    if (!merchantId || !selectedPkg) return;
    const pkg = packages.find(p => p.id === selectedPkg);
    if (!pkg) return;

    const payableAmount = promoPreview?.final_amount ?? pkg.price;
    if (promoCode.trim() && !promoPreview) {
      toast.error('Validasi kode promo terlebih dahulu');
      return;
    }
    if (payableAmount > 0 && !paymentProof) {
      toast.error('Silakan upload bukti pembayaran');
      return;
    }

    setSubmitting(true);
    try {
      const { error } = await supabase.rpc('create_pos_subscription_with_promotion' as never, {
        p_package_id: pkg.id,
        p_payment_proof_url: paymentProof,
        p_promo_code: promoCode.trim() || null,
      } as never);
      if (error) throw error;
      toast.success('Permintaan berhasil dikirim! Menunggu persetujuan admin.');
      window.location.reload();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Gagal mengirim permintaan');
    } finally {
      setSubmitting(false);
    }
  };

  const handlePreviewPromo = async () => {
    if (!selectedPkg || !promoCode.trim()) {
      setPromoPreview(null);
      return;
    }
    setPromoLoading(true);
    const { data, error } = await supabase.rpc('preview_pos_onboarding_promotion' as never, {
      p_code: promoCode.trim(),
      p_package_id: selectedPkg,
    } as never);
    setPromoLoading(false);
    if (error) {
      setPromoPreview(null);
      toast.error(error.message);
      return;
    }
    setPromoPreview(data as typeof promoPreview);
    toast.success('Kode promo valid');
  };

  const handleExportSubscription = async () => {
    if (!merchantId) return;
    const { data, error } = await supabase.rpc(
      'export_pos_subscription_data' as never,
      { p_merchant_id: merchantId } as never,
    );
    if (error) {
      toast.error(`Gagal mengekspor data subscription: ${error.message}`);
      return;
    }
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = `sadesa-pos-subscription-${new Date().toISOString().slice(0, 10)}.json`;
    anchor.click();
    URL.revokeObjectURL(url);
    toast.success('Export data subscription berhasil diunduh');
  };

  if (loading) {
    return (
      <MerchantLayout title="Langganan POS" subtitle="Pilih paket dan aktifkan operasional kasir">
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
        </div>
      </MerchantLayout>
    );
  }

  // Active and pending subscriptions have a status-first view. Rejected/expired subscriptions can be renewed or resubmitted below.
  if (existingSub) {
    const subscriptionState = getPOSSubscriptionState(existingSub);
    const isActive = subscriptionState === 'ACTIVE' || subscriptionState === 'EXPIRING_SOON' || subscriptionState === 'GRACE_PERIOD';
    const isPending = subscriptionState === 'PENDING_REVIEW';

    if (isActive || isPending || subscriptionState === 'SUSPENDED') return (
      <MerchantLayout title="Langganan POS" subtitle="Status paket dan akses operasional kasir">
        <div className="max-w-lg mx-auto space-y-6">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                {isActive ? <Check className="h-5 w-5 text-success" /> : isPending ? <Clock className="h-5 w-5 text-warning" /> : <AlertTriangle className="h-5 w-5 text-destructive" />}
                {subscriptionState === 'GRACE_PERIOD' ? 'Kasir POS dalam Masa Tenggang' : isActive ? 'Kasir POS Aktif' : isPending ? 'Menunggu Persetujuan Admin' : POS_SUBSCRIPTION_STATE_LABEL[subscriptionState]}
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Status</span>
                <Badge variant={isActive ? 'success' : isPending ? 'warning' : 'destructive'}>
                   {POS_SUBSCRIPTION_STATE_LABEL[subscriptionState]}
                </Badge>
              </div>
              {existingSub.is_trial && (
                <div className="flex justify-between text-sm">
                  <span className="text-muted-foreground">Tipe</span>
                  <Badge variant="info">Trial Gratis</Badge>
                </div>
              )}
              {existingSub.expired_at && (
                <div className="flex justify-between text-sm">
                  <span className="text-muted-foreground">Berlaku hingga</span>
                  <span>{new Date(existingSub.expired_at).toLocaleDateString('id-ID')}</span>
                </div>
              )}
              {subscriptionState === 'GRACE_PERIOD' && existingSub.grace_ends_at && (
                <div className="rounded-lg bg-warning/10 p-3 text-sm text-warning-foreground">
                  Transaksi POS masih dapat berjalan sampai {new Date(existingSub.grace_ends_at).toLocaleDateString('id-ID')}. Setelah itu POS akan ditangguhkan, tetapi data marketplace dan histori tetap tersimpan.
                </div>
              )}
              {existingSub.rejection_reason && (
                <div className="bg-destructive/10 p-3 rounded-lg">
                  <p className="text-sm text-destructive">Alasan ditolak: {existingSub.rejection_reason}</p>
                </div>
              )}
              <Button variant="outline" className="w-full" onClick={handleExportSubscription}>
                <Download className="mr-2 h-4 w-4" /> Export Data Subscription
              </Button>
              {isActive && !hasPOSWorkspace && (
                <Button className="w-full" onClick={() => navigate('/merchant/pos/setup')}>
                  Siapkan workspace POS
                </Button>
              )}
            </CardContent>
          </Card>
        </div>
      </MerchantLayout>
    );
  }

  return (
    <MerchantLayout title="Langganan POS" subtitle="Pilih paket dan aktifkan operasional kasir">
        <div className="max-w-2xl mx-auto space-y-6">
        {existingSub && (
          <Card className="border-warning/40 bg-warning/5">
            <CardContent className="p-4">
              <p className="font-semibold">Langganan sebelumnya: {POS_SUBSCRIPTION_STATE_LABEL[getPOSSubscriptionState(existingSub)]}</p>
              {existingSub.rejection_reason && <p className="mt-1 text-sm text-muted-foreground">Catatan admin: {existingSub.rejection_reason}</p>}
              <p className="mt-2 text-xs text-muted-foreground">Anda dapat memilih paket baru dan mengirim permintaan kembali. Masa aktif baru dimulai setelah disetujui admin.</p>
            </CardContent>
          </Card>
        )}

        <Card className="border-primary/20 bg-primary/5">
          <CardHeader className="pb-3"><CardTitle className="text-base">Alur Aktivasi POS</CardTitle></CardHeader>
          <CardContent className="grid gap-3 text-sm sm:grid-cols-4">
            <div><p className="font-semibold">1. Pilih paket</p><p className="text-xs text-muted-foreground">Bandingkan durasi dan harga.</p></div>
            <div><p className="font-semibold">2. Bayar</p><p className="text-xs text-muted-foreground">Ikuti instruksi pembayaran.</p></div>
            <div><p className="font-semibold">3. Kirim bukti</p><p className="text-xs text-muted-foreground">Admin memverifikasi permintaan.</p></div>
            <div><p className="font-semibold">4. Mulai POS</p><p className="text-xs text-muted-foreground">Akses aktif setelah disetujui.</p></div>
          </CardContent>
        </Card>

        {/* Free Trial */}
        {!hasUsedTrial && (
          <Card className="border-primary/50 bg-primary/5">
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Gift className="h-5 w-5 text-primary" />
                Coba Gratis {trialDays} Hari!
              </CardTitle>
              <CardDescription>
                Coba fitur kasir POS selama {trialDays} hari tanpa biaya
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Button onClick={handleActivateTrial} disabled={submitting} className="w-full">
                {submitting ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Gift className="h-4 w-4 mr-2" />}
                Aktifkan Trial Gratis
              </Button>
            </CardContent>
          </Card>
        )}

        {/* Packages */}
        <h3 className="font-bold text-lg">Paket Berlangganan</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {packages.map(pkg => (
            <Card
              key={pkg.id}
              className={`cursor-pointer transition-all ${selectedPkg === pkg.id ? 'ring-2 ring-primary border-primary' : 'hover:border-primary/30'}`}
              onClick={() => setSelectedPkg(pkg.id)}
            >
              <CardContent className="p-4 space-y-2">
                <h4 className="font-bold">{pkg.name}</h4>
                {pkg.description && <p className="text-sm text-muted-foreground">{pkg.description}</p>}
                <p className="text-2xl font-bold text-primary">{formatPrice(pkg.price)}</p>
                <p className="text-xs text-muted-foreground">{pkg.duration_months} bulan</p>
                <div className="grid grid-cols-2 gap-x-3 gap-y-1 pt-2 text-xs text-muted-foreground">
                  <span>{pkg.max_outlets ?? 1} outlet</span>
                  <span>{pkg.max_users ?? 2} pengguna</span>
                  <span>Add-on {formatPrice(pkg.add_on_user_price ?? 25000)}/pengguna</span>
                  <span>{pkg.priority_support ? 'Dukungan prioritas' : 'Dukungan standar'}</span>
                </div>
                {(pkg.onboarding_discount_percent ?? 0) > 0 && (
                  <Badge variant="secondary" className="mt-2">
                    Promo onboarding {pkg.onboarding_discount_percent}%{pkg.onboarding_discount_expires_at ? ` sampai ${new Date(pkg.onboarding_discount_expires_at).toLocaleDateString('id-ID')}` : ''}
                  </Badge>
                )}
                {selectedPkg === pkg.id && (
                  <Badge variant="default"><Check className="h-3 w-3 mr-1" /> Dipilih</Badge>
                )}
                {selectedPkg === pkg.id && promoPreview?.final_amount !== undefined && promoPreview.original_amount === pkg.price && (
                  <div className="rounded-lg bg-emerald-50 border border-emerald-200 p-2 text-xs text-emerald-700">
                    Harga setelah promo: <strong>{formatPrice(promoPreview.final_amount)}</strong>
                  </div>
                )}
              </CardContent>
            </Card>
          ))}
        </div>

        {packages.length === 0 && (
          <div className="text-center py-10 text-muted-foreground">
            <p>Belum ada paket tersedia. Hubungi admin.</p>
          </div>
        )}

        {selectedPkg && (
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-base flex items-center gap-2"><Tag className="h-4 w-4" /> Kode promo partner</CardTitle>
              <CardDescription>Masukkan kode dari desa, koperasi, atau partner resmi. Kode hanya dapat digunakan satu kali.</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="flex gap-2">
                <Input
                  value={promoCode}
                  onChange={e => { setPromoCode(e.target.value.toUpperCase()); setPromoPreview(null); }}
                  placeholder="Contoh: KOPERASI2026"
                  maxLength={40}
                  className="uppercase"
                />
                <Button variant="outline" onClick={handlePreviewPromo} disabled={!promoCode.trim() || promoLoading}>
                  {promoLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Gunakan'}
                </Button>
              </div>
              {promoPreview && (
                <div className="mt-3 rounded-lg border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-medium">{promoPreview.name}{promoPreview.partner_type ? ` · ${promoPreview.partner_type}` : ''}</span>
                    <Badge variant="secondary">{promoPreview.discount_percent}% off</Badge>
                  </div>
                  <p className="mt-1">Potongan {formatPrice(promoPreview.discount_amount)} · berlaku sampai {new Date(promoPreview.expires_at).toLocaleDateString('id-ID')}</p>
                </div>
              )}
            </CardContent>
          </Card>
        )}

        {/* Payment Proof */}
        {selectedPkg && (promoPreview?.final_amount ?? (packages.find(p => p.id === selectedPkg)?.price || 0)) > 0 && (
          <Card>
            <CardHeader>
              <CardTitle className="text-base flex items-center gap-2">
                <Upload className="h-4 w-4" /> Bukti Pembayaran
              </CardTitle>
            </CardHeader>
            <CardContent>
              <ImageUpload
                value={paymentProof}
                onChange={setPaymentProof}
                bucket="payment-proofs"
                path={`pos/${merchantId}`}
                placeholder="Upload bukti pembayaran"
              />
            </CardContent>
          </Card>
        )}

        {selectedPkg && (
          <Button onClick={handleSubscribe} disabled={submitting} className="w-full" size="lg">
            {submitting ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <CreditCard className="h-4 w-4 mr-2" />}
            Kirim Permintaan Langganan
          </Button>
        )}
      </div>
    </MerchantLayout>
  );
}
