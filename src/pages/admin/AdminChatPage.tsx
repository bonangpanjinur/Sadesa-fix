import { useEffect, useMemo, useState } from 'react';
import { MessageCircle, Store, Truck, Search, ArrowLeft } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { ConversationView } from '@/components/chat/ConversationView';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Button } from '@/components/ui/button';

type TargetRole = 'merchant' | 'courier';
type ChatTarget = { id: string; user_id: string; name: string; role: TargetRole; detail?: string };

export default function AdminChatPage() {
  const [targets, setTargets] = useState<ChatTarget[]>([]);
  const [selected, setSelected] = useState<ChatTarget | null>(null);
  const [search, setSearch] = useState('');
  const [tab, setTab] = useState<TargetRole>('merchant');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    const loadTargets = async () => {
      setLoading(true);
      const [{ data: merchants, error: merchantsError }, { data: couriers, error: couriersError }] = await Promise.all([
        supabase.from('merchants').select('id, user_id, name, status').not('user_id', 'is', null).order('name'),
        supabase.from('couriers').select('id, user_id, name, status, registration_status').not('user_id', 'is', null).order('name'),
      ]);
      if (!active) return;
      if (merchantsError || couriersError) setError('Daftar merchant dan kurir belum dapat dimuat.');
      setTargets([
        ...(merchants || []).filter((item) => item.user_id && item.status === 'ACTIVE').map((item) => ({ id: item.id, user_id: item.user_id!, name: item.name || 'Merchant tanpa nama', role: 'merchant' as const, detail: 'Merchant aktif' })),
        ...(couriers || []).filter((item) => item.user_id && item.registration_status === 'APPROVED').map((item) => ({ id: item.id, user_id: item.user_id!, name: item.name || 'Kurir tanpa nama', role: 'courier' as const, detail: item.status === 'ACTIVE' ? 'Kurir aktif' : 'Kurir terdaftar' })),
      ]);
      setLoading(false);
    };
    void loadTargets();
    return () => { active = false; };
  }, []);

  const visibleTargets = useMemo(() => targets.filter((target) => target.role === tab && target.name.toLowerCase().includes(search.trim().toLowerCase())), [targets, tab, search]);

  if (selected) {
    return (
      <AdminLayout title="Chat Admin" subtitle={`Percakapan langsung dengan ${selected.name}`}>
        <div className="mb-4 flex items-center gap-3">
          <Button variant="outline" size="sm" onClick={() => setSelected(null)}><ArrowLeft className="mr-2 h-4 w-4" /> Kembali ke daftar</Button>
          <Badge variant="secondary">{selected.role === 'merchant' ? 'Merchant' : 'Kurir'}</Badge>
        </div>
        <div className="h-[calc(100vh-220px)] min-h-[520px]">
          <ConversationView
            title={selected.name}
            subtitle="Chat langsung dari admin"
            contextType="direct"
            conversationType={selected.role === 'merchant' ? 'admin_merchant' : 'admin_courier'}
            adminTargetUserId={selected.user_id}
            adminTargetRole={selected.role}
            receiverId={selected.user_id}
            onClose={() => setSelected(null)}
          />
        </div>
      </AdminLayout>
    );
  }

  return (
    <AdminLayout title="Chat Admin" subtitle="Hubungi merchant atau kurir tanpa menunggu percakapan dimulai">
      <Card>
        <CardContent className="p-4 sm:p-6">
          <div className="mb-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div><h2 className="text-lg font-semibold">Mulai percakapan</h2><p className="text-sm text-muted-foreground">Pilih tujuan chat. Percakapan akan dibuat otomatis saat Anda membukanya.</p></div>
            <div className="relative w-full sm:max-w-xs"><Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" /><Input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Cari nama…" className="pl-9" /></div>
          </div>
          {error && <p className="mb-4 text-sm text-destructive">{error}</p>}
          <Tabs value={tab} onValueChange={(value) => setTab(value as TargetRole)}>
            <TabsList className="mb-4 grid w-full max-w-md grid-cols-2"><TabsTrigger value="merchant"><Store className="mr-2 h-4 w-4" /> Merchant ({targets.filter((item) => item.role === 'merchant').length})</TabsTrigger><TabsTrigger value="courier"><Truck className="mr-2 h-4 w-4" /> Kurir ({targets.filter((item) => item.role === 'courier').length})</TabsTrigger></TabsList>
            <TabsContent value={tab}>
              {loading ? <div className="py-12 text-center text-sm text-muted-foreground">Memuat daftar tujuan chat…</div> : visibleTargets.length === 0 ? <div className="flex flex-col items-center py-12 text-center text-muted-foreground"><MessageCircle className="mb-3 h-10 w-10 opacity-30" /><p>Tidak ada {tab === 'merchant' ? 'merchant' : 'kurir'} yang ditemukan.</p></div> : <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">{visibleTargets.map((target) => <button key={`${target.role}-${target.id}`} type="button" onClick={() => setSelected(target)} className="text-left"><Card className="transition hover:border-primary hover:bg-accent/40"><CardContent className="flex items-center gap-3 p-4"><div className="rounded-full bg-primary/10 p-2 text-primary">{target.role === 'merchant' ? <Store className="h-5 w-5" /> : <Truck className="h-5 w-5" />}</div><div className="min-w-0 flex-1"><p className="truncate font-medium">{target.name}</p><p className="text-xs text-muted-foreground">{target.detail}</p></div><MessageCircle className="h-4 w-4 text-muted-foreground" /></CardContent></Card></button>)}</div>}
            </TabsContent>
          </Tabs>
        </CardContent>
      </Card>
    </AdminLayout>
  );
}
