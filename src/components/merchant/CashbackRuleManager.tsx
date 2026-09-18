import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Badge } from '@/components/ui/badge';
import { Gift, Plus, Percent, Save, X } from 'lucide-react';
import { toast } from 'sonner';
import { formatPrice } from '@/lib/utils';

type Rule = {
  id: string;
  name: string;
  cashback_percent: number;
  min_order_amount: number;
  max_cashback: number | null;
  category: string | null;
  is_active: boolean;
  valid_from: string;
  valid_until: string | null;
};

const emptyForm = { name: '', cashback_percent: 2, min_order_amount: 0, max_cashback: '', category: '', valid_until: '' };

export function CashbackRuleManager({ merchantId }: { merchantId: string }) {
  const [rules, setRules] = useState<Rule[]>([]);
  const [form, setForm] = useState(emptyForm);
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase.from('cashback_rules').select('*').eq('merchant_id', merchantId).order('created_at', { ascending: false });
    if (error) toast.error('Gagal memuat cashback toko');
    setRules((data || []) as Rule[]);
    setLoading(false);
  }, [merchantId]);

  useEffect(() => { void load(); }, [load]);

  const save = async () => {
    const percent = Number(form.cashback_percent);
    const minimum = Number(form.min_order_amount);
    const maximum = form.max_cashback === '' ? null : Number(form.max_cashback);
    if (!form.name.trim()) return toast.error('Nama program wajib diisi');
    if (!Number.isFinite(percent) || percent <= 0 || percent > 50) return toast.error('Cashback harus 0,1–50%');
    if (!Number.isFinite(minimum) || minimum < 0) return toast.error('Minimum belanja tidak valid');
    if (maximum !== null && (!Number.isFinite(maximum) || maximum <= 0)) return toast.error('Batas cashback tidak valid');
    setSaving(true);
    const { error } = await supabase.from('cashback_rules').insert({
      merchant_id: merchantId,
      name: form.name.trim(),
      cashback_percent: percent,
      min_order_amount: minimum,
      max_cashback: maximum,
      category: form.category.trim() || null,
      valid_from: new Date().toISOString(),
      valid_until: form.valid_until ? new Date(`${form.valid_until}T23:59:59`).toISOString() : null,
      is_active: true,
    });
    setSaving(false);
    if (error) return toast.error(error.message || 'Gagal menyimpan program');
    toast.success('Program cashback toko dibuat');
    setForm(emptyForm); setOpen(false); await load();
  };

  const toggle = async (rule: Rule) => {
    const { error } = await supabase.from('cashback_rules').update({ is_active: !rule.is_active }).eq('id', rule.id).eq('merchant_id', merchantId);
    if (error) return toast.error('Gagal mengubah status program');
    await load();
  };

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between gap-3">
        <div><CardTitle className="text-base flex items-center gap-2"><Gift className="h-4 w-4 text-emerald-600" /> Cashback Toko</CardTitle><p className="text-xs text-muted-foreground mt-1">Berikan insentif setelah pesanan selesai; diproses server secara idempotent.</p></div>
        <Button size="sm" onClick={() => setOpen(v => !v)} className="gap-1"><Plus className="h-4 w-4" /> Buat</Button>
      </CardHeader>
      <CardContent className="space-y-4">
        {open && <div className="rounded-lg border bg-muted/30 p-4 space-y-3">
          <div className="flex justify-between items-center"><p className="font-medium text-sm">Program baru</p><Button variant="ghost" size="icon" onClick={() => setOpen(false)}><X className="h-4 w-4" /></Button></div>
          <div><Label>Nama program</Label><Input className="mt-1" placeholder="Cashback pelanggan setia" value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} /></div>
          <div className="grid grid-cols-2 gap-3"><div><Label>Cashback (%)</Label><Input className="mt-1" type="number" min="0.1" max="50" step="0.1" value={form.cashback_percent} onChange={e => setForm(f => ({ ...f, cashback_percent: Number(e.target.value) }))} /></div><div><Label>Min. belanja</Label><Input className="mt-1" type="number" min="0" value={form.min_order_amount} onChange={e => setForm(f => ({ ...f, min_order_amount: Number(e.target.value) }))} /></div></div>
          <div className="grid grid-cols-2 gap-3"><div><Label>Maks. cashback</Label><Input className="mt-1" type="number" min="1" placeholder="Opsional" value={form.max_cashback} onChange={e => setForm(f => ({ ...f, max_cashback: e.target.value }))} /></div><div><Label>Kategori produk</Label><Input className="mt-1" placeholder="Opsional" value={form.category} onChange={e => setForm(f => ({ ...f, category: e.target.value }))} /></div></div>
          <div><Label>Berlaku hingga</Label><Input className="mt-1" type="date" value={form.valid_until} onChange={e => setForm(f => ({ ...f, valid_until: e.target.value }))} /></div>
          <Button className="w-full gap-2" onClick={() => void save()} disabled={saving}><Save className="h-4 w-4" />{saving ? 'Menyimpan...' : 'Simpan program'}</Button>
        </div>}
        {loading ? <p className="text-sm text-muted-foreground">Memuat program...</p> : rules.length === 0 ? <div className="rounded-lg border border-dashed p-5 text-center text-sm text-muted-foreground">Belum ada cashback khusus toko.</div> : <div className="space-y-2">{rules.map(rule => <div key={rule.id} className="flex items-center justify-between rounded-lg border p-3"><div><p className="font-medium text-sm">{rule.name}</p><div className="flex flex-wrap gap-2 mt-1"><Badge variant="secondary"><Percent className="h-3 w-3 mr-1" />{rule.cashback_percent}%</Badge><span className="text-xs text-muted-foreground">Min. {formatPrice(rule.min_order_amount)}</span>{rule.max_cashback && <span className="text-xs text-muted-foreground">Maks. {formatPrice(rule.max_cashback)}</span>}</div></div><Switch checked={rule.is_active} onCheckedChange={() => void toggle(rule)} aria-label={`Aktifkan ${rule.name}`} /></div>)}</div>}
      </CardContent>
    </Card>
  );
}
