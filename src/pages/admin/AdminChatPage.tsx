import { useEffect, useMemo, useState } from 'react';
import { MessageCircle, Store, Truck, Search, ArrowLeft, UserRound } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { ConversationView } from '@/components/chat/ConversationView';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Button } from '@/components/ui/button';
import { useAuth } from '@/contexts/AuthContext';
import { useSearchParams } from 'react-router-dom';

type TargetRole = 'merchant' | 'courier' | 'buyer';
type ChatTarget = { id: string; user_id: string; name: string; role: TargetRole; detail?: string };

export default function AdminChatPage() {
  const { user } = useAuth();
  const [searchParams] = useSearchParams();
  const [targets, setTargets] = useState<ChatTarget[]>([]);
  const [selected, setSelected] = useState<ChatTarget | null>(null);
  const [search, setSearch] = useState('');
  const [tab, setTab] = useState<TargetRole>('buyer');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    if (!user) return () => { active = false; };
    const loadTargets = async () => {
      setLoading(true);
      const [{ data: profiles, error: profilesError }, { data: roles, error: rolesError }] = await Promise.all([
        supabase.from('profiles').select('id, user_id, full_name, phone').order('full_name'),
        supabase.from('user_roles').select('user_id, role'),
      ]);
      if (!active) return;
      if (profilesError || rolesError) setError('Daftar pengguna belum dapat dimuat.');
      const roleMap = new Map<string, string[]>();
      (roles || []).forEach((item) => roleMap.set(item.user_id, [...(roleMap.get(item.user_id) || []), item.role]));
      const nextTargets = (profiles || []).filter((item) => item.user_id && item.user_id !== user.id && !(roleMap.get(item.user_id!) || []).includes('admin')).map((item) => {
        const userRoles = roleMap.get(item.user_id!) || [];
        const role: TargetRole = userRoles.includes('merchant') ? 'merchant' : userRoles.includes('courier') ? 'courier' : 'buyer';
        return { id: item.id, user_id: item.user_id!, name: item.full_name || 'Pengguna tanpa nama', role, detail: item.phone || 'Pengguna aktif' };
      });
      setTargets(nextTargets);
      const conversationId = searchParams.get('conversationId');
      const targetUserId = searchParams.get('userId');
      if (conversationId) {
        const { data: conversation } = await supabase.from('chat_conversations').select('direct_target_user_id').eq('id', conversationId).maybeSingle();
        if (!active) return;
        const target = nextTargets.find((item) => item.user_id === conversation?.direct_target_user_id);
        if (target) { setTab(target.role); setSelected(target); }
      } else if (targetUserId) {
        const target = nextTargets.find((item) => item.user_id === targetUserId);
        if (target) { setTab(target.role); setSelected(target); }
      }
      setLoading(false);
    };
    void loadTargets();
    return () => { active = false; };
  }, [searchParams, user]);

  const visibleTargets = useMemo(() => targets.filter((target) => target.role === tab && target.name.toLowerCase().includes(search.trim().toLowerCase())), [targets, tab, search]);
  const roleLabel = (role: TargetRole) => role === 'merchant' ? 'Merchant' : role === 'courier' ? 'Kurir' : 'Pengguna';

  if (selected) {
    return <AdminLayout title="Chat Admin" subtitle={`Percakapan langsung dengan ${selected.name}`}>
      <div className="mb-4 flex items-center gap-3"><Button variant="outline" size="sm" onClick={() => setSelected(null)}><ArrowLeft className="mr-2 h-4 w-4" /> Kembali ke daftar</Button><Badge variant="secondary">{roleLabel(selected.role)}</Badge></div>
      <div className="h-[calc(100vh-220px)] min-h-[520px]"><ConversationView title={selected.name} subtitle="Khusus admin ↔ pengguna ini" contextType="direct" conversationType={selected.role === 'merchant' ? 'admin_merchant' : selected.role === 'courier' ? 'admin_courier' : 'admin_user'} adminTargetUserId={selected.user_id} adminTargetRole={selected.role === 'buyer' ? 'buyer' : selected.role} receiverId={selected.user_id} onClose={() => setSelected(null)} /></div>
    </AdminLayout>;
  }

  return <AdminLayout title="Chat Admin" subtitle="Kirim pesan pribadi kepada pengguna. Hanya admin dan pengguna yang dipilih yang dapat melihat percakapan.">
    <Card><CardContent className="p-4 sm:p-6">
      <div className="mb-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h2 className="text-lg font-semibold">Mulai percakapan</h2><p className="text-sm text-muted-foreground">Pengguna tidak dapat memulai chat dengan pengguna lain.</p></div><div className="relative w-full sm:max-w-xs"><Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" /><Input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Cari nama…" className="pl-9" /></div></div>
      {error && <p className="mb-4 text-sm text-destructive">{error}</p>}
      <Tabs value={tab} onValueChange={(value) => setTab(value as TargetRole)}><TabsList className="mb-4 grid w-full max-w-xl grid-cols-3"><TabsTrigger value="buyer"><UserRound className="mr-2 h-4 w-4" /> Pengguna ({targets.filter((item) => item.role === 'buyer').length})</TabsTrigger><TabsTrigger value="merchant"><Store className="mr-2 h-4 w-4" /> Merchant ({targets.filter((item) => item.role === 'merchant').length})</TabsTrigger><TabsTrigger value="courier"><Truck className="mr-2 h-4 w-4" /> Kurir ({targets.filter((item) => item.role === 'courier').length})</TabsTrigger></TabsList>
        <TabsContent value={tab}>{loading ? <div className="py-12 text-center text-sm text-muted-foreground">Memuat daftar pengguna…</div> : visibleTargets.length === 0 ? <div className="flex flex-col items-center py-12 text-center text-muted-foreground"><MessageCircle className="mb-3 h-10 w-10 opacity-30" /><p>Tidak ada {roleLabel(tab).toLowerCase()} yang ditemukan.</p></div> : <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">{visibleTargets.map((target) => <button key={`${target.role}-${target.id}`} type="button" onClick={() => setSelected(target)} className="text-left"><Card className="transition hover:border-primary hover:bg-accent/40"><CardContent className="flex items-center gap-3 p-4"><div className="rounded-full bg-primary/10 p-2 text-primary">{target.role === 'merchant' ? <Store className="h-5 w-5" /> : target.role === 'courier' ? <Truck className="h-5 w-5" /> : <UserRound className="h-5 w-5" />}</div><div className="min-w-0 flex-1"><p className="truncate font-medium">{target.name}</p><p className="text-xs text-muted-foreground">{target.detail}</p></div><MessageCircle className="h-4 w-4 text-muted-foreground" /></CardContent></Card></button>)}</div>}</TabsContent>
      </Tabs>
    </CardContent></Card>
  </AdminLayout>;
}
