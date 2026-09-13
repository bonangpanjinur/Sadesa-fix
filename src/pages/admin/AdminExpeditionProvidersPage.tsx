import { useCallback, useEffect, useState } from 'react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Switch } from '@/components/ui/switch';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { supabase } from '@/integrations/supabase/client';
import { validateUploadFile } from '@/lib/fileValidation';
import { toast } from 'sonner';
import { ExternalLink, ImagePlus, Link2, Loader2, Pencil, Plus, Radio, Trash2, Truck } from 'lucide-react';

interface ExpeditionProvider {
  id: string;
  name: string;
  logo_url: string | null;
  tracking_website: string;
  is_active: boolean;
  sort_order: number;
  created_at: string;
}

const emptyForm = { name: '', logo_url: '', tracking_website: '', is_active: true, sort_order: '0' };

export default function AdminExpeditionProvidersPage() {
  const [providers, setProviders] = useState<ExpeditionProvider[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing] = useState<ExpeditionProvider | null>(null);
  const [form, setForm] = useState(emptyForm);

  const fetchProviders = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from('expedition_providers')
      .select('id, name, logo_url, tracking_website, is_active, sort_order, created_at')
      .order('sort_order', { ascending: true })
      .order('name', { ascending: true });
    if (error) toast.error(`Gagal memuat ekspedisi: ${error.message}`);
    else setProviders((data || []) as unknown as ExpeditionProvider[]);
    setLoading(false);
  }, []);

  useEffect(() => { fetchProviders(); }, [fetchProviders]);

  const openCreate = () => {
    setEditing(null);
    setForm(emptyForm);
    setDialogOpen(true);
  };

  const openEdit = (provider: ExpeditionProvider) => {
    setEditing(provider);
    setForm({
      name: provider.name,
      logo_url: provider.logo_url || '',
      tracking_website: provider.tracking_website,
      is_active: provider.is_active,
      sort_order: String(provider.sort_order),
    });
    setDialogOpen(true);
  };

  const uploadLogo = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    const validation = validateUploadFile(file);
    if (validation.valid === false) { toast.error(validation.error); return; }
    setUploading(true);
    try {
      const path = `providers/${crypto.randomUUID()}.${validation.extension}`;
      const { error } = await supabase.storage.from('expedition-logos').upload(path, file, { upsert: false });
      if (error) throw error;
      const { data } = supabase.storage.from('expedition-logos').getPublicUrl(path);
      setForm((current) => ({ ...current, logo_url: data.publicUrl }));
      toast.success('Logo berhasil diupload');
    } catch (error: unknown) {
      toast.error(error instanceof Error ? error.message : 'Gagal upload logo');
    } finally {
      setUploading(false);
    }
  };

  const saveProvider = async () => {
    const name = form.name.trim();
    const website = form.tracking_website.trim();
    if (name.length < 2) { toast.error('Nama ekspedisi minimal 2 karakter'); return; }
    if (!/^https?:\/\//i.test(website)) { toast.error('Website harus diawali http:// atau https://'); return; }
    setSaving(true);
    try {
      const payload = {
        name,
        logo_url: form.logo_url.trim() || null,
        tracking_website: website,
        is_active: form.is_active,
        sort_order: Number(form.sort_order) || 0,
        updated_at: new Date().toISOString(),
      };
      const result = editing
        ? await supabase.from('expedition_providers').update(payload).eq('id', editing.id)
        : await supabase.from('expedition_providers').insert(payload);
      if (result.error) throw result.error;
      toast.success(editing ? 'Ekspedisi diperbarui' : 'Ekspedisi ditambahkan');
      setDialogOpen(false);
      await fetchProviders();
    } catch (error: unknown) {
      toast.error(error instanceof Error ? error.message : 'Gagal menyimpan ekspedisi');
    } finally {
      setSaving(false);
    }
  };

  const toggleProvider = async (provider: ExpeditionProvider) => {
    const { error } = await supabase.from('expedition_providers').update({ is_active: !provider.is_active }).eq('id', provider.id);
    if (error) toast.error(error.message);
    else fetchProviders();
  };

  const deleteProvider = async (provider: ExpeditionProvider) => {
    if (!confirm(`Hapus ekspedisi "${provider.name}"? Data order lama tetap aman karena memakai snapshot.`)) return;
    const { error } = await supabase.from('expedition_providers').delete().eq('id', provider.id);
    if (error) toast.error(error.message);
    else { toast.success('Ekspedisi dihapus'); fetchProviders(); }
  };

  return (
    <AdminLayout title="Master Ekspedisi" subtitle="Kelola nama, logo, dan website tracking resmi ekspedisi">
      <div className="space-y-6">
        <Card className="border-primary/20 bg-primary/[0.03]">
          <CardContent className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-start gap-3">
              <div className="rounded-lg bg-primary/10 p-2 text-primary"><Truck className="h-5 w-5" /></div>
              <div>
                <p className="font-medium">Satu sumber data untuk semua ekspedisi</p>
                <p className="text-sm text-muted-foreground">Pedagang memilih dari daftar ini. Pembeli melihat logo dan dapat membuka website resmi yang Anda tetapkan.</p>
              </div>
            </div>
            <Button onClick={openCreate} className="shrink-0"><Plus className="mr-2 h-4 w-4" />Tambah Ekspedisi</Button>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2"><Radio className="h-5 w-5" />Daftar Ekspedisi ({providers.length})</CardTitle></CardHeader>
          <CardContent>
            {loading ? <div className="flex justify-center py-12"><Loader2 className="h-6 w-6 animate-spin text-primary" /></div> : providers.length === 0 ? (
              <div className="py-12 text-center text-muted-foreground"><Truck className="mx-auto mb-3 h-10 w-10 opacity-30" /><p>Belum ada master ekspedisi.</p><Button className="mt-4" onClick={openCreate}>Tambah Ekspedisi Pertama</Button></div>
            ) : (
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader><TableRow><TableHead>Ekspedisi</TableHead><TableHead>Website Tracking</TableHead><TableHead>Urutan</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Aksi</TableHead></TableRow></TableHeader>
                  <TableBody>{providers.map((provider) => (
                    <TableRow key={provider.id}>
                      <TableCell><div className="flex items-center gap-3"><div className="flex h-11 w-11 items-center justify-center overflow-hidden rounded-lg border bg-muted">{provider.logo_url ? <img src={provider.logo_url} alt={`Logo ${provider.name}`} className="h-full w-full object-contain" /> : <Truck className="h-5 w-5 text-muted-foreground" />}</div><span className="font-medium">{provider.name}</span></div></TableCell>
                      <TableCell><a href={provider.tracking_website} target="_blank" rel="noreferrer" className="inline-flex max-w-[280px] items-center gap-1 truncate text-sm text-primary hover:underline"><Link2 className="h-3.5 w-3.5 shrink-0" />{provider.tracking_website}<ExternalLink className="h-3.5 w-3.5 shrink-0" /></a></TableCell>
                      <TableCell>{provider.sort_order}</TableCell>
                      <TableCell><div className="flex items-center gap-2"><Switch checked={provider.is_active} onCheckedChange={() => toggleProvider(provider)} aria-label={`Aktifkan ${provider.name}`} /><Badge variant={provider.is_active ? 'default' : 'secondary'}>{provider.is_active ? 'Aktif' : 'Nonaktif'}</Badge></div></TableCell>
                      <TableCell><div className="flex justify-end gap-1"><Button size="sm" variant="ghost" onClick={() => openEdit(provider)} aria-label={`Edit ${provider.name}`}><Pencil className="h-4 w-4" /></Button><Button size="sm" variant="ghost" className="text-destructive" onClick={() => deleteProvider(provider)} aria-label={`Hapus ${provider.name}`}><Trash2 className="h-4 w-4" /></Button></div></TableCell>
                    </TableRow>
                  ))}</TableBody>
                </Table>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="w-[calc(100%-1rem)] max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader><DialogTitle>{editing ? 'Edit Ekspedisi' : 'Tambah Ekspedisi'}</DialogTitle><DialogDescription>Data ini akan menjadi pilihan pedagang dan informasi tracking pembeli.</DialogDescription></DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-2"><Label htmlFor="provider-name">Nama ekspedisi *</Label><Input id="provider-name" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="JNE, J&T Express, SiCepat" maxLength={120} /></div>
            <div className="space-y-2"><Label>Logo ekspedisi</Label><div className="flex items-center gap-3"><div className="flex h-16 w-16 items-center justify-center overflow-hidden rounded-lg border bg-muted">{form.logo_url ? <img src={form.logo_url} alt="Preview logo" className="h-full w-full object-contain" /> : <ImagePlus className="h-6 w-6 text-muted-foreground" />}</div><div><Button type="button" variant="outline" asChild disabled={uploading}><label className="cursor-pointer">{uploading ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <ImagePlus className="mr-2 h-4 w-4" />}Upload Logo<input type="file" accept="image/png,image/jpeg,image/webp,image/svg+xml" className="hidden" onChange={uploadLogo} /></label></Button><p className="mt-1 text-xs text-muted-foreground">PNG, JPG, WEBP, SVG. Maksimal 2 MB.</p></div></div><Input value={form.logo_url} onChange={(e) => setForm({ ...form, logo_url: e.target.value })} placeholder="Atau masukkan URL logo" /></div>
            <div className="space-y-2"><Label htmlFor="tracking-website">Website tracking resmi *</Label><Input id="tracking-website" type="url" value={form.tracking_website} onChange={(e) => setForm({ ...form, tracking_website: e.target.value })} placeholder="https://website-resmi-ekspedisi.com/track" /></div>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2"><div className="space-y-2"><Label htmlFor="sort-order">Urutan tampil</Label><Input id="sort-order" type="number" min="0" value={form.sort_order} onChange={(e) => setForm({ ...form, sort_order: e.target.value })} /></div><div className="flex items-center gap-3 pt-7"><Switch checked={form.is_active} onCheckedChange={(value) => setForm({ ...form, is_active: value })} /><Label>Aktif untuk pedagang</Label></div></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setDialogOpen(false)}>Batal</Button><Button onClick={saveProvider} disabled={saving || uploading}>{saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}{saving ? 'Menyimpan...' : 'Simpan Ekspedisi'}</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </AdminLayout>
  );
}
