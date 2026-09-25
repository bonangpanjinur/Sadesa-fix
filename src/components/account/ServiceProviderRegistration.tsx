import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { CheckCircle2, Clock3, Send, Wrench, XCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { toast } from 'sonner';

const db = supabase as unknown as { from: typeof supabase.from; rpc: typeof supabase.rpc };

const fallbackCategories = [
  { id: 'elektronik', name: 'Jasa Elektronik', subcategories: [{ id: 'tv', name: 'Perbaikan televisi' }, { id: 'kulkas', name: 'Perbaikan kulkas' }, { id: 'pompa', name: 'Servis pompa air' }] },
  { id: 'bengkel', name: 'Jasa Bengkel Kendaraan', subcategories: [{ id: 'motor', name: 'Servis motor' }, { id: 'mobil', name: 'Servis mobil' }, { id: 'oli', name: 'Ganti oli' }] },
  { id: 'kebun', name: 'Jasa Kebun', subcategories: [{ id: 'rumput', name: 'Potong rumput' }, { id: 'pohon', name: 'Tebang pohon' }, { id: 'taman', name: 'Pembuatan taman' }] },
  { id: 'pertukangan', name: 'Jasa Pertukangan', subcategories: [{ id: 'kayu', name: 'Tukang kayu' }, { id: 'plafon', name: 'Pemasangan plafon' }, { id: 'cat', name: 'Pengecatan rumah' }] },
  { id: 'pendidikan', name: 'Jasa Pendidikan', subcategories: [{ id: 'les', name: 'Les anak sekolah' }, { id: 'ngaji', name: 'Mengaji' }, { id: 'komputer', name: 'Les komputer' }] },
];

type Category = { id: string; name: string; subcategories: { id: string; name: string }[] };
type ProviderApplication = {
  provider_name: string;
  headline: string;
  bio: string | null;
  village: string | null;
  phone: string | null;
  min_price: number;
  verification_status: string;
  verification_note: string | null;
  verifikator_code: string | null;
  service_skills?: { subcategory_id: string }[];
};

type Props = { userId: string; openOnMount?: boolean };

export function ServiceProviderRegistration({ userId, openOnMount = false }: Props) {
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(openOnMount);
  const [referralError, setReferralError] = useState('');
  const [post, setPost] = useState({ name: '', headline: '', bio: '', village: '', phone: '', min_price: '', referralCode: '', skills: [] as string[] });
  const { data: application, refetch } = useQuery<ProviderApplication | null>({
    queryKey: ['service-provider-application', userId],
    queryFn: async () => {
      const { data, error } = await db.from('service_profiles')
        .select('provider_name,headline,bio,village,phone,min_price,verification_status,verification_note,verifikator_code,service_skills(subcategory_id)')
        .eq('provider_id', userId)
        .maybeSingle();
      if (error) throw error;
      return data as ProviderApplication | null;
    },
  });
  const { data: categories = fallbackCategories } = useQuery<Category[]>({
    queryKey: ['service-categories'],
    queryFn: async () => {
      const { data, error } = await db.from('service_categories').select('id,name,subcategories:service_subcategories(id,name)').eq('is_active', true).order('sort_order');
      if (error || !data?.length) return fallbackCategories;
      return data as Category[];
    },
    staleTime: 300000,
  });
  useEffect(() => {
    if (openOnMount) setOpen(true);
  }, [openOnMount]);

  function editApplication() {
    if (application) {
      setPost({
        name: application.provider_name,
        headline: application.headline,
        bio: application.bio || '',
        village: application.village || '',
        phone: application.phone || '',
        min_price: String(application.min_price || ''),
        referralCode: application.verifikator_code || '',
        skills: application.service_skills?.map((skill) => skill.subcategory_id) || [],
      });
    }
    setReferralError('');
    setOpen(true);
  }

  async function submit() {
    const minPrice = Number(post.min_price || 0);
    if (post.name.trim().length < 2 || post.headline.trim().length < 3 || post.phone.trim().length < 8 || !post.skills.length || !Number.isFinite(minPrice) || minPrice < 0) {
      toast.error('Nama, judul, nomor telepon valid, harga minimum, dan minimal satu keahlian wajib diisi.');
      return;
    }
    const referralCode = post.referralCode.trim().toUpperCase();
    if (referralCode && !/^[A-Z0-9_-]{3,32}$/.test(referralCode)) {
      toast.error('Format kode referral tidak valid.');
      return;
    }
    setReferralError('');
    const { error } = await db.rpc('service_publish_profile', {
      p_provider_name: post.name,
      p_headline: post.headline,
      p_bio: post.bio,
      p_village: post.village,
      p_phone: post.phone.trim(),
      p_min_price: minPrice,
      p_subcategory_ids: post.skills,
      p_verifikator_code: referralCode || null,
    });
    if (error) {
      if (error.message?.toLowerCase().includes('referral code')) setReferralError(error.message);
      toast.error(error.message || 'Pendaftaran penyedia jasa gagal dikirim.');
      return;
    }
    toast.success(referralCode ? 'Pendaftaran dikirim ke verifikator pemilik kode.' : 'Pendaftaran dikirim dan menunggu verifikasi admin.');
    setOpen(false);
    await refetch();
    queryClient.invalidateQueries({ queryKey: ['service-providers'] });
  }

  const status = application?.verification_status;
  const statusCopy = status === 'VERIFIED'
    ? { label: 'Profil terverifikasi', detail: 'Profil Anda aktif di direktori jasa.', icon: CheckCircle2, className: 'border-emerald-200 bg-emerald-50 text-emerald-900' }
    : status === 'REJECTED'
      ? { label: 'Perlu diperbaiki', detail: application?.verification_note || 'Perbarui data lalu kirim kembali untuk diverifikasi.', icon: XCircle, className: 'border-red-200 bg-red-50 text-red-900' }
      : status === 'PENDING'
        ? { label: 'Menunggu verifikasi', detail: 'Admin atau verifikator akan meninjau data Anda.', icon: Clock3, className: 'border-amber-200 bg-amber-50 text-amber-950' }
        : null;
  const StatusIcon = statusCopy?.icon;

  return <>
    <Card className="mb-6 overflow-hidden border-emerald-200 bg-gradient-to-br from-emerald-50 via-card to-amber-50/50">
      <CardHeader className="pb-3">
        <CardTitle className="flex items-center gap-2 text-base"><Wrench className="h-5 w-5 text-emerald-700" />Penyedia Jasa</CardTitle>
        <CardDescription>Gunakan akun ini untuk menawarkan keahlian Anda di SaDesa.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {statusCopy && <div className={`flex items-start gap-2 rounded-xl border p-3 text-sm ${statusCopy.className}`}><StatusIcon className="mt-0.5 h-4 w-4 shrink-0" /><div><p className="font-semibold">{statusCopy.label}</p><p className="mt-0.5 text-xs opacity-80">{statusCopy.detail}</p></div></div>}
        {!statusCopy && <p className="text-sm text-muted-foreground">Belum ada pendaftaran. Lengkapi profil jasa untuk mulai mengajukan verifikasi.</p>}
        <Button onClick={editApplication} className="w-full rounded-full bg-emerald-700 hover:bg-emerald-800"><Wrench className="mr-2 h-4 w-4" />{status === 'VERIFIED' ? 'Kelola profil jasa' : application ? 'Lihat / perbarui pendaftaran' : 'Daftar sebagai penyedia jasa'}</Button>
      </CardContent>
    </Card>

    <Dialog open={open} onOpenChange={setOpen}><DialogContent className="max-h-[90vh] overflow-y-auto rounded-3xl sm:max-w-xl"><DialogHeader><DialogTitle>{application ? 'Perbarui pendaftaran penyedia jasa' : 'Daftar sebagai penyedia jasa'}</DialogTitle><DialogDescription>Pengajuan ini memakai akun Anda dan akan diverifikasi sebelum profil tampil di katalog.</DialogDescription></DialogHeader>
      <div className="space-y-4">
        {status === 'PENDING' && <div className="rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-950">Pendaftaran sedang menunggu verifikasi. Anda tetap dapat memperbarui data jika diperlukan.</div>}
        {status === 'REJECTED' && <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-900">Pendaftaran sebelumnya ditolak. Perbaiki data sesuai catatan lalu kirim kembali.</div>}
        <Input maxLength={100} placeholder="Nama penyedia / nama usaha" value={post.name} onChange={(e) => setPost({ ...post, name: e.target.value })} />
        <Input maxLength={120} placeholder="Judul layanan, mis. Teknisi elektronik panggilan" value={post.headline} onChange={(e) => setPost({ ...post, headline: e.target.value })} />
        <Input type="tel" maxLength={30} placeholder="Nomor telepon aktif" value={post.phone} onChange={(e) => setPost({ ...post, phone: e.target.value })} />
        <Textarea maxLength={2000} placeholder="Pengalaman, layanan, dan area yang dilayani" value={post.bio} onChange={(e) => setPost({ ...post, bio: e.target.value })} />
        <Input maxLength={150} placeholder="Desa / area layanan" value={post.village} onChange={(e) => setPost({ ...post, village: e.target.value })} />
        <Input type="number" min="0" step="1000" placeholder="Harga minimum jasa (Rp)" value={post.min_price} onChange={(e) => setPost({ ...post, min_price: e.target.value })} />
        <div><p className="mb-2 text-sm font-bold">Keahlian yang ditawarkan</p><div className="grid gap-3 sm:grid-cols-2">{categories.flatMap((category) => category.subcategories.map((sub) => <label key={sub.id} className={`cursor-pointer rounded-2xl border p-3 text-sm transition ${post.skills.includes(sub.id) ? 'border-emerald-500 bg-emerald-50 font-bold' : 'border-border bg-white'}`}><input type="checkbox" className="mr-2 accent-emerald-700" checked={post.skills.includes(sub.id)} onChange={(e) => setPost({ ...post, skills: e.target.checked ? [...post.skills, sub.id] : post.skills.filter((id) => id !== sub.id) })} />{sub.name}</label>))}</div></div>
        <div className="space-y-2"><label htmlFor="service-referral-code" className="text-sm font-semibold">Kode referral verifikator (opsional)</label><Input id="service-referral-code" maxLength={32} placeholder="Masukkan kode milik verifikator" value={post.referralCode} onChange={(e) => { setReferralError(''); setPost({ ...post, referralCode: e.target.value.toUpperCase() }); }} /><p className="text-xs text-muted-foreground">Dengan kode, pengajuan masuk ke antrean verifikator tersebut. Tanpa kode, admin yang memverifikasi.</p>{referralError && <p className="text-sm text-destructive">{referralError}</p>}</div>
      </div>
      <DialogFooter><Button onClick={() => void submit()} className="w-full rounded-full bg-emerald-700"><Send className="mr-2 h-4 w-4" />Kirim pendaftaran untuk verifikasi</Button></DialogFooter>
    </DialogContent></Dialog>
  </>;
}
