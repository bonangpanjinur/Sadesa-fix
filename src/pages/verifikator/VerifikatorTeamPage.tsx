import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Bike, Check, ClipboardList, MapPin, ShieldCheck, Store, UsersRound, X } from 'lucide-react';
import { VerifikatorLayout } from '@/components/verifikator/VerifikatorLayout';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { id } from 'date-fns/locale';

interface TeamData {
  team: { id: string; name: string; description: string | null; lead_verifikator_id: string; is_active: boolean } | null;
  members: Array<{ id: string; user_id: string; role: string; is_active: boolean; joined_at: string }>;
  scopes: Array<{ id: string; village_id: string; village?: { name: string; district: string; regency: string } | null }>;
  cases: Array<{ id: string; case_type: string; merchant_id: string | null; courier_id: string | null; status: string; risk_level: string; assigned_to: string | null; submitted_at: string; due_at: string | null; decision_reason: string | null; merchant?: { name: string } | null; courier?: { name: string } | null }>;
}

const roleLabels: Record<string, string> = {
  LEAD: 'Koordinator',
  MERCHANT_REVIEWER: 'Admin Merchant',
  COURIER_REVIEWER: 'Admin Ojek',
  QUALITY_CONTROL: 'Quality Control',
};
const statusLabels: Record<string, string> = {
  PENDING: 'Menunggu', IN_REVIEW: 'Sedang diperiksa', NEED_REVISION: 'Perlu revisi',
  READY_FOR_APPROVAL: 'Siap disetujui', APPROVED: 'Disetujui', REJECTED: 'Ditolak', ESCALATED: 'Eskalasi', CLOSED: 'Selesai',
};

export default function VerifikatorTeamPage() {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [activeTab, setActiveTab] = useState<'queue' | 'members' | 'scope'>('queue');
  const { data, isLoading } = useQuery<TeamData>({
    queryKey: ['verifikator-team-workspace', user?.id],
    enabled: !!user,
    staleTime: 30_000,
    queryFn: async () => {
      const { data: membership, error: membershipError } = await supabase
        .from('verifikator_team_members')
        .select('team_id')
        .eq('user_id', user!.id)
        .eq('is_active', true)
        .limit(1)
        .maybeSingle();
      if (membershipError) throw membershipError;
      if (!membership?.team_id) return { team: null, members: [], scopes: [], cases: [] };
      const [teamRes, membersRes, scopesRes, casesRes] = await Promise.all([
        supabase.from('verifikator_teams').select('*').eq('id', membership.team_id).maybeSingle(),
        supabase.from('verifikator_team_members').select('*').eq('team_id', membership.team_id).order('joined_at'),
        supabase.from('verifikator_team_scopes').select('*, village:villages(name, district, regency)').eq('team_id', membership.team_id).eq('is_active', true),
        supabase.from('verification_cases').select('*, merchant:merchants(name), courier:couriers(name)').eq('team_id', membership.team_id).order('due_at', { ascending: true, nullsFirst: false }),
      ]);
      const firstError = [teamRes, membersRes, scopesRes, casesRes].find(result => result.error)?.error;
      if (firstError) throw firstError;
      return { team: teamRes.data, members: membersRes.data || [], scopes: scopesRes.data || [], cases: casesRes.data || [] };
    },
  });
  const claimMutation = useMutation({
    mutationFn: async (caseId: string) => {
      const { error } = await supabase.rpc('claim_verification_case', { p_case_id: caseId });
      if (error) throw error;
    },
    onSuccess: () => { toast.success('Kasus berhasil diambil'); queryClient.invalidateQueries({ queryKey: ['verifikator-team-workspace', user?.id] }); },
    onError: (error: Error) => toast.error(error.message || 'Kasus tidak dapat diambil'),
  });
  const reviewMutation = useMutation({
    mutationFn: async ({ caseId, decision }: { caseId: string; decision: string }) => {
      const reason = decision === 'REJECTED' ? window.prompt('Masukkan alasan penolakan') : null;
      if (decision === 'REJECTED' && !reason?.trim()) throw new Error('Alasan penolakan wajib diisi');
      const { error } = await supabase.rpc('review_verification_case', { p_case_id: caseId, p_decision: decision, p_reason: reason });
      if (error) throw error;
    },
    onSuccess: () => { toast.success('Status kasus diperbarui'); queryClient.invalidateQueries({ queryKey: ['verifikator-team-workspace', user?.id] }); },
    onError: (error: Error) => toast.error(error.message || 'Kasus tidak dapat diperbarui'),
  });
  const team = data?.team;
  const cases = data?.cases || [];
  const openCases = cases.filter(item => !['APPROVED', 'REJECTED', 'CLOSED'].includes(item.status));
  const pendingCases = cases.filter(item => item.status === 'PENDING');
  const escalatedCases = cases.filter(item => item.status === 'ESCALATED');
  const statusBadge = (status: string) => <Badge variant={status === 'REJECTED' ? 'destructive' : status === 'APPROVED' || status === 'CLOSED' ? 'default' : 'outline'}>{statusLabels[status] || status}</Badge>;

  return (
    <VerifikatorLayout title="Tim & Antrean" subtitle="Kelola pembagian tugas verifikasi dalam wilayah tim">
      {isLoading ? <div className="flex h-64 items-center justify-center"><div className="h-8 w-8 animate-spin rounded-full border-b-2 border-primary" /></div> : !team ? (
        <Card><CardContent className="py-12 text-center"><UsersRound className="mx-auto mb-3 h-10 w-10 text-muted-foreground" /><p className="font-medium">Anda belum terdaftar dalam tim verifikator</p><p className="mt-1 text-sm text-muted-foreground">Hubungi admin pusat untuk mengatur membership dan scope wilayah.</p></CardContent></Card>
      ) : (
        <>
          <div className="mb-6 flex flex-col gap-4 rounded-xl border bg-card p-5 sm:flex-row sm:items-center sm:justify-between">
            <div><div className="flex items-center gap-2"><ShieldCheck className="h-5 w-5 text-primary" /><h2 className="text-xl font-semibold">{team.name}</h2><Badge variant={team.is_active ? 'default' : 'secondary'}>{team.is_active ? 'Aktif' : 'Nonaktif'}</Badge></div><p className="mt-1 text-sm text-muted-foreground">{team.description || 'Tim verifikator daerah'}</p></div>
            <div className="text-left sm:text-right"><p className="text-xs uppercase tracking-wide text-muted-foreground">Anggota aktif</p><p className="text-2xl font-bold">{data?.members.filter(member => member.is_active).length || 0}</p></div>
          </div>
          <div className="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-3">
            <Card><CardContent className="p-4"><div className="flex items-center gap-3"><ClipboardList className="h-5 w-5 text-primary" /><div><p className="text-sm text-muted-foreground">Kasus terbuka</p><p className="text-2xl font-bold">{openCases.length}</p></div></div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="flex items-center gap-3"><UsersRound className="h-5 w-5 text-orange-600" /><div><p className="text-sm text-muted-foreground">Menunggu pemeriksaan</p><p className="text-2xl font-bold">{pendingCases.length}</p></div></div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="flex items-center gap-3"><MapPin className="h-5 w-5 text-emerald-600" /><div><p className="text-sm text-muted-foreground">Scope wilayah</p><p className="text-2xl font-bold">{data?.scopes.length || 0}</p></div></div></CardContent></Card>
          </div>
          <div className="mb-4 flex gap-2 overflow-x-auto border-b"><Button variant={activeTab === 'queue' ? 'default' : 'ghost'} onClick={() => setActiveTab('queue')}><ClipboardList className="mr-2 h-4 w-4" />Antrean</Button><Button variant={activeTab === 'members' ? 'default' : 'ghost'} onClick={() => setActiveTab('members')}><UsersRound className="mr-2 h-4 w-4" />Anggota</Button><Button variant={activeTab === 'scope' ? 'default' : 'ghost'} onClick={() => setActiveTab('scope')}><MapPin className="mr-2 h-4 w-4" />Wilayah</Button></div>
          {activeTab === 'queue' && <Card><CardHeader><CardTitle>Antrean verifikasi</CardTitle></CardHeader><CardContent>{cases.length === 0 ? <p className="py-8 text-center text-sm text-muted-foreground">Belum ada kasus dalam antrean tim.</p> : <div className="overflow-x-auto"><Table><TableHeader><TableRow><TableHead>Jenis</TableHead><TableHead>Subjek</TableHead><TableHead>Status</TableHead><TableHead>Risiko</TableHead><TableHead>Dikirim</TableHead><TableHead>Aksi</TableHead></TableRow></TableHeader><TableBody>{cases.map(item => <TableRow key={item.id}><TableCell><div className="flex items-center gap-2">{item.case_type === 'MERCHANT' ? <Store className="h-4 w-4 text-emerald-600" /> : <Bike className="h-4 w-4 text-orange-600" />}{item.case_type === 'MERCHANT' ? 'Merchant' : 'Ojek'}</div></TableCell><TableCell className="font-medium">{item.merchant?.name || item.courier?.name || item.merchant_id || item.courier_id || '-'}</TableCell><TableCell>{statusBadge(item.status)}</TableCell><TableCell><Badge variant={item.risk_level === 'HIGH' ? 'destructive' : 'outline'}>{item.risk_level}</Badge></TableCell><TableCell>{format(new Date(item.submitted_at), 'dd MMM yyyy', { locale: id })}</TableCell><TableCell><div className="flex flex-wrap gap-2">{['PENDING', 'ESCALATED'].includes(item.status) && <Button size="sm" variant="outline" disabled={claimMutation.isPending} onClick={() => claimMutation.mutate(item.id)}>Ambil</Button>}{item.status === 'IN_REVIEW' && item.assigned_to === user?.id && <><Button size="sm" variant="outline" disabled={reviewMutation.isPending} onClick={() => reviewMutation.mutate({ caseId: item.id, decision: 'READY_FOR_APPROVAL' })}><Check className="mr-1 h-3 w-3" />Siap review</Button><Button size="sm" variant="destructive" disabled={reviewMutation.isPending} onClick={() => reviewMutation.mutate({ caseId: item.id, decision: 'REJECTED' })}><X className="mr-1 h-3 w-3" />Tolak</Button></>}</div></TableCell></TableRow>)}</TableBody></Table></div>}</CardContent></Card>}
          {activeTab === 'members' && <Card><CardHeader><CardTitle>Anggota tim</CardTitle></CardHeader><CardContent><Table><TableHeader><TableRow><TableHead>Pengguna</TableHead><TableHead>Peran</TableHead><TableHead>Status</TableHead><TableHead>Bergabung</TableHead></TableRow></TableHeader><TableBody>{(data?.members || []).map(member => <TableRow key={member.id}><TableCell className="font-mono text-xs">{member.user_id}</TableCell><TableCell>{roleLabels[member.role] || member.role}</TableCell><TableCell><Badge variant={member.is_active ? 'default' : 'secondary'}>{member.is_active ? 'Aktif' : 'Nonaktif'}</Badge></TableCell><TableCell>{format(new Date(member.joined_at), 'dd MMM yyyy', { locale: id })}</TableCell></TableRow>)}</TableBody></Table></CardContent></Card>}
          {activeTab === 'scope' && <Card><CardHeader><CardTitle>Scope wilayah tim</CardTitle></CardHeader><CardContent>{(data?.scopes || []).length === 0 ? <p className="py-8 text-center text-sm text-muted-foreground">Belum ada scope wilayah yang ditentukan.</p> : <Table><TableHeader><TableRow><TableHead>Desa</TableHead><TableHead>Kecamatan</TableHead><TableHead>Kabupaten</TableHead></TableRow></TableHeader><TableBody>{(data?.scopes || []).map(scope => <TableRow key={scope.id}><TableCell className="font-medium">{scope.village?.name || scope.village_id}</TableCell><TableCell>{scope.village?.district || '-'}</TableCell><TableCell>{scope.village?.regency || '-'}</TableCell></TableRow>)}</TableBody></Table>}</CardContent></Card>}
          {escalatedCases.length > 0 && <p className="mt-4 text-sm text-orange-700">Ada {escalatedCases.length} kasus eskalasi yang membutuhkan perhatian koordinator atau admin pusat.</p>}
        </>
      )}
    </VerifikatorLayout>
  );
}
