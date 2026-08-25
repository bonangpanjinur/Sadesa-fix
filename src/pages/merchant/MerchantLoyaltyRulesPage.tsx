import { useCallback, useEffect, useState } from 'react';
import { Gift, Plus, RefreshCw } from 'lucide-react';
import { MerchantLayout } from '@/components/merchant/MerchantLayout';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { supabase } from '@/integrations/supabase/client';
import { usePOS } from '@/contexts/POSContext';
import { toast } from 'sonner';

interface LoyaltyRule { id: string; name: string; rule_type: string; min_spend: number; points_per_currency: number; points_value: number; tier_name: string | null; expires_after_days: number | null; is_active: boolean; priority: number; }
const TYPES = ['earn', 'redeem', 'tier', 'expiry', 'category_bonus'];

export default function MerchantLoyaltyRulesPage() {
  const { tenant, loading: posLoading } = usePOS();
  const [rules, setRules] = useState<LoyaltyRule[]>([]);
  const [loading, setLoading] = useState(false);
  const [form, setForm] = useState({ name: '', type: 'earn', minSpend: '0', pointsPerCurrency: '0.001', pointsValue: '0', tierName: '', expiresAfterDays: '', priority: '0' });

  const load = useCallback(async () => {
    if (!tenant) return;
    setLoading(true);
    const { data, error } = await supabase.from('pos_loyalty_rules').select('id, name, rule_type, min_spend, points_per_currency, points_value, tier_name, expires_after_days, is_active, priority').eq('tenant_id', tenant.id).order('priority', { ascending: false });
    if (error) toast.error('Gagal memuat rule loyalty');
    setRules((data ?? []) as LoyaltyRule[]); setLoading(false);
  }, [tenant]);
  useEffect(() => { void load(); }, [load]);

  const create = async () => {
    if (!tenant || !form.name.trim()) { toast.error('Nama rule wajib diisi'); return; }
    setLoading(true);
    try {
      const { error } = await supabase.from('pos_loyalty_rules').insert({ tenant_id: tenant.id, name: form.name.trim(), rule_type: form.type, min_spend: Number(form.minSpend) || 0, points_per_currency: Number(form.pointsPerCurrency) || 0, points_value: Number(form.pointsValue) || 0, tier_name: form.tierName.trim() || null, expires_after_days: form.expiresAfterDays ? Number(form.expiresAfterDays) : null, priority: Number(form.priority) || 0 });
      if (error) throw error;
      toast.success('Rule loyalty berhasil dibuat'); setForm({ name: '', type: 'earn', minSpend: '0', pointsPerCurrency: '0.001', pointsValue: '0', tierName: '', expiresAfterDays: '', priority: '0' }); await load();
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Gagal membuat rule'); } finally { setLoading(false); }
  };

  if (posLoading) return <MerchantLayout title="Loyalty Rules"><div className="p-6">Memuat...</div></MerchantLayout>;
  return <MerchantLayout title="Loyalty Rules Engine" subtitle="Atur poin belanja, redeem, tier, expiry, dan bonus kategori"><div className="space-y-6"><Card><CardHeader><CardTitle className="flex items-center gap-2"><Plus className="h-5 w-5" />Tambah Rule Loyalty</CardTitle></CardHeader><CardContent className="grid gap-4 md:grid-cols-2"><div><Label>Nama Rule</Label><Input className="mt-1" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="Poin belanja member" /></div><div><Label>Tipe</Label><Select value={form.type} onValueChange={(v) => setForm({ ...form, type: v })}><SelectTrigger className="mt-1"><SelectValue /></SelectTrigger><SelectContent>{TYPES.map((type) => <SelectItem key={type} value={type}>{type}</SelectItem>)}</SelectContent></Select></div><div><Label>Minimum belanja</Label><Input className="mt-1" type="number" min="0" value={form.minSpend} onChange={(e) => setForm({ ...form, minSpend: e.target.value })} /></div><div><Label>Poin per mata uang</Label><Input className="mt-1" type="number" min="0" step="0.0001" value={form.pointsPerCurrency} onChange={(e) => setForm({ ...form, pointsPerCurrency: e.target.value })} /></div><div><Label>Nilai redeem per poin</Label><Input className="mt-1" type="number" min="0" value={form.pointsValue} onChange={(e) => setForm({ ...form, pointsValue: e.target.value })} /></div><div><Label>Nama tier (opsional)</Label><Input className="mt-1" value={form.tierName} onChange={(e) => setForm({ ...form, tierName: e.target.value })} /></div><div><Label>Expiry poin (hari)</Label><Input className="mt-1" type="number" min="1" value={form.expiresAfterDays} onChange={(e) => setForm({ ...form, expiresAfterDays: e.target.value })} /></div><div><Label>Prioritas</Label><Input className="mt-1" type="number" value={form.priority} onChange={(e) => setForm({ ...form, priority: e.target.value })} /></div><div className="md:col-span-2"><Button onClick={() => void create()} disabled={loading}><Plus className="h-4 w-4 mr-2" />Simpan Rule</Button></div></CardContent></Card><Card><CardHeader><CardTitle className="flex items-center justify-between"><span className="flex items-center gap-2"><Gift className="h-5 w-5" />Rule Aktif</span><Button size="sm" variant="outline" onClick={() => void load()}><RefreshCw className="h-4 w-4" /></Button></CardTitle></CardHeader><CardContent>{rules.length === 0 ? <p className="text-sm text-muted-foreground">Belum ada rule loyalty.</p> : <div className="space-y-2">{rules.map((rule) => <div key={rule.id} className="flex flex-wrap items-center gap-3 border rounded-lg p-3"><div className="flex-1"><p className="font-medium">{rule.name}</p><p className="text-xs text-muted-foreground">Min. {rule.min_spend.toLocaleString('id-ID')} · {rule.expires_after_days ? `Expiry ${rule.expires_after_days} hari` : 'Tanpa expiry'}</p></div><Badge variant="outline">{rule.rule_type}</Badge>{rule.tier_name && <Badge variant="secondary">{rule.tier_name}</Badge>}<Badge variant={rule.is_active ? 'default' : 'secondary'}>{rule.is_active ? 'Aktif' : 'Nonaktif'}</Badge></div>)}</div>}</CardContent></Card></div></MerchantLayout>;
}
