import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
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
    let createdTenantId: string | null = null;
    try {
      const { data: insertedTenant, error: tenantError } = await supabase
        .from('pos_tenants' as never)
        .insert({ ...tenantData, user_id: user.id })
        .select('id')
        .single();

      let tenantId = (insertedTenant as unknown as { id?: string } | null)?.id;
      if (tenantError) {
        const databaseError = tenantError as DatabaseError;
        if (databaseError.code !== '23505') throw tenantError;
        const { data: existingTenant, error: existingTenantError } = await supabase
          .from('pos_tenants' as never)
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();
        if (existingTenantError) throw existingTenantError;
        tenantId = (existingTenant as unknown as { id?: string } | null)?.id;
      }

      if (!tenantId) throw new Error('Usaha gagal dibuat karena ID tenant tidak tersedia');
      if (!tenantError) createdTenantId = tenantId;

      const { data: existingOutlet, error: existingOutletError } = await supabase
        .from('pos_outlets' as never)
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .limit(1)
        .maybeSingle();
      if (existingOutletError) throw existingOutletError;

      if (!existingOutlet) {
        const { error: outletError } = await supabase
          .from('pos_outlets' as never)
          .insert({ ...outletData, tenant_id: tenantId });
        if (outletError) throw outletError;
      }

      toast.success('Usaha berhasil dibuat! Selamat datang di DesaMart POS.');
      navigate('/pos', { replace: true });
      window.location.reload();
    } catch (err: unknown) {
      if (createdTenantId) {
        const { error: cleanupError } = await supabase
          .from('pos_tenants' as never)
          .delete()
          .eq('id', createdTenantId)
          .eq('user_id', user.id);
        if (cleanupError) console.error('Failed to rollback POS tenant creation:', cleanupError);
      }
      const message = getDatabaseErrorMessage(err);
      toast.error(message.includes('duplicate') || message.includes('unique')
        ? 'Usaha untuk akun ini sudah terdaftar. Silakan buka POS.'
        : 'Gagal membuat usaha: ' + message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-emerald-50 to-white flex items-center justify-center p-4">
      <div className="w-full max-w-lg">
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 bg-emerald-100 rounded-2xl mb-4">
            <Store className="h-8 w-8 text-emerald-600" />
          </div>
          <h1 className="text-2xl font-bold">Selamat Datang di DesaMart POS</h1>
          <p className="text-muted-foreground mt-1">Sistem Kasir & Manajemen UMKM</p>
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
                  {loading ? 'Menyimpan...' : 'Mulai Sekarang 🚀'}
                </Button>
              </div>
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}
