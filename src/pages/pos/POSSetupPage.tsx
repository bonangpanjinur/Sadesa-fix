import { useState } from 'react';
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
import { Store, ArrowRight } from 'lucide-react';

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

  const handleCreate = async () => {
    if (!user) return;
    if (!tenantData.name.trim()) { toast.error('Nama usaha wajib diisi'); return; }
    if (!outletData.name.trim()) { toast.error('Nama outlet wajib diisi'); return; }

    setLoading(true);
    try {
      const { error } = await supabase.rpc('ensure_merchant_pos_workspace' as never, {
        p_name: tenantData.name,
        p_phone: tenantData.phone || null,
        p_address: tenantData.address || null,
        p_timezone: tenantData.timezone,
        p_currency: tenantData.currency,
        p_outlet_name: outletData.name,
        p_outlet_address: outletData.address || null,
        p_outlet_phone: outletData.phone || null,
      } as never);
      if (error) throw error;

      toast.success('Usaha berhasil dibuat! Selamat datang di SaDesa POS.');
      navigate('/merchant', { replace: true });
      window.location.reload();
    } catch (err: unknown) {
      const message = getDatabaseErrorMessage(err);
      toast.error(message.includes('duplicate') || message.includes('unique')
        ? 'Usaha untuk akun ini sudah terdaftar. Silakan buka POS.'
        : 'Gagal membuat usaha: ' + message);
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
          {[1, 2].map(s => (
            <div key={s} className={`flex items-center gap-1.5 ${s < step ? 'text-emerald-600' : s === step ? 'text-foreground' : 'text-muted-foreground'}`}>
              <div className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold border-2 ${s === step ? 'border-emerald-600 bg-emerald-50 text-emerald-600' : s < step ? 'border-emerald-600 bg-emerald-600 text-white' : 'border-muted-foreground/30'}`}>
                {s}
              </div>
              <span className="text-xs font-medium hidden sm:inline">{s === 1 ? 'Info Usaha' : 'Outlet Pertama'}</span>
              {s < 2 && <ArrowRight className="h-3 w-3 ml-1 text-muted-foreground" />}
            </div>
          ))}
        </div>

        {step === 1 && (
          <Card>
            <CardHeader>
              <CardTitle>Informasi Usaha</CardTitle>
              <CardDescription>Data ini akan muncul di struk dan laporan.</CardDescription>
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
              <Button
                className="w-full bg-emerald-600 hover:bg-emerald-700"
                onClick={() => {
                  if (!tenantData.name.trim()) { toast.error('Nama usaha wajib diisi'); return; }
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
              <CardTitle>Outlet / Lokasi Pertama</CardTitle>
              <CardDescription>Bisa ditambah outlet lain nanti di Pengaturan.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
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
                <Button variant="outline" onClick={() => setStep(1)} className="flex-1">Kembali</Button>
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
