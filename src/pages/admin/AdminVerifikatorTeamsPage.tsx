import { useCallback, useEffect, useMemo, useState } from 'react';
import { UserPlus, UsersRound, UserRoundCheck, UserRoundX } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { toast } from 'sonner';

const teamRoles = [
  { value: 'LEAD', label: 'Koordinator' },
  { value: 'MERCHANT_REVIEWER', label: 'Admin Merchant' },
  { value: 'COURIER_REVIEWER', label: 'Admin Ojek' },
  { value: 'QUALITY_CONTROL', label: 'Quality Control' },
];

type Team = { id: string; name: string; description: string | null; lead_verifikator_id: string; is_active: boolean };
type Member = { id: string; user_id: string; role: string; is_active: boolean; joined_at: string; ended_at: string | null };
type Profile = { user_id: string; full_name: string; phone: string | null };

export default function AdminVerifikatorTeamsPage() {
  const [teams, setTeams] = useState<Team[]>([]);
  const [members, setMembers] = useState<Member[]>([]);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [selectedTeamId, setSelectedTeamId] = useState('');
  const [loading, setLoading] = useState(true);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [selectedUserId, setSelectedUserId] = useState('');
  const [selectedRole, setSelectedRole] = useState('MERCHANT_REVIEWER');
  const [search, setSearch] = useState('');

  const selectedTeam = teams.find(team => team.id === selectedTeamId) || null;
  const availableProfiles = useMemo(() => {
    const memberIds = new Set(members.map(member => member.user_id));
    return profiles.filter(profile => !memberIds.has(profile.user_id) && `${profile.full_name} ${profile.phone || ''}`.toLowerCase().includes(search.toLowerCase()));
  }, [profiles, members, search]);
  const profileName = (userId: string) => profiles.find(profile => profile.user_id === userId)?.full_name || userId;
  const roleName = (role: string) => teamRoles.find(item => item.value === role)?.label || role;

  const load = useCallback(async () => {
    setLoading(true);
    const [teamsRes, profilesRes] = await Promise.all([
      supabase.from('verifikator_teams').select('*').order('name'),
      supabase.from('profiles').select('user_id, full_name, phone').order('full_name'),
    ]);
    if (teamsRes.error || profilesRes.error) {
      toast.error(teamsRes.error?.message || profilesRes.error?.message || 'Data tim gagal dimuat');
      setLoading(false);
      return;
    }
    setTeams(teamsRes.data || []);
    setProfiles(profilesRes.data || []);
    const teamId = selectedTeamId || teamsRes.data?.[0]?.id || '';
    setSelectedTeamId(teamId);
    if (teamId) {
      const membersRes = await supabase.from('verifikator_team_members').select('*').eq('team_id', teamId).order('joined_at');
      if (membersRes.error) toast.error(membersRes.error.message);
      setMembers(membersRes.data || []);
    } else {
      setMembers([]);
    }
    setLoading(false);
  }, [selectedTeamId]);

  useEffect(() => { void load(); }, [load]);

  const addMember = async () => {
    if (!selectedTeamId || !selectedUserId) return;
    const { error } = await supabase.from('verifikator_team_members').insert({ team_id: selectedTeamId, user_id: selectedUserId, role: selectedRole, is_active: true });
    if (error) { toast.error(error.message); return; }
    toast.success('Anggota berhasil ditambahkan');
    setDialogOpen(false); setSelectedUserId(''); setSearch(''); void load();
  };

  const updateMember = async (member: Member, patch: { role?: string; is_active?: boolean }) => {
    const { error } = await supabase.from('verifikator_team_members').update({ ...patch, ended_at: patch.is_active === false ? new Date().toISOString() : null, updated_at: new Date().toISOString() }).eq('id', member.id);
    if (error) { toast.error(error.message); return; }
    toast.success('Data anggota diperbarui');
    void load();
  };

  return (
    <AdminLayout title="Tim Verifikator" subtitle="Kelola anggota, role operasional, dan status membership tim">
      <div className="space-y-6">
        <Card><CardHeader><CardTitle className="flex items-center gap-2"><UsersRound className="h-5 w-5 text-primary" />Pilih tim</CardTitle></CardHeader><CardContent><div className="flex flex-col gap-3 sm:flex-row sm:items-center"><Select value={selectedTeamId} onValueChange={setSelectedTeamId}><SelectTrigger className="w-full sm:max-w-md"><SelectValue placeholder="Pilih tim verifikator" /></SelectTrigger><SelectContent>{teams.map(team => <SelectItem key={team.id} value={team.id}>{team.name}{team.is_active ? '' : ' (Nonaktif)'}</SelectItem>)}</SelectContent></Select><Button onClick={() => setDialogOpen(true)} disabled={!selectedTeamId}><UserPlus className="mr-2 h-4 w-4" />Tambah anggota</Button></div>{selectedTeam && <p className="mt-3 text-sm text-muted-foreground">{selectedTeam.description || 'Tim verifikator daerah'} · Koordinator: {profileName(selectedTeam.lead_verifikator_id)}</p>}</CardContent></Card>
        <Card><CardHeader><CardTitle>Anggota {selectedTeam ? `· ${selectedTeam.name}` : ''}</CardTitle></CardHeader><CardContent>{loading ? <div className="py-10 text-center text-sm text-muted-foreground">Memuat data...</div> : !selectedTeam ? <div className="py-10 text-center text-sm text-muted-foreground">Belum ada tim verifikator.</div> : <div className="overflow-x-auto"><Table><TableHeader><TableRow><TableHead>Anggota</TableHead><TableHead>Kontak</TableHead><TableHead>Role tim</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Aksi</TableHead></TableRow></TableHeader><TableBody>{members.map(member => <TableRow key={member.id}><TableCell><div className="font-medium">{profileName(member.user_id)}</div><div className="font-mono text-xs text-muted-foreground">{member.user_id}</div></TableCell><TableCell>{profiles.find(profile => profile.user_id === member.user_id)?.phone || '-'}</TableCell><TableCell><Select value={member.role} onValueChange={role => void updateMember(member, { role })}><SelectTrigger className="w-[180px]"><SelectValue /></SelectTrigger><SelectContent>{teamRoles.map(role => <SelectItem key={role.value} value={role.value}>{role.label}</SelectItem>)}</SelectContent></Select></TableCell><TableCell><Badge variant={member.is_active ? 'default' : 'secondary'}>{member.is_active ? 'Aktif' : 'Nonaktif'}</Badge></TableCell><TableCell className="text-right">{member.is_active ? <Button size="sm" variant="outline" onClick={() => void updateMember(member, { is_active: false })}><UserRoundX className="mr-1 h-4 w-4" />Nonaktifkan</Button> : <Button size="sm" variant="outline" onClick={() => void updateMember(member, { is_active: true })}><UserRoundCheck className="mr-1 h-4 w-4" />Aktifkan</Button>}</TableCell></TableRow>)}{members.length === 0 && <TableRow><TableCell colSpan={5} className="py-10 text-center text-sm text-muted-foreground">Belum ada anggota pada tim ini.</TableCell></TableRow>}</TableBody></Table></div>}</CardContent></Card>
      </div>
      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}><DialogContent><DialogHeader><DialogTitle>Tambah anggota tim</DialogTitle></DialogHeader><div className="space-y-4"><div><Label>Cari pengguna</Label><Input className="mt-1" value={search} onChange={event => setSearch(event.target.value)} placeholder="Nama atau nomor telepon" /></div><div><Label>Pengguna</Label><Select value={selectedUserId} onValueChange={setSelectedUserId}><SelectTrigger className="mt-1"><SelectValue placeholder="Pilih pengguna" /></SelectTrigger><SelectContent>{availableProfiles.slice(0, 50).map(profile => <SelectItem key={profile.user_id} value={profile.user_id}>{profile.full_name} {profile.phone ? `· ${profile.phone}` : ''}</SelectItem>)}</SelectContent></Select></div><div><Label>Role operasional</Label><Select value={selectedRole} onValueChange={setSelectedRole}><SelectTrigger className="mt-1"><SelectValue /></SelectTrigger><SelectContent>{teamRoles.map(role => <SelectItem key={role.value} value={role.value}>{role.label}</SelectItem>)}</SelectContent></Select></div></div><DialogFooter><Button variant="outline" onClick={() => setDialogOpen(false)}>Batal</Button><Button onClick={() => void addMember()} disabled={!selectedUserId}>Simpan anggota</Button></DialogFooter></DialogContent></Dialog>
    </AdminLayout>
  );
}
