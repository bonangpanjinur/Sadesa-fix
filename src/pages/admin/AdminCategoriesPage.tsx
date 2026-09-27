import { useCallback, useEffect, useMemo, useState } from 'react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Switch } from '@/components/ui/switch';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Textarea } from '@/components/ui/textarea';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';
import {
  CheckCircle2,
  ChevronRight,
  CircleDot,
  FolderTree,
  GripVertical,
  Layers3,
  Loader2,
  Pencil,
  Plus,
  Search,
  Tags,
  Trash2,
} from 'lucide-react';

interface Category {
  id: string;
  name: string;
  slug: string;
  parent_id: string | null;
  icon: string | null;
  description: string | null;
  sort_order: number;
  is_active: boolean;
  created_at: string;
}

type StatusFilter = 'all' | 'active' | 'inactive';

export default function AdminCategoriesPage() {
  const { toast } = useToast();
  const [categories, setCategories] = useState<Category[]>([]);
  const [loading, setLoading] = useState(true);
  const [showDialog, setShowDialog] = useState(false);
  const [editingCategory, setEditingCategory] = useState<Category | null>(null);
  const [saving, setSaving] = useState(false);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [form, setForm] = useState({
    name: '',
    slug: '',
    parent_id: '',
    icon: '',
    description: '',
    is_active: true,
  });

  const fetchCategories = useCallback(async () => {
    try {
      const { data, error } = await supabase
        .from('categories')
        .select('*')
        .order('sort_order', { ascending: true });
      if (error) throw error;
      setCategories((data || []) as unknown as Category[]);
    } catch (error) {
      console.error('Error fetching categories:', error);
      toast({
        title: 'Gagal memuat kategori',
        description: 'Silakan coba lagi beberapa saat kemudian.',
        variant: 'destructive',
      });
    } finally {
      setLoading(false);
    }
  }, [toast]);

  useEffect(() => {
    fetchCategories();
  }, [fetchCategories]);

  const generateSlug = (name: string) => name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '');

  const categoryById = useMemo(
    () => new Map(categories.map((category) => [category.id, category])),
    [categories],
  );

  const filteredCategories = useMemo(() => {
    const normalizedSearch = search.trim().toLowerCase();
    const matches = categories.filter((category) => {
      const parentName = category.parent_id ? categoryById.get(category.parent_id)?.name || '' : '';
      const matchesSearch = !normalizedSearch
        || `${category.name} ${category.slug} ${parentName}`.toLowerCase().includes(normalizedSearch);
      const matchesStatus = statusFilter === 'all'
        || (statusFilter === 'active' && category.is_active)
        || (statusFilter === 'inactive' && !category.is_active);
      return matchesSearch && matchesStatus;
    });

    return [...matches].sort((a, b) => {
      // Keep each parent immediately above its children for easier scanning.
      if (a.parent_id === b.id) return 1;
      if (b.parent_id === a.id) return -1;
      if (a.parent_id === b.parent_id) return a.sort_order - b.sort_order || a.name.localeCompare(b.name);
      if (!a.parent_id && b.parent_id) return -1;
      if (a.parent_id && !b.parent_id) return 1;
      const aParent = a.parent_id ? categoryById.get(a.parent_id) : undefined;
      const bParent = b.parent_id ? categoryById.get(b.parent_id) : undefined;
      return (aParent?.sort_order || a.sort_order) - (bParent?.sort_order || b.sort_order)
        || a.name.localeCompare(b.name);
    });
  }, [categories, categoryById, search, statusFilter]);

  const topLevelCategories = categories.filter((category) => !category.parent_id);
  const activeCount = categories.filter((category) => category.is_active).length;
  const subcategoryCount = categories.filter((category) => category.parent_id).length;

  const handleOpenDialog = (category?: Category) => {
    if (category) {
      setEditingCategory(category);
      setForm({
        name: category.name,
        slug: category.slug,
        parent_id: category.parent_id || '',
        icon: category.icon || '',
        description: category.description || '',
        is_active: category.is_active,
      });
    } else {
      setEditingCategory(null);
      setForm({ name: '', slug: '', parent_id: '', icon: '', description: '', is_active: true });
    }
    setShowDialog(true);
  };

  const handleSave = async () => {
    if (!form.name.trim()) {
      toast({ title: 'Nama kategori wajib diisi', variant: 'destructive' });
      return;
    }

    setSaving(true);
    try {
      const slug = form.slug || generateSlug(form.name);
      const payload = {
        name: form.name.trim(),
        slug,
        parent_id: form.parent_id || null,
        icon: form.icon.trim() || null,
        description: form.description.trim() || null,
        is_active: form.is_active,
      };

      if (editingCategory) {
        const { error } = await supabase
          .from('categories')
          .update({ ...payload, updated_at: new Date().toISOString() })
          .eq('id', editingCategory.id);
        if (error) throw error;
        toast({ title: 'Kategori diperbarui' });
      } else {
        const maxOrder = Math.max(0, ...categories.map((category) => category.sort_order));
        const { error } = await supabase
          .from('categories')
          .insert({ ...payload, sort_order: maxOrder + 1 });
        if (error) throw error;
        toast({ title: 'Kategori ditambahkan' });
      }
      setShowDialog(false);
      fetchCategories();
    } catch (error: unknown) {
      console.error('Error saving category:', error);
      toast({
        title: 'Gagal menyimpan kategori',
        description: error instanceof Error ? error.message : 'Periksa kembali data kategori.',
        variant: 'destructive',
      });
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (category: Category) => {
    if (!confirm(`Hapus kategori "${category.name}"?`)) return;
    try {
      const { error } = await supabase.from('categories').delete().eq('id', category.id);
      if (error) throw error;
      toast({ title: 'Kategori dihapus' });
      fetchCategories();
    } catch (error) {
      console.error('Error deleting category:', error);
      toast({ title: 'Gagal menghapus kategori', variant: 'destructive' });
    }
  };

  const handleToggleActive = async (category: Category) => {
    try {
      const { error } = await supabase
        .from('categories')
        .update({ is_active: !category.is_active })
        .eq('id', category.id);
      if (error) throw error;
      setCategories((current) => current.map((item) => (
        item.id === category.id ? { ...item, is_active: !item.is_active } : item
      )));
      toast({ title: category.is_active ? 'Kategori dinonaktifkan' : 'Kategori diaktifkan' });
    } catch (error) {
      console.error('Error toggling category:', error);
      toast({ title: 'Gagal mengubah status kategori', variant: 'destructive' });
    }
  };

  return (
    <AdminLayout title="Kategori Produk" subtitle="Kelola struktur kategori dan subkategori produk">
      <div className="space-y-6">
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <Card className="border-border/70 shadow-sm">
            <CardContent className="flex items-center gap-4 p-5">
              <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-primary/10 text-primary"><Layers3 className="h-5 w-5" /></div>
              <div><p className="text-sm text-muted-foreground">Total kategori</p><p className="text-2xl font-bold tracking-tight">{categories.length}</p></div>
            </CardContent>
          </Card>
          <Card className="border-border/70 shadow-sm">
            <CardContent className="flex items-center gap-4 p-5">
              <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-emerald-100 text-emerald-700"><FolderTree className="h-5 w-5" /></div>
              <div><p className="text-sm text-muted-foreground">Kategori utama</p><p className="text-2xl font-bold tracking-tight">{topLevelCategories.length}</p></div>
            </CardContent>
          </Card>
          <Card className="border-border/70 shadow-sm">
            <CardContent className="flex items-center gap-4 p-5">
              <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-amber-100 text-amber-700"><Tags className="h-5 w-5" /></div>
              <div><p className="text-sm text-muted-foreground">Subkategori</p><p className="text-2xl font-bold tracking-tight">{subcategoryCount}</p></div>
            </CardContent>
          </Card>
          <Card className="border-border/70 shadow-sm">
            <CardContent className="flex items-center gap-4 p-5">
              <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-sky-100 text-sky-700"><CheckCircle2 className="h-5 w-5" /></div>
              <div><p className="text-sm text-muted-foreground">Kategori aktif</p><p className="text-2xl font-bold tracking-tight">{activeCount}<span className="ml-1 text-sm font-normal text-muted-foreground">/ {categories.length}</span></p></div>
            </CardContent>
          </Card>
        </div>

        <Card className="overflow-hidden border-border/70 shadow-sm">
          <CardHeader className="border-b bg-muted/20 px-5 py-5 sm:px-6">
            <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
              <div>
                <CardTitle className="flex items-center gap-2 text-xl"><Tags className="h-5 w-5 text-primary" />Daftar kategori</CardTitle>
                <p className="mt-1 text-sm text-muted-foreground">Susun kategori utama dan subkategori agar katalog lebih mudah ditemukan.</p>
              </div>
              <Button onClick={() => handleOpenDialog()} className="w-full gap-2 sm:w-auto"><Plus className="h-4 w-4" />Tambah kategori</Button>
            </div>
          </CardHeader>
          <CardContent className="p-0">
            <div className="flex flex-col gap-3 border-b px-5 py-4 sm:flex-row sm:items-center sm:px-6">
              <div className="relative flex-1">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                <Input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Cari nama, slug, atau kategori induk..." className="h-10 pl-9" />
              </div>
              <div className="flex rounded-lg border bg-background p-1">
                {(['all', 'active', 'inactive'] as StatusFilter[]).map((filter) => (
                  <Button key={filter} type="button" variant={statusFilter === filter ? 'secondary' : 'ghost'} size="sm" onClick={() => setStatusFilter(filter)} className="h-8 px-3 text-xs">
                    {filter === 'all' ? 'Semua' : filter === 'active' ? 'Aktif' : 'Nonaktif'}
                  </Button>
                ))}
              </div>
            </div>

            {loading ? (
              <div className="flex items-center justify-center py-16"><Loader2 className="h-7 w-7 animate-spin text-primary" /></div>
            ) : categories.length === 0 ? (
              <div className="px-6 py-16 text-center"><FolderTree className="mx-auto h-10 w-10 text-muted-foreground/50" /><h3 className="mt-3 font-semibold">Belum ada kategori</h3><p className="mt-1 text-sm text-muted-foreground">Tambahkan kategori pertama untuk mulai mengelompokkan produk.</p><Button onClick={() => handleOpenDialog()} className="mt-5 gap-2"><Plus className="h-4 w-4" />Tambah kategori</Button></div>
            ) : filteredCategories.length === 0 ? (
              <div className="px-6 py-16 text-center"><Search className="mx-auto h-10 w-10 text-muted-foreground/50" /><h3 className="mt-3 font-semibold">Kategori tidak ditemukan</h3><p className="mt-1 text-sm text-muted-foreground">Coba ubah kata kunci atau filter status.</p></div>
            ) : (
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader className="bg-muted/15">
                    <TableRow className="hover:bg-transparent">
                      <TableHead className="w-12 pl-6 text-xs uppercase tracking-wide text-muted-foreground">#</TableHead>
                      <TableHead className="w-16 text-xs uppercase tracking-wide text-muted-foreground">Icon</TableHead>
                      <TableHead className="min-w-[240px] text-xs uppercase tracking-wide text-muted-foreground">Kategori</TableHead>
                      <TableHead className="min-w-[150px] text-xs uppercase tracking-wide text-muted-foreground">Induk</TableHead>
                      <TableHead className="min-w-[170px] text-xs uppercase tracking-wide text-muted-foreground">Slug</TableHead>
                      <TableHead className="text-xs uppercase tracking-wide text-muted-foreground">Status</TableHead>
                      <TableHead className="pr-6 text-right text-xs uppercase tracking-wide text-muted-foreground">Aksi</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {filteredCategories.map((category, index) => {
                      const parent = category.parent_id ? categoryById.get(category.parent_id) : null;
                      return (
                        <TableRow key={category.id} className={category.parent_id ? 'bg-muted/[0.08]' : ''}>
                          <TableCell className="pl-6 text-muted-foreground"><div className="flex items-center gap-2"><GripVertical className="h-4 w-4 cursor-grab text-muted-foreground/40" /><span className="text-xs">{String(index + 1).padStart(2, '0')}</span></div></TableCell>
                          <TableCell><span className="flex h-9 w-9 items-center justify-center rounded-xl bg-muted/70 text-xl">{category.icon || '📦'}</span></TableCell>
                          <TableCell>
                            <div className={`flex items-center gap-2 ${category.parent_id ? 'pl-5' : ''}`}>
                              {category.parent_id ? <ChevronRight className="h-4 w-4 shrink-0 text-primary" /> : <CircleDot className="h-3.5 w-3.5 shrink-0 fill-primary text-primary" />}
                              <div className="min-w-0"><p className="truncate font-medium">{category.name}</p>{category.description && <p className="mt-0.5 max-w-[300px] truncate text-xs text-muted-foreground">{category.description}</p>}</div>
                              {category.parent_id && <Badge variant="secondary" className="shrink-0 rounded-full px-2 py-0.5 text-[10px] font-medium">Subkategori</Badge>}
                            </div>
                          </TableCell>
                          <TableCell className="text-sm text-muted-foreground">{parent ? <span className="inline-flex items-center gap-1.5"><span>{parent.icon || '📦'}</span>{parent.name}</span> : <span className="text-muted-foreground/50">Kategori utama</span>}</TableCell>
                          <TableCell><code className="rounded bg-muted px-2 py-1 text-xs text-muted-foreground">{category.slug}</code></TableCell>
                          <TableCell><div className="flex items-center gap-2"><Switch checked={category.is_active} onCheckedChange={() => handleToggleActive(category)} /><span className={`hidden text-xs font-medium sm:inline ${category.is_active ? 'text-emerald-600' : 'text-muted-foreground'}`}>{category.is_active ? 'Aktif' : 'Nonaktif'}</span></div></TableCell>
                          <TableCell className="pr-6"><div className="flex justify-end gap-1"><Button variant="ghost" size="icon" aria-label={`Edit ${category.name}`} onClick={() => handleOpenDialog(category)} className="h-8 w-8"><Pencil className="h-4 w-4" /></Button><Button variant="ghost" size="icon" aria-label={`Hapus ${category.name}`} className="h-8 w-8 text-destructive hover:bg-destructive/10 hover:text-destructive" onClick={() => handleDelete(category)}><Trash2 className="h-4 w-4" /></Button></div></TableCell>
                        </TableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              </div>
            )}
            {!loading && categories.length > 0 && <div className="border-t bg-muted/10 px-5 py-3 text-xs text-muted-foreground sm:px-6">Menampilkan <span className="font-semibold text-foreground">{filteredCategories.length}</span> dari <span className="font-semibold text-foreground">{categories.length}</span> kategori</div>}
          </CardContent>
        </Card>
      </div>

      <Dialog open={showDialog} onOpenChange={setShowDialog}>
        <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader><DialogTitle>{editingCategory ? 'Edit kategori' : 'Tambah kategori'}</DialogTitle><DialogDescription>{editingCategory ? 'Perbarui informasi kategori dan tampilannya di katalog.' : 'Buat kategori utama atau subkategori baru untuk produk.'}</DialogDescription></DialogHeader>
          <div className="space-y-5 py-2">
            <div className="grid gap-4 sm:grid-cols-[1fr_96px]">
              <div className="space-y-2"><Label htmlFor="category-name">Nama kategori <span className="text-destructive">*</span></Label><Input id="category-name" value={form.name} onChange={(event) => setForm((prev) => ({ ...prev, name: event.target.value, slug: prev.slug || generateSlug(event.target.value) }))} placeholder="Contoh: Makanan Ringan" autoFocus /></div>
              <div className="space-y-2"><Label htmlFor="category-icon">Icon</Label><Input id="category-icon" value={form.icon} onChange={(event) => setForm((prev) => ({ ...prev, icon: event.target.value }))} placeholder="🍔" className="text-center text-xl" maxLength={4} /></div>
            </div>
            <div className="space-y-2"><Label htmlFor="category-parent">Kategori induk</Label><select id="category-parent" value={form.parent_id} onChange={(event) => setForm((prev) => ({ ...prev, parent_id: event.target.value }))} className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus:outline-none focus:ring-2 focus:ring-ring"><option value="">Kategori utama (tanpa induk)</option>{categories.filter((category) => !category.parent_id && category.id !== editingCategory?.id).map((category) => <option key={category.id} value={category.id}>{category.icon || '📦'} {category.name}</option>)}</select><p className="text-xs text-muted-foreground">Pilih kategori induk jika item ini merupakan subkategori.</p></div>
            <div className="space-y-2"><Label htmlFor="category-slug">Slug</Label><Input id="category-slug" value={form.slug} onChange={(event) => setForm((prev) => ({ ...prev, slug: event.target.value }))} placeholder="Otomatis dari nama" /><p className="text-xs text-muted-foreground">Dipakai untuk URL dan identifikasi kategori.</p></div>
            <div className="space-y-2"><Label htmlFor="category-description">Deskripsi</Label><Textarea id="category-description" value={form.description} onChange={(event) => setForm((prev) => ({ ...prev, description: event.target.value }))} placeholder="Jelaskan isi kategori secara singkat..." rows={3} /></div>
            <div className="flex items-center justify-between rounded-xl border bg-muted/20 px-4 py-3"><div><Label htmlFor="category-active" className="cursor-pointer">Tampilkan di katalog</Label><p className="mt-0.5 text-xs text-muted-foreground">Kategori aktif dapat dipilih saat mengelola produk.</p></div><Switch id="category-active" checked={form.is_active} onCheckedChange={(checked) => setForm((prev) => ({ ...prev, is_active: checked }))} /></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setShowDialog(false)} disabled={saving}>Batal</Button><Button onClick={handleSave} disabled={saving} className="gap-2">{saving && <Loader2 className="h-4 w-4 animate-spin" />}{editingCategory ? 'Simpan perubahan' : 'Tambah kategori'}</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </AdminLayout>
  );
}
