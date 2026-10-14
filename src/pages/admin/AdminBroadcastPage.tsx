import { useState, useEffect } from 'react';
import { 
  Bell, 
  Plus, 
  Send, 
  Trash2, 
  Edit, 
  MoreHorizontal, 
  Users,
  Clock,
  CheckCircle,
  AlertCircle
} from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Checkbox } from '@/components/ui/checkbox';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { id as idLocale } from 'date-fns/locale';
import { useAuth } from '@/contexts/AuthContext';
import { chunkArray, fetchAllPagedRows } from '@/lib/adminBroadcastRecipients';

interface Broadcast {
	id: string;
	title: string;
	message: string;
	link: string | null;
	target_audience: string;
  target_roles: string[];
  status: string;
  sent_at: string | null;
  sent_count: number;
  created_at: string;
}

const ROLE_OPTIONS = [
  { value: 'buyer', label: 'Pembeli' },
  { value: 'merchant', label: 'Pedagang' },
  { value: 'courier', label: 'Ojek' },
  { value: 'verifikator', label: 'Verifikator' },
  { value: 'admin_desa', label: 'Admin Desa' },
];

export default function AdminBroadcastPage() {
  const { user } = useAuth();
  const [broadcasts, setBroadcasts] = useState<Broadcast[]>([]);
  const [loading, setLoading] = useState(true);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [sending, setSending] = useState(false);
	const [formData, setFormData] = useState({
		title: '',
		message: '',
		link: '',
		target_audience: 'ALL',
		target_roles: [] as string[],
	});

	const normalizeBroadcastLink = (value: string) => {
		const link = value.trim();
		if (!link) return null;
		if (link.startsWith('/') && !link.startsWith('//')) return link;
		try {
			const parsed = new URL(link);
			if (parsed.protocol === 'http:' || parsed.protocol === 'https:') return parsed.toString();
		} catch {
			// Invalid URLs are rejected below with a user-facing message.
		}
		return undefined;
	};

  const fetchBroadcasts = async () => {
    try {
      const { data, error } = await supabase
        .from('broadcast_notifications')
        .select('*')
        .order('created_at', { ascending: false });

      if (error) throw error;
      setBroadcasts(data || []);
    } catch (error) {
      console.error('Error fetching broadcasts:', error);
      toast.error('Gagal memuat data');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchBroadcasts();
  }, []);

	const resetForm = () => {
		setFormData({
			title: '',
			message: '',
			link: '',
			target_audience: 'ALL',
      target_roles: [],
    });
  };

	const handleSendBroadcast = async () => {
		if (!formData.title.trim() || !formData.message.trim()) {
			toast.error('Judul dan pesan harus diisi');
			return;
		}
		if (formData.target_audience === 'ROLES' && formData.target_roles.length === 0) {
			toast.error('Pilih minimal satu role penerima');
			return;
		}
		const link = normalizeBroadcastLink(formData.link);
		if (link === undefined) {
			toast.error('Link harus berupa path internal (/promo) atau URL http/https yang valid');
			return;
		}

		setSending(true);
    let broadcastId: string | null = null;
    try {
      type AppRole = 'admin' | 'buyer' | 'verifikator' | 'merchant' | 'courier' | 'admin_desa';
      let userIds: string[] = [];

      if (formData.target_audience === 'ALL') {
        const profiles = await fetchAllPagedRows((from, to) => supabase
          .from('profiles')
          .select('user_id')
          .eq('is_blocked', false)
          .order('user_id', { ascending: true })
          .range(from, to));
        userIds = profiles.map((profile) => profile.user_id);
      } else {
        const rolesFilter = formData.target_roles as AppRole[];
        const recipients = await fetchAllPagedRows((from, to) => supabase
          .from('user_roles')
          .select('user_id, role')
          .in('role', rolesFilter)
          .order('user_id', { ascending: true })
          .order('role', { ascending: true })
          .range(from, to));
        userIds = recipients.map((recipient) => recipient.user_id);
      }
      userIds = [...new Set(userIds)];
      if (userIds.length === 0) throw new Error('Tidak ada pengguna yang cocok dengan target broadcast ini.');

      const { data: broadcast, error: createError } = await supabase
        .from('broadcast_notifications')
        .insert({
          title: formData.title.trim(),
          message: formData.message.trim(),
          link,
          target_audience: formData.target_audience,
          target_roles: formData.target_roles,
          status: 'SENDING',
          created_by: user?.id,
        })
        .select('id')
        .single();

      if (createError) throw createError;
      broadcastId = broadcast.id;

      const notifications = userIds.map((userId) => ({
        user_id: userId,
        title: formData.title.trim(),
        message: formData.message.trim(),
        type: 'broadcast',
        link,
      }));
      for (const batch of chunkArray(notifications, 500)) {
        const { error: notificationError } = await supabase.from('notifications').insert(batch);
        if (notificationError) throw notificationError;
      }

      // The edge function accepts recipient lists up to 5,000 IDs. Keep each
      // request smaller to avoid oversized PostgREST query URLs downstream.
      let pushSent = 0;
      let pushTotal = 0;
      let pushFailed = false;
      let pushFailureMessage = '';
      for (const recipientBatch of chunkArray(userIds, 500)) {
        try {
          const { data: pushData, error: pushError } = await supabase.functions.invoke('send-push-notification', {
            body: {
              user_ids: recipientBatch,
              title: formData.title.trim(),
              body: formData.message.trim(),
              url: link || '/',
            },
          });
          if (pushError) throw pushError;
          const result = pushData as { success?: boolean; sent?: number; total?: number; message?: string } | null;
          if (!result) throw new Error('Server push tidak memberikan hasil pengiriman.');
          const sent = result.sent ?? 0;
          const total = result.total ?? 0;
          pushSent += sent;
          pushTotal += total;
          if (result.success === false || (total > 0 && sent < total)) {
            pushFailed = true;
            pushFailureMessage ||= result.message || 'Sebagian perangkat gagal menerima push.';
          }
        } catch (pushError) {
          pushFailed = true;
          pushFailureMessage ||= pushError instanceof Error ? pushError.message : 'Pengiriman Web Push gagal.';
          console.error('Broadcast inbox berhasil, Web Push gagal:', pushError);
        }
      }

      const { error: statusError } = await supabase
        .from('broadcast_notifications')
        .update({
          status: pushFailed ? 'PARTIAL' : 'SENT',
          sent_at: new Date().toISOString(),
          sent_count: userIds.length,
        })
        .eq('id', broadcastId);
      if (statusError) console.error('Gagal menyimpan status broadcast:', statusError);

      if (pushFailed) {
        toast.warning(`Inbox terkirim ke ${userIds.length} pengguna; Web Push VAPID terkirim ke ${pushSent}/${pushTotal} perangkat. ${pushFailureMessage}`);
      } else if (pushTotal === 0) {
        toast.success(`Inbox terkirim ke ${userIds.length} pengguna. Belum ada perangkat target yang mengaktifkan Web Push.`);
      } else {
        toast.success(`Inbox terkirim ke ${userIds.length} pengguna; Web Push VAPID terkirim ke ${pushSent}/${pushTotal} perangkat.`);
      }
      setDialogOpen(false);
      resetForm();
      void fetchBroadcasts();
    } catch (error) {
      console.error('Error sending broadcast:', error);
      if (broadcastId) {
        const { error: statusError } = await supabase
          .from('broadcast_notifications')
          .update({ status: 'FAILED' })
          .eq('id', broadcastId)
          .eq('status', 'SENDING');
        if (statusError) console.error('Gagal menyimpan status gagal broadcast:', statusError);
      }
      toast.error(error instanceof Error ? error.message : 'Gagal mengirim notifikasi');
    } finally {
      setSending(false);
    }
  };

  const deleteBroadcast = async (id: string) => {
    if (!confirm('Yakin ingin menghapus?')) return;
    try {
      await supabase.from('broadcast_notifications').delete().eq('id', id);
      toast.success('Broadcast dihapus');
      fetchBroadcasts();
    } catch {
      toast.error('Gagal menghapus');
    }
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'SENT':
        return <Badge variant="success"><CheckCircle className="h-3 w-3 mr-1" />Terkirim</Badge>;
		case 'SENDING':
			return <Badge variant="warning"><Clock className="h-3 w-3 mr-1" />Mengirim</Badge>;
		case 'PARTIAL':
			return <Badge variant="warning"><AlertCircle className="h-3 w-3 mr-1" />Inbox terkirim, push sebagian gagal</Badge>;
      case 'DRAFT':
        return <Badge variant="secondary">Draft</Badge>;
      case 'FAILED':
        return <Badge variant="destructive"><AlertCircle className="h-3 w-3 mr-1" />Gagal</Badge>;
      default:
        return <Badge variant="outline">{status}</Badge>;
    }
  };

  const getAudienceLabel = (audience: string, roles: string[]) => {
    if (audience === 'ALL') return 'Semua Pengguna';
    if (audience === 'ROLES') {
      return roles.map(r => ROLE_OPTIONS.find(o => o.value === r)?.label || r).join(', ');
    }
    return audience;
  };

  return (
    <AdminLayout title="Broadcast Notifikasi" subtitle="Kirim notifikasi massal ke pengguna">
      <div className="flex justify-between items-center mb-6">
        <div className="flex items-center gap-2">
          <Bell className="h-5 w-5 text-primary" />
          <span className="text-muted-foreground">{broadcasts.length} broadcast</span>
        </div>
        <Button onClick={() => setDialogOpen(true)}>
          <Plus className="h-4 w-4 mr-2" />
          Buat Broadcast
        </Button>
      </div>

      {loading ? (
        <div className="flex items-center justify-center py-20">
          <div className="animate-spin rounded-full h-10 w-10 border-2 border-primary border-t-transparent" />
        </div>
      ) : broadcasts.length === 0 ? (
        <div className="text-center py-20 text-muted-foreground">
          <Bell className="h-16 w-16 mx-auto mb-4 opacity-50" />
          <p>Belum ada broadcast</p>
          <Button className="mt-4" onClick={() => setDialogOpen(true)}>
            Kirim Broadcast Pertama
          </Button>
        </div>
      ) : (
        <div className="space-y-4">
          {broadcasts.map(b => (
            <Card key={b.id}>
              <CardContent className="p-4">
                <div className="flex justify-between items-start">
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-1">
                      <h3 className="font-semibold">{b.title}</h3>
                      {getStatusBadge(b.status)}
                    </div>
                    <p className="text-sm text-muted-foreground line-clamp-2 mb-2">{b.message}</p>
                    <div className="flex items-center gap-4 text-xs text-muted-foreground">
                      <span className="flex items-center gap-1">
                        <Users className="h-3 w-3" />
                        {getAudienceLabel(b.target_audience, b.target_roles || [])}
                      </span>
                      {b.sent_count > 0 && (
                        <span className="flex items-center gap-1">
                          <Send className="h-3 w-3" />
                          {b.sent_count} terkirim
                        </span>
                      )}
                      <span className="flex items-center gap-1">
                        <Clock className="h-3 w-3" />
                        {format(new Date(b.created_at), 'dd MMM yyyy, HH:mm', { locale: idLocale })}
                      </span>
                    </div>
                  </div>
                  
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button variant="ghost" size="icon">
                        <MoreHorizontal className="h-4 w-4" />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem onClick={() => deleteBroadcast(b.id)} className="text-destructive">
                        <Trash2 className="h-4 w-4 mr-2" />
                        Hapus
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* Create Dialog */}
      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Send className="h-5 w-5" />
              Kirim Broadcast
            </DialogTitle>
          </DialogHeader>

          <div className="space-y-4">
            <div>
              <Label>Judul *</Label>
              <Input
                value={formData.title}
                onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                placeholder="Judul notifikasi"
              />
            </div>

            <div>
              <Label>Pesan *</Label>
              <Textarea
                value={formData.message}
                onChange={(e) => setFormData({ ...formData, message: e.target.value })}
                placeholder="Isi pesan notifikasi..."
					rows={4}
				/>
			</div>

			<div>
				<Label>Link tujuan atau promo (opsional)</Label>
				<Input
					value={formData.link}
					onChange={(e) => setFormData({ ...formData, link: e.target.value })}
					placeholder="/promo atau https://contoh.com/promo"
					type="text"
				/>
				<p className="mt-1 text-xs text-muted-foreground">Penerima akan diarahkan ke link ini saat notifikasi diklik.</p>
			</div>

			<div>
				<Label>Target Penerima</Label>
              <Select
                value={formData.target_audience}
                onValueChange={(value) => setFormData({ ...formData, target_audience: value })}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="ALL">Semua Pengguna</SelectItem>
                  <SelectItem value="ROLES">Berdasarkan Role</SelectItem>
                </SelectContent>
              </Select>
            </div>

            {formData.target_audience === 'ROLES' && (
              <div className="space-y-2">
                <Label>Pilih Role</Label>
                <div className="grid grid-cols-2 gap-2">
                  {ROLE_OPTIONS.map(role => (
                    <div key={role.value} className="flex items-center space-x-2">
                      <Checkbox
                        id={role.value}
                        checked={formData.target_roles.includes(role.value)}
                        onCheckedChange={(checked) => {
                          if (checked) {
                            setFormData({ ...formData, target_roles: [...formData.target_roles, role.value] });
                          } else {
                            setFormData({ ...formData, target_roles: formData.target_roles.filter(r => r !== role.value) });
                          }
                        }}
                      />
                      <label htmlFor={role.value} className="text-sm">{role.label}</label>
                    </div>
                  ))}
                </div>
				</div>
				)}

				<div className="rounded-lg border border-primary/20 bg-primary/5 p-3 text-xs text-muted-foreground">
					<strong className="text-foreground">Kanal pengiriman:</strong> pesan masuk ke inbox aplikasi dan dikirim sebagai Web Push melalui VAPID ke perangkat target yang sudah mengaktifkan notifikasi. VAPID bukan email, jadi broadcast ini tidak mengirim surat elektronik.
				</div>
			</div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>Batal</Button>
            <Button onClick={handleSendBroadcast} disabled={sending}>
              {sending ? (
                <>
                  <div className="animate-spin rounded-full h-4 w-4 border-2 border-primary-foreground border-t-transparent mr-2" />
                  Mengirim...
                </>
              ) : (
                <>
                  <Send className="h-4 w-4 mr-2" />
                  Kirim Sekarang
                </>
              )}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </AdminLayout>
  );
}
