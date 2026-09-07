import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { MerchantLayout } from '@/components/merchant/MerchantLayout';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { toast } from 'sonner';
import { Check, Globe2, ShoppingBag, Store, Utensils, ArrowLeft, ArrowRight } from 'lucide-react';
import {
  POS_BUSINESS_OPTIONS,
  POS_MODULE_OPTIONS,
  getRecommendedPOSModules,
  type POSBusinessType,
} from '@/lib/posModuleRecommendations';

type DatabaseError = {
  code?: string;
  message?: string;
  details?: string;
};

function getDatabaseErrorMessage(error: DatabaseError | Error | unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === 'object' && error !== null && 'message' in error) {
    const databaseError = error as DatabaseError;
    return databaseError.message || 'Terjadi kesalahan database';
  }
  return 'Terjadi kesalahan yang tidak diketahui';
}

export default function POSSetupPage() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);
  const [step, setStep] = useState(1);
  const [businessType, setBusinessType] = useState<POSBusinessType>('simple');
  const [selectedModules, setSelectedModules] = useState<string[]>(getRecommendedPOSModules('simple'));

  const [tenantData, setTenantData] = useState({
    name: '',
    phone: '',
    address: '',
    timezone: 'Asia/Jakarta',
    currency: 'IDR',
  });

  const [outletData, setOutletData] = useState({
    name: '',
    address: '',
    phone: '',
  });

  useEffect(() => {
    setSelectedModules(getRecommendedPOSModules(businessType));
  }, [businessType]);

  const businessIcon = (icon: string) => {
    if (icon === 'globe') return <Globe2 className="h-5 w-5" />;
    if (icon === 'shopping-bag') return <ShoppingBag className="h-5 w-5" />;
    if (icon === 'utensils') return <Utensils className="h-5 w-5" />;
    return <Store className="h-5 w-5" />;
  };

  const toggleModule = (moduleId: string) => {
    setSelectedModules((current) => current.includes(moduleId)
      ? current.filter((id) => id !== moduleId)
      : [...current, moduleId]);
  };

  const handleCreate = async () => {
    if (!user) return;
    if (!tenantData.name.trim()) { toast.error('Nama usaha wajib diisi'); return; }
    if (!outletData.name.trim()) { toast.error('Nama outlet wajib diisi'); return; }

    setLoading(true);
    try {
      const { error } = await supabase.rpc('activate_merchant_pos_workspace' as never, {
        p_name: tenantData.name,
        p_phone: tenantData.phone || null,
        p_address: tenantData.address || null,
        p_timezone: tenantData.timezone,
        p_currency: tenantData.currency,
        p_outlet_name: outletData.name,
        p_outlet_address: outletData.address || null,
        p_outlet_phone: outletData.phone || null,
        p_business_type: businessType,
        p_enabled_modules: selectedModules,
      } as never);
      if (error) throw error;

      toast.success('Kasir berhasil diaktifkan di workspace merchant Anda.');
      navigate('/merchant', { replace: true });
      window.location.reload();
    } catch (err: unknown) {
      const message = getDatabaseErrorMessage(err);
      if (message.includes('active POS trial or subscription')) {
        toast.error('POS belum bisa diaktifkan. Ajukan trial atau langganan terlebih dahulu, lalu tunggu entitlement aktif.');
      } else if (message.includes('approved and active merchant profile')) {
        toast.error('Toko harus berstatus disetujui dan aktif sebelum POS dapat diaktifkan.');
      } else {
        toast.error(message.includes('duplicate') || message.includes('unique')
          ? 'Usaha untuk akun ini sudah terdaftar. Silakan buka POS.'
          : 'Gagal membuat usaha: ' + message);
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <MerchantLayout title="Siapkan POS" subtitle="Aktifkan kasir dan operasional outlet dari workspace merchant">
      <div className="mx-auto w-full max-w-lg py-4 sm:py-8">
        <div className="mb-8 text-center">
          <div className="mb-4 inline-flex h-16 w-16 items-center justify-center rounded-2xl bg-primary/10">
            <Store className="h-8 w-8 text-emerald-600" />
          </div>
          <h1 className="text-2xl font-bold">Aktifkan POS untuk toko Anda</h1>
          <p className="mt-1 text-muted-foreground">Satu workspace untuk mengelola toko online dan operasional kasir.</p>
        </div>

        <div className="flex items-center justify-center gap-2 mb-6">
          {[1, 2, 3, 4].map(s => (
            <div key={s} className={`flex items-center gap-1.5 ${s < step ? 'text-emerald-600' : s === step ? 'text-foreground' : 'text-muted-foreground'}`}>
              <div className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold border-2 ${s === step ? 'border-emerald-600 bg-emerald-50 text-emerald-600' : s < step ? 'border-emerald-600 bg-emerald-600 text-white' : 'border-muted-foreground/30'}`}>
                {s}
              </div>
               <span className="text-xs font-medium hidden sm:inline">
                 {s === 1 ? 'Jenis usaha' : s === 2 ? 'Modul' : s === 3 ? 'Katalog' : 'Outlet'}
               </span>
               {s < 4 && <ArrowRight className="h-3 w-3 ml-1 text-muted-foreground" />}
            </div>
          ))}
        </div>

        {step === 1 && (
          <Card>
            <CardHeader>
              <CardTitle>Bagaimana Anda berjualan?</CardTitle>
              <CardDescription>Pilihan ini hanya untuk memberi rekomendasi. Modul dapat diubah nanti.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid gap-3 sm:grid-cols-2">
                {POS_BUSINESS_OPTIONS.map((option) => (
                  <button
                    key={option.id}
                    type="button"
                    onClick={() => setBusinessType(option.id)}
                    aria-pressed={businessType === option.id}
                    className={`rounded-xl border p-4 text-left transition-colors ${businessType === option.id ? 'border-primary bg-primary/5 ring-2 ring-primary/20' : 'hover:border-primary/40'}`}
                  >
                    <span className="flex items-center gap-2 font-semibold">{businessIcon(option.icon)}{option.label}</span>
                    <span className="mt-2 block text-xs leading-5 text-muted-foreground">{option.description}</span>
                  </button>
                ))}
              </div>
              <Button
                className="w-full bg-emerald-600 hover:bg-emerald-700"
                onClick={() => {
                  if (businessType === 'online') {
                    navigate('/merchant', { replace: true });
                    return;
                  }
                  setStep(2);
                }}
              >
                Lanjut <ArrowRight className="h-4 w-4 ml-2" />
              </Button>
            </CardContent>
          </Card>
        )}

        {step === 2 && (
          <Card>
            <CardHeader>
              <CardTitle>Pilih modul operasional</CardTitle>
              <CardDescription>Modul yang disarankan sudah dipilih. Anda dapat menyesuaikannya.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-3">
              <div className="grid gap-3 sm:grid-cols-2">
                {POS_MODULE_OPTIONS.map((module) => {
                  const selected = selectedModules.includes(module.id);
                  return (
                    <button
                      key={module.id}
                      type="button"
                      onClick={() => toggleModule(module.id)}
                      aria-pressed={selected}
                      className={`flex items-start gap-3 rounded-xl border p-3 text-left transition-colors ${selected ? 'border-primary bg-primary/5' : 'hover:border-primary/40'}`}
                    >
                      <span className={`mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded border ${selected ? 'border-primary bg-primary text-primary-foreground' : 'border-muted-foreground/40'}`}>
                        {selected && <Check className="h-3.5 w-3.5" />}
                      </span>
                      <span><span className="block text-sm font-semibold">{module.label}</span><span className="mt-1 block text-xs leading-5 text-muted-foreground">{module.description}</span></span>
                    </button>
                  );
                })}
              </div>
              {!selectedModules.includes('cashier') && (
                <p className="rounded-lg bg-warning/10 p-3 text-xs text-warning-foreground">Modul Kasir belum dipilih. Pilih Kasir untuk mengaktifkan operasional POS.</p>
              )}
              <div className="flex gap-2">
                <Button variant="outline" onClick={() => setStep(1)} className="flex-1"><ArrowLeft className="mr-2 h-4 w-4" />Kembali</Button>
                <Button onClick={() => {
                  if (!selectedModules.includes('cashier')) { toast.error('Modul Kasir wajib dipilih'); return; }
                  setStep(3);
                }} className="flex-1">Lanjut <ArrowRight className="ml-2 h-4 w-4" /></Button>
              </div>
            </CardContent>
          </Card>
        )}

        {step === 3 && (
          <Card>
            <CardHeader>
              <CardTitle>Gunakan katalog merchant</CardTitle>
              <CardDescription>Produk yang sudah ada dapat langsung dijual di kasir tanpa dibuat ulang.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="rounded-xl border border-primary/30 bg-primary/5 p-4">
                <p className="font-semibold">Katalog bersama aktif</p>
                <p className="mt-1 text-sm leading-6 text-muted-foreground">Produk, pelanggan, promo, dan stok tetap berada di workspace merchant yang sama. Sistem akan menyiapkan produk yang sudah ada untuk kasir.</p>
              </div>
              <div className="flex gap-2">
                <Button variant="outline" onClick={() => setStep(2)} className="flex-1"><ArrowLeft className="mr-2 h-4 w-4" />Kembali</Button>
                <Button onClick={() => setStep(4)} className="flex-1">Lanjut <ArrowRight className="ml-2 h-4 w-4" /></Button>
              </div>
            </CardContent>
          </Card>
        )}

        {step === 4 && (
          <Card>
            <CardHeader>
              <CardTitle>Outlet / Lokasi Pertama</CardTitle>
              <CardDescription>Outlet adalah lokasi operasional di bawah merchant Anda, bukan bisnis baru.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <Label>Nama Usaha *</Label>
                <Input
                  placeholder="Contoh: Toko Sembako Pak Budi"
                  value={tenantData.name}
                  onChange={e => setTenantData(p => ({ ...p, name: e.target.value }))}
                  className="mt-1"
                />
              </div>
              <div>
                <Label>Nomor Telepon</Label>
                <Input
                  placeholder="08xxxxxxxxxx"
                  value={tenantData.phone}
                  onChange={e => setTenantData(p => ({ ...p, phone: e.target.value }))}
                  className="mt-1"
                />
              </div>
              <div>
                <Label>Alamat Usaha</Label>
                <Textarea
                  placeholder="Alamat lengkap usaha"
                  value={tenantData.address}
                  onChange={e => setTenantData(p => ({ ...p, address: e.target.value }))}
                  className="mt-1"
                  rows={2}
                />
              </div>
              <div>
                <Label>Nama Outlet *</Label>
                <Input
                  placeholder="Contoh: Toko Utama / Cabang Selatan"
                  value={outletData.name}
                  onChange={e => setOutletData(p => ({ ...p, name: e.target.value }))}
                  className="mt-1"
                />
              </div>
              <div>
                <Label>Alamat Outlet</Label>
                <Textarea
                  placeholder="Alamat outlet"
                  value={outletData.address}
                  onChange={e => setOutletData(p => ({ ...p, address: e.target.value }))}
                  className="mt-1"
                  rows={2}
                />
              </div>
              <div>
                <Label>Telepon Outlet</Label>
                <Input
                  placeholder="08xxxxxxxxxx"
                  value={outletData.phone}
                  onChange={e => setOutletData(p => ({ ...p, phone: e.target.value }))}
                  className="mt-1"
                />
              </div>
              <div className="flex gap-2">
                <Button variant="outline" onClick={() => setStep(3)} className="flex-1"><ArrowLeft className="mr-2 h-4 w-4" />Kembali</Button>
                <Button
                  className="flex-1 bg-emerald-600 hover:bg-emerald-700"
                  onClick={handleCreate}
                  disabled={loading}
                >
                  {loading ? 'Menyimpan...' : 'Mulai Sekarang'}
                </Button>
              </div>
            </CardContent>
          </Card>
        )}
      </div>
    </MerchantLayout>
  );
}
