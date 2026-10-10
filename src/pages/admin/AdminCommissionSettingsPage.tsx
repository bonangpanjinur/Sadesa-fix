import { useMemo, useState } from 'react';
import { AlertCircle, Calculator, CheckCircle2, Percent, Save, Wallet } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { supabase } from '@/integrations/supabase/client';
import { formatPrice } from '@/lib/utils';
import { toast } from 'sonner';

type Merchant = { id: string; name: string };
type FeeSetting = { fee_percent: number; is_enabled: boolean };
type Wallet = { balance_rupiah: number; debt_rupiah: number; is_active: boolean };

export default function AdminCommissionSettingsPage() {
  const [feePercent, setFeePercent] = useState('3');
  const [isEnabled, setIsEnabled] = useState(true);
  const [simulationAmount, setSimulationAmount] = useState('100000');
  const [selectedMerchant, setSelectedMerchant] = useState('');
  const [saving, setSaving] = useState(false);
  const [savedAt, setSavedAt] = useState<Date | null>(null);
  const { data, isLoading, refetch } = useQuery<{ merchants: Merchant[]; setting: FeeSetting | null }>({
    queryKey: ['admin-commission-settings'],
    queryFn: async () => {
      const [merchantRes, settingRes] = await Promise.all([
        supabase.from('merchants').select('id,name').order('name'),
        supabase.from('commission_fee_settings' as never).select('fee_percent,is_enabled').eq('owner_type' as never, 'MERCHANT' as never).maybeSingle(),
      ]);
      if (merchantRes.error) throw merchantRes.error;
      if (settingRes.error) throw settingRes.error;
      const setting = settingRes.data as unknown as FeeSetting | null;
      if (setting) { setFeePercent(String(setting.fee_percent)); setIsEnabled(setting.is_enabled); }
      return { merchants: (merchantRes.data ?? []) as Merchant[], setting };
    },
  });
  const merchants = useMemo(() => data?.merchants ?? [], [data?.merchants]);
  const { data: wallet } = useQuery<Wallet | null>({
    queryKey: ['admin-commission-wallet-preview', selectedMerchant], enabled: !!selectedMerchant,
    queryFn: async () => { const { data: walletData, error } = await supabase.from('commission_wallets' as never).select('balance_rupiah,debt_rupiah,is_active').eq('owner_type' as never, 'MERCHANT' as never).eq('merchant_id' as never, selectedMerchant as never).maybeSingle(); if (error) throw error; return walletData as unknown as Wallet | null; },
  });
  const amount = Math.max(0, Number(simulationAmount) || 0);
  const rate = Math.min(100, Math.max(0, Number(feePercent) || 0));
  const simulatedFee = isEnabled ? Math.round(amount * rate / 100) : 0;
  const startingBalance = Number(wallet?.balance_rupiah ?? 0);
  const startingDebt = Number(wallet?.debt_rupiah ?? 0);
  const balanceAfter = Math.max(0, startingBalance - simulatedFee);
  const newDebt = startingDebt + Math.max(0, simulatedFee - startingBalance);
  const merchantName = useMemo(() => merchants.find((merchant) => merchant.id === selectedMerchant)?.name ?? 'Merchant terpilih', [merchants, selectedMerchant]);
  const saveSettings = async () => {
    if (rate < 0 || rate > 100) { toast.error('Tarif komisi harus berada di antara 0% dan 100%'); return; }
    setSaving(true);
    const { error } = await supabase.from('commission_fee_settings' as never).upsert({ owner_type: 'MERCHANT', fee_percent: rate, is_enabled: isEnabled } as never, { onConflict: 'owner_type' });
    setSaving(false);
    if (error) { toast.error(`Pengaturan gagal disimpan: ${error.message}`); return; }
    setSavedAt(new Date()); await refetch(); toast.success('Pengaturan komisi merchant berhasil disimpan');
  };

  return <AdminLayout title="Pengaturan Komisi Merchant" subtitle="Atur tarif dinamis dan simulasi pemotongan saldo sebelum diberlakukan"><div className="space-y-6"><Alert className="border-primary/20 bg-primary/5"><Percent className="h-4 w-4" /><AlertTitle>Komisi dinamis dan aman</AlertTitle><AlertDescription>Perubahan tarif berlaku untuk transaksi baru. Potongan saldo aktual tetap diproses oleh RPC server dan dicatat ke ledger wallet.</AlertDescription></Alert><div className="grid gap-6 lg:grid-cols-[1.05fr_1.95fr]"><Card><CardHeader><CardTitle className="flex items-center gap-2"><Percent className="h-5 w-5 text-primary" />Tarif platform merchant</CardTitle><CardDescription>Nilai ini menjadi tarif default untuk seluruh merchant.</CardDescription></CardHeader><CardContent className="space-y-5"><div className="space-y-2"><Label htmlFor="merchant-fee-percent">Tarif komisi (%)</Label><div className="relative"><Input id="merchant-fee-percent" type="number" min="0" max="100" step="0.01" value={feePercent} onChange={(event) => setFeePercent(event.target.value)} className="pr-10 text-lg font-semibold" /><span className="absolute right-3 top-2.5 text-sm text-muted-foreground">%</span></div><p className="text-xs text-muted-foreground">Contoh: 3 berarti platform memotong Rp3.000 dari transaksi Rp100.000.</p></div><div className="flex items-center justify-between rounded-xl border p-4"><div><Label htmlFor="merchant-fee-enabled">Aktifkan komisi</Label><p className="mt-1 text-xs text-muted-foreground">Jika nonaktif, transaksi tidak dipotong komisi.</p></div><Switch id="merchant-fee-enabled" checked={isEnabled} onCheckedChange={setIsEnabled} /></div><Button className="w-full" onClick={() => void saveSettings()} disabled={saving || isLoading}><Save className="mr-2 h-4 w-4" />{saving ? 'Menyimpan...' : 'Simpan pengaturan'}</Button>{savedAt && <p className="flex items-center justify-center gap-1.5 text-xs text-emerald-600"><CheckCircle2 className="h-3.5 w-3.5" />Tersimpan {savedAt.toLocaleTimeString('id-ID')}</p>}</CardContent></Card><Card><CardHeader><CardTitle className="flex items-center gap-2"><Calculator className="h-5 w-5 text-primary" />Simulasi pemotongan saldo</CardTitle><CardDescription>Simulasi ini tidak mengubah wallet atau membuat ledger.</CardDescription></CardHeader><CardContent className="space-y-5"><div className="grid gap-4 sm:grid-cols-2"><div className="space-y-2"><Label>Merchant</Label><Select value={selectedMerchant} onValueChange={setSelectedMerchant}><SelectTrigger><SelectValue placeholder="Pilih merchant" /></SelectTrigger><SelectContent>{merchants.map((merchant) => <SelectItem key={merchant.id} value={merchant.id}>{merchant.name}</SelectItem>)}</SelectContent></Select></div><div className="space-y-2"><Label htmlFor="simulation-amount">Nilai transaksi (Rp)</Label><Input id="simulation-amount" type="number" min="0" value={simulationAmount} onChange={(event) => setSimulationAmount(event.target.value)} /></div></div><div className="rounded-2xl bg-muted/50 p-4"><div className="flex items-center justify-between gap-3"><div><p className="text-sm font-medium">{selectedMerchant ? merchantName : 'Belum ada merchant dipilih'}</p><p className="text-xs text-muted-foreground">{selectedMerchant ? 'Wallet komisi saat ini' : 'Pilih merchant untuk melihat saldo aktual'}</p></div><Badge variant={isEnabled ? 'default' : 'secondary'}>{isEnabled ? `${rate}% aktif` : 'Komisi nonaktif'}</Badge></div><div className="mt-4 grid gap-3 sm:grid-cols-3"><div className="rounded-xl border bg-background p-3"><p className="text-xs text-muted-foreground">Saldo awal</p><p className="mt-1 font-semibold">{formatPrice(startingBalance)}</p></div><div className="rounded-xl border bg-background p-3"><p className="text-xs text-muted-foreground">Potongan komisi</p><p className="mt-1 font-semibold text-orange-600">-{formatPrice(simulatedFee)}</p></div><div className="rounded-xl border bg-background p-3"><p className="text-xs text-muted-foreground">Saldo setelah potong</p><p className="mt-1 font-semibold text-emerald-600">{formatPrice(balanceAfter)}</p></div></div></div>{selectedMerchant && simulatedFee > startingBalance && <Alert variant="destructive"><AlertCircle className="h-4 w-4" /><AlertTitle>Saldo tidak mencukupi</AlertTitle><AlertDescription>Kekurangan {formatPrice(simulatedFee - startingBalance)} akan menjadi tagihan. Estimasi tagihan setelah transaksi: {formatPrice(newDebt)}.</AlertDescription></Alert>}{selectedMerchant && simulatedFee <= startingBalance && <Alert><Wallet className="h-4 w-4" /><AlertTitle>Saldo mencukupi</AlertTitle><AlertDescription>Saldo merchant dapat menutup potongan komisi pada simulasi ini. Tagihan saat ini: {formatPrice(startingDebt)}.</AlertDescription></Alert>}</CardContent></Card></div><Card><CardHeader><CardTitle>Aturan pemotongan saldo</CardTitle><CardDescription>Ringkasan perilaku sistem yang berlaku untuk admin dan merchant.</CardDescription></CardHeader><CardContent className="grid gap-4 text-sm md:grid-cols-3"><div className="rounded-xl border p-4"><p className="font-semibold">1. Transaksi selesai</p><p className="mt-1 text-muted-foreground">Komisi diterapkan hanya saat order berstatus selesai dan memakai nilai subtotal.</p></div><div className="rounded-xl border p-4"><p className="font-semibold">2. Saldo tersedia</p><p className="mt-1 text-muted-foreground">Saldo dipotong terlebih dahulu; saldo tidak pernah dibuat negatif.</p></div><div className="rounded-xl border p-4"><p className="font-semibold">3. Kekurangan menjadi tagihan</p><p className="mt-1 text-muted-foreground">Kekurangan dicatat sebagai debt dan dilunasi saat merchant melakukan top-up.</p></div></CardContent></Card></div></AdminLayout>;
}
