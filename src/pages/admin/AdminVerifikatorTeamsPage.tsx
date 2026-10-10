import { useCallback, useEffect, useMemo, useState } from 'react';
import { UserPlus, UsersRound, UserRoundCheck, UserRoundX, Plus, RefreshCw } from 'lucide-react';
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
  const [verifikatorIds, setVerifikatorIds] = useState<string[]>([]);
  const [selectedTeamId, setSelectedTeamId] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [createTeamOpen, setCreateTeamOpen] = useState(false);
  const [selectedUserId, setSelectedUserId] = useState('');
  const [selectedRole, setSelectedRole] = useState('MERCHANT_REVIEWER');
  const [search, setSearch] = useState('');
  const [teamName, setTeamName] = useState('');
  const [teamDescription, setTeamDescription] = useState('');
  const [teamLeadId, setTeamLeadId] = useState('');

  const selectedTeam = teams.find(team => team.id === selectedTeamId) || null;
  const verifikators = useMemo(() => profiles.filter(profile => verifikatorIds.includes(profile.user_id)), [profiles, verifikatorIds]);
  const availableProfiles = useMemo(() => {
    const memberIds = new Set(members.map(member => member.user_id));
    return verifikators.filter(profile => !memberIds.has(profile.user_id) && `${profile.full_name} ${profile.phone || ''}`.toLowerCase().includes(search.toLowerCase()));
  }, [verifikators, members, search]);
  const profileName = (userId: string) => profiles.find(profile => profile.user_id === userId)?.full_name || userId;

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [teamsRes, profilesRes, rolesRes] = await Promise.all([
        supabase.from('verifikator_teams').select('*').order('name'),
        supabase.from('profiles').select('user_id, full_name, phone').order('full_name'),
        supabase.from('user_roles').select('user_id').eq('role', 'verifikator'),
      ]);
      const error = teamsRes.error || profilesRes.error || rolesRes.error;
      if (error) throw error;

      const nextTeams = teamsRes.data || [];
      const nextProfiles = profilesRes.data || [];
      setTeams(nextTeams);
      setProfiles(nextProfiles);
      setVerifikatorIds((rolesRes.data || []).map(role => role.user_id));

      const nextTeamId = nextTeams.some(team => team.id === selectedTeamId)
        ? selectedTeamId
        : nextTeams[0]?.id || '';
      setSelectedTeamId(nextTeamId);
      if (nextTeamId) {
        const membersRes = await supabase.from('verifikator_team_members').select('*').eq('team_id', nextTeamId).order('joined_at');
        if (membersRes.error) throw membersRes.error;
        setMembers(membersRes.data || []);
      } else {
        setMembers([]);
      }
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Data tim gagal dimuat');
      setMembers([]);
    } finally {
      setLoading(false);
    }
  }, [selectedTeamId]);

  useEffect(() => { void load(); }, [load]);

  const addMember = async () => {
    if (!selectedTeamId || !selectedUserId || !verifikatorIds.includes(selectedUserId)) return;
    setSaving(true);
    const { error } = await supabase.from('verifikator_team_members').insert({ team_id: selectedTeamId, user_id: selectedUserId, role: selectedRole, is_active: true });
    setSaving(false);
    if (error) { toast.error(error.message); return; }
    toast.success('Anggota berhasil ditambahkan');
    setDialogOpen(false); setSelectedUserId(''); setSearch(''); void load();
  };

  const createTeam = async () => {
    const name = teamName.trim();
    if (name.length < 2 || name.length > 120 || !verifikatorIds.includes(teamLeadId)) return;
    setSaving(true);
    const { data: team, error } = await supabase.from('verifikator_teams').insert({
      name,
      description: teamDescription.trim() || null,
      lead_verifikator_id: teamLeadId,
      is_active: true,
    }).select('*').single();
    if (error || !team) {
      setSaving(false);
      toast.error(error?.message || 'Tim gagal dibuat');
      return;
    }

    const { error: memberError } = await supabase.from('verifikator_team_members').insert({
      team_id: team.id,
      user_id: teamLeadId,
      role: 'LEAD',
      is_active: true,
    });
    if (memberError) {
      // Best-effort cleanup: do not leave behind an unusable team without its lead.
      const { error: cleanupError } = await supabase.from('verifikator_teams').delete().eq('id', team.id);
      setSaving(false);
      toast.error(cleanupError ? `Membership koordinator gagal dibuat (${memberError.message}); tim ${team.name} juga gagal dibersihkan.` : `Membership koordinator gagal dibuat; tim dibatalkan. ${memberError.message}`);
      return;
    }

    setSaving(false);
    setTeamName(''); setTeamDescription(''); setTeamLeadId(''); setCreateTeamOpen(false);
    setSelectedTeamId(team.id);
    toast.success('Tim dan membership koordinator berhasil dibuat');
    void load();
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
        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2"><UsersRound className="h-5 w-5 text-primary" />Pilih tim</CardTitle></CardHeader>
          <CardContent>
            <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
              <Select value={selectedTeamId} onValueChange={setSelectedTeamId}>
                <SelectTrigger className="w-full sm:max-w-md"><SelectValue placeholder="Pilih tim verifikator" /></SelectTrigger>
                <SelectContent>{teams.map(team => <SelectItem key={team.id} value={team.id}>{team.name}{team.is_active ? '' : ' (Nonaktif)'}</SelectItem>)}</SelectContent>
              </Select>
              <Button onClick={() => setDialogOpen(true)} disabled={!selectedTeamId}><UserPlus className="mr-2 h-4 w-4" />Tambah anggota</Button>
              <Button variant="outline" onClick={() => setCreateTeamOpen(true)}><Plus className="mr-2 h-4 w-4" />Buat tim</Button>
              <Button variant="ghost" size="icon" onClick={() => void load()} aria-label="Muat ulang data"><RefreshCw className="h-4 w-4" /></Button>
            </div>
            {selectedTeam && <p className="mt-3 text-sm text-muted-foreground">{selectedTeam.description || 'Tim verifikator daerah'} · Koordinator: {profileName(selectedTeam.lead_verifikator_id)}</p>}
            {!loading && teams.length === 0 && <p className="mt-3 text-sm text-muted-foreground">Belum ada tim. Buat tim terlebih dahulu; akun koordinator harus memiliki role Verifikator.</p>}
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle>Anggota {selectedTeam ? `· ${selectedTeam.name}` : ''}</CardTitle></CardHeader>
          <CardContent>
            {loading ? <div className="py-10 text-center text-sm text-muted-foreground">Memuat data...</div> : !selectedTeam ? <div className="py-10 text-center text-sm text-muted-foreground">Pilih atau buat tim verifikator untuk mengelola anggotanya.</div> : <div className="overflow-x-auto"><Table><TableHeader><TableRow><TableHead>Anggota</TableHead><TableHead>Kontak</TableHead><TableHead>Role tim</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Aksi</TableHead></TableRow></TableHeader><TableBody>{members.map(member => <TableRow key={member.id}><TableCell><div className="flex flex-wrap items-center gap-2 font-medium">{profileName(member.user_id)}<Badge variant={verifikatorIds.includes(member.user_id) ? 'secondary' : 'destructive'}>{verifikatorIds.includes(member.user_id) ? 'Verifikator' : 'Role akun belum ditetapkan'}</Badge></div><div className="font-mono text-xs text-muted-foreground">{member.user_id}</div></TableCell><TableCell>{profiles.find(profile => profile.user_id === member.user_id)?.phone || '-'}</TableCell><TableCell><Select value={member.role} onValueChange={role => void updateMember(member, { role })}><SelectTrigger className="w-[180px]"><SelectValue /></SelectTrigger><SelectContent>{teamRoles.map(role => <SelectItem key={role.value} value={role.value}>{role.label}</SelectItem>)}</SelectContent></Select></TableCell><TableCell><Badge variant={member.is_active ? 'default' : 'secondary'}>{member.is_active ? 'Aktif' : 'Nonaktif'}</Badge></TableCell><TableCell className="text-right">{member.is_active ? <Button size="sm" variant="outline" onClick={() => void updateMember(member, { is_active: false })}><UserRoundX className="mr-1 h-4 w-4" />Nonaktifkan</Button> : <Button size="sm" variant="outline" onClick={() => void updateMember(member, { is_active: true })}><UserRoundCheck className="mr-1 h-4 w-4" />Aktifkan</Button>}</TableCell></TableRow>)}{members.length === 0 && <TableRow><TableCell colSpan={5} className="py-10 text-center text-sm text-muted-foreground">Belum ada anggota pada tim ini.</TableCell></TableRow>}</TableBody></Table></div>}
          </CardContent>
        </Card>
      </div>
      <Dialog open={createTeamOpen} onOpenChange={setCreateTeamOpen}>
        <DialogContent><DialogHeader><DialogTitle>Buat tim verifikator</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div><Label htmlFor="team-name">Nama tim</Label><Input id="team-name" className="mt-1" value={teamName} onChange={event => setTeamName(event.target.value)} maxLength={120} placeholder="Contoh: Tim Verifikator Kecamatan" /></div>
            <div><Label htmlFor="team-description">Deskripsi (opsional)</Label><Input id="team-description" className="mt-1" value={teamDescription} onChange={event => setTeamDescription(event.target.value)} placeholder="Wilayah atau tanggung jawab tim" /></div>
            <div><Label>Koordinator (akun Verifikator)</Label><Select value={teamLeadId} onValueChange={setTeamLeadId}><SelectTrigger className="mt-1"><SelectValue placeholder="Pilih koordinator" /></SelectTrigger><SelectContent>{verifikators.map(profile => <SelectItem key={profile.user_id} value={profile.user_id}>{profile.full_name || profile.user_id}{profile.phone ? ` · ${profile.phone}` : ''}</SelectItem>)}</SelectContent></Select></div>
            {verifikators.length === 0 && <p className="text-sm text-destructive">Belum ada akun dengan role Verifikator. Tetapkan role terlebih dahulu di menu Role Pengguna.</p>}
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setCreateTeamOpen(false)}>Batal</Button><Button onClick={() => void createTeam()} disabled={saving || teamName.trim().length < 2 || teamName.trim().length > 120 || !teamLeadId}>{saving ? 'Menyimpan...' : 'Buat tim'}</Button></DialogFooter>
        </DialogContent>
      </Dialog>
      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent><DialogHeader><DialogTitle>Tambah anggota tim</DialogTitle></DialogHeader>
          <div className="space-y-4"><div><Label>Cari pengguna</Label><Input className="mt-1" value={search} onChange={event => setSearch(event.target.value)} placeholder="Nama atau nomor telepon" /></div>
            <div><Label>Pengguna</Label><Select value={selectedUserId} onValueChange={setSelectedUserId}><SelectTrigger className="mt-1"><SelectValue placeholder="Pilih pengguna" /></SelectTrigger><SelectContent>{availableProfiles.slice(0, 50).map(profile => <SelectItem key={profile.user_id} value={profile.user_id}>{profile.full_name} {profile.phone ? `· ${profile.phone}` : ''}</SelectItem>)}</SelectContent></Select>{availableProfiles.length === 0 && <p className="mt-1 text-xs text-muted-foreground">Tidak ada akun Verifikator tersedia untuk pencarian ini.</p>}</div>
            <div><Label>Role operasional</Label><Select value={selectedRole} onValueChange={setSelectedRole}><SelectTrigger className="mt-1"><SelectValue /></SelectTrigger><SelectContent>{teamRoles.filter(role => role.value !== 'LEAD').map(role => <SelectItem key={role.value} value={role.value}>{role.label}</SelectItem>)}</SelectContent></Select></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setDialogOpen(false)}>Batal</Button><Button onClick={() => void addMember()} disabled={saving || !selectedUserId}>{saving ? 'Menyimpan...' : 'Simpan anggota'}</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </AdminLayout>
  );
}
