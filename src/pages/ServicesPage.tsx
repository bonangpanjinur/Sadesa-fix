import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useUserRoles } from '@/hooks/useUserRoles';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { toast } from 'sonner';
import { Armchair, CarFront, ChevronRight, CircleDollarSign, GraduationCap, Hammer, HeartPulse, Leaf, MessageCircle, Search, Send, ShieldCheck, Star, Trees, Tv, Truck, Wallet, Wrench } from 'lucide-react';

const db = supabase as any;
const iconMap: Record<string, any> = { Tv, CarFront, Hammer, Trees, Truck, Armchair, HeartPulse, GraduationCap, Wrench };
const demoCategories = [
  { id: 'demo-elektronik', name: 'Jasa Elektronik', slug: 'elektronik', icon: 'Tv', subcategories: [{ id: 'demo-tv', name: 'Perbaikan televisi' }, { id: 'demo-kulkas', name: 'Perbaikan kulkas' }, { id: 'demo-pompa', name: 'Servis pompa air' }] },
  { id: 'demo-bengkel', name: 'Jasa Bengkel Kendaraan', slug: 'bengkel-kendaraan', icon: 'CarFront', subcategories: [{ id: 'demo-motor', name: 'Servis motor' }, { id: 'demo-mobil', name: 'Servis mobil' }, { id: 'demo-oli', name: 'Ganti oli' }] },
  { id: 'demo-kebun', name: 'Jasa Kebun', slug: 'kebun', icon: 'Trees', subcategories: [{ id: 'demo-rumput', name: 'Potong rumput' }, { id: 'demo-pohon', name: 'Tebang pohon' }, { id: 'demo-taman', name: 'Pembuatan taman' }] },
  { id: 'demo-angkut', name: 'Jasa Angkut & Pengiriman', slug: 'angkut-pengiriman', icon: 'Truck', subcategories: [{ id: 'demo-angkut-barang', name: 'Angkut barang' }, { id: 'demo-pindahan', name: 'Pindahan rumah' }, { id: 'demo-titip', name: 'Titip belanja dari pasar' }] },
  { id: 'demo-pertukangan', name: 'Jasa Pertukangan', slug: 'pertukangan', icon: 'Hammer', subcategories: [{ id: 'demo-kayu', name: 'Tukang kayu' }, { id: 'demo-plafon', name: 'Pemasangan plafon' }, { id: 'demo-cat', name: 'Pengecatan rumah' }] },
  { id: 'demo-sewa', name: 'Jasa Sewa', slug: 'sewa', icon: 'Armchair', subcategories: [{ id: 'demo-motor-sewa', name: 'Sewa motor' }, { id: 'demo-tenda', name: 'Sewa tenda' }, { id: 'demo-sound', name: 'Sewa sound system' }] },
  { id: 'demo-perawatan', name: 'Kesehatan & Perawatan', slug: 'kesehatan-perawatan', icon: 'HeartPulse', subcategories: [{ id: 'demo-pijat', name: 'Pijat tradisional' }, { id: 'demo-cukur', name: 'Pangkas rambut' }] },
  { id: 'demo-pendidikan', name: 'Jasa Pendidikan', slug: 'pendidikan', icon: 'GraduationCap', subcategories: [{ id: 'demo-les', name: 'Les anak sekolah' }, { id: 'demo-ngaji', name: 'Mengaji' }, { id: 'demo-komputer', name: 'Les komputer' }] },
];

type Category = typeof demoCategories[number];
type Provider = { id: string; provider_id: string; provider_name: string; headline: string; bio: string | null; village: string | null; min_price: number; rating: number; review_count: number; is_verified: boolean; service_skills?: { subcategory_id: string; service_subcategories?: { name: string; category_id: string } }[] };
const money = (n: number) => new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(n);

export default function ServicesPage() {
  const { user } = useAuth();
  const { roles } = useUserRoles();
  const isAdmin = roles.includes('admin');
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('all');
  const [selectedProvider, setSelectedProvider] = useState<Provider | null>(null);
  const [showOffer, setShowOffer] = useState(false);
  const [showPost, setShowPost] = useState(false);
  const [tab, setTab] = useState('cari');
  const [offer, setOffer] = useState({ title: '', description: '', location: '', price: '' });
  const [post, setPost] = useState({ name: '', headline: '', bio: '', village: '', min_price: '', skills: [] as string[] });

  const { data: categories = demoCategories } = useQuery<Category[]>({ queryKey: ['service-categories'], queryFn: async () => {
    const { data, error } = await db.from('service_categories').select('id,name,slug,icon,service_subcategories(id,name)').eq('is_active', true).order('sort_order');
    if (error || !data?.length) return demoCategories;
    return data as Category[];
  }, staleTime: 300000 });
  const { data: providers = [], isLoading } = useQuery<Provider[]>({ queryKey: ['service-providers', selectedCategory], queryFn: async () => {
    let query = db.from('service_profiles').select('*,service_skills(subcategory_id,service_subcategories(name,category_id))').eq('is_active', true).order('rating', { ascending: false });
    const { data, error } = await query;
    if (error) return [];
    return data || [];
  }, staleTime: 60000 });

  const visibleProviders = useMemo(() => providers.filter((provider) => {
    const haystack = `${provider.provider_name} ${provider.headline} ${provider.bio || ''} ${provider.village || ''}`.toLowerCase();
    const categoryMatch = selectedCategory === 'all' || provider.service_skills?.some((skill) => skill.service_subcategories?.category_id === selectedCategory);
    return categoryMatch && haystack.includes(search.toLowerCase());
  }), [providers, search, selectedCategory]);

  async function createOffer() {
    if (!user || !selectedProvider || !offer.title || !offer.description || !offer.location) return toast.error('Lengkapi kebutuhan jasa terlebih dahulu.');
    const { error } = await db.from('service_requests').insert({ requester_id: user.id, provider_id: selectedProvider.provider_id, profile_id: selectedProvider.id, title: offer.title, description: offer.description, location: offer.location, agreed_price: offer.price ? Number(offer.price) : null });
    if (error) return toast.error('Gagal membuat permintaan jasa. Pastikan migrasi sudah diterapkan.');
    toast.success('Permintaan terkirim. Silakan lanjutkan negosiasi melalui chat.'); setShowOffer(false); setOffer({ title: '', description: '', location: '', price: '' });
  }

  async function publishProfile() {
    if (!user || !post.name || !post.headline || !post.skills.length) return toast.error('Nama, keahlian, dan minimal satu subkategori wajib diisi.');
    const { data: profile, error } = await db.from('service_profiles').upsert({ provider_id: user.id, provider_name: post.name, headline: post.headline, bio: post.bio || null, village: post.village || null, min_price: Number(post.min_price || 0), is_active: true }, { onConflict: 'provider_id' }).select('id').single();
    if (error || !profile) return toast.error('Gagal menyimpan profil penyedia jasa.');
    await db.from('service_skills').delete().eq('profile_id', profile.id);
    const { error: skillError } = await db.from('service_skills').insert(post.skills.map((subcategory_id) => ({ profile_id: profile.id, subcategory_id })));
    if (skillError) return toast.error('Profil tersimpan, tetapi keahlian belum tersimpan.');
    toast.success('Profil keahlian Anda sudah tampil di katalog.'); setShowPost(false); queryClient.invalidateQueries({ queryKey: ['service-providers'] });
  }

  const selectedCategoryName = categories.find((category) => category.id === selectedCategory)?.name;
  return <div className="mobile-shell min-h-screen bg-background pb-28"><Header /><main className="mx-auto max-w-6xl px-4 py-6 sm:px-6">
    <section className="relative overflow-hidden rounded-[2rem] bg-[linear-gradient(135deg,#12372a,#1f6a4d_60%,#e2a83b)] p-6 text-white shadow-xl sm:p-9">
      <div className="relative z-10 max-w-2xl"><p className="text-xs font-bold uppercase tracking-[0.22em] text-amber-200">SaDesa Jasa</p><h1 className="mt-2 font-heading text-3xl font-black tracking-tight sm:text-5xl">Keahlian warga, solusi dekat rumah.</h1><p className="mt-3 max-w-xl text-sm leading-relaxed text-emerald-50 sm:text-base">Temukan tukang dan tenaga ahli terpercaya di sekitar desa. Harga bisa dinegosiasikan, pembayaran aman dititipkan ke admin, dan pekerjaan baru berjalan setelah dana terverifikasi.</p><div className="mt-6 flex flex-wrap gap-3"><Button onClick={() => setShowPost(true)} className="rounded-full bg-amber-400 px-5 font-bold text-emerald-950 hover:bg-amber-300"><Wrench className="mr-2 h-4 w-4" />Tawarkan keahlian</Button><Button asChild variant="outline" className="rounded-full border-white/30 bg-white/10 text-white hover:bg-white/20 hover:text-white"><Link to="/services/provider-history"><Wallet className="mr-2 h-4 w-4" />Riwayat transaksi</Link></Button><div className="flex items-center gap-2 rounded-full border border-white/20 bg-white/10 px-4 text-xs font-semibold"><ShieldCheck className="h-4 w-4 text-amber-200" />Admin sebagai pihak ketiga</div></div></div><div className="pointer-events-none absolute -right-12 -top-20 h-72 w-72 rounded-full border-[28px] border-white/10" /></section>
    <div className="mt-6 grid gap-6 lg:grid-cols-[240px_1fr]"><aside className="space-y-3"><div className="flex items-center justify-between"><h2 className="font-heading text-lg font-extrabold">Kategori jasa</h2><Badge variant="secondary">{categories.length}</Badge></div><button onClick={() => setSelectedCategory('all')} className={`flex w-full items-center gap-3 rounded-2xl px-3 py-3 text-left text-sm font-bold transition ${selectedCategory === 'all' ? 'bg-emerald-700 text-white shadow-md' : 'bg-white text-foreground hover:bg-emerald-50'}`}><Wrench className="h-4 w-4" />Semua jasa</button>{categories.map((category) => { const Icon = iconMap[category.icon] || Wrench; return <button key={category.id} onClick={() => setSelectedCategory(category.id)} className={`flex w-full items-center gap-3 rounded-2xl px-3 py-3 text-left text-sm font-bold transition ${selectedCategory === category.id ? 'bg-emerald-700 text-white shadow-md' : 'bg-white text-foreground hover:bg-emerald-50'}`}><span className="rounded-xl bg-emerald-100 p-2 text-emerald-700"><Icon className="h-4 w-4" /></span><span className="min-w-0 flex-1 truncate">{category.name}</span><ChevronRight className="h-4 w-4 opacity-50" /></button>})}</aside>
    <section><div className="mb-5 flex flex-col justify-between gap-3 sm:flex-row sm:items-center"><div><p className="text-xs font-bold uppercase tracking-[0.16em] text-emerald-700">Direktori penyedia</p><h2 className="font-heading text-2xl font-black">{selectedCategoryName || 'Cari tenaga ahli'}</h2></div><div className="flex gap-2"><div className="relative min-w-0 flex-1 sm:w-64"><Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" /><Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Cari keahlian..." className="rounded-full bg-white pl-9" /></div><Button variant="outline" onClick={() => setShowPost(true)} className="hidden rounded-full sm:flex"><Wrench className="mr-2 h-4 w-4" />Posting</Button></div></div>{isLoading ? <div className="rounded-3xl bg-white p-10 text-center text-sm text-muted-foreground">Memuat penyedia jasa...</div> : visibleProviders.length === 0 ? <Card className="rounded-3xl border-dashed"><CardContent className="p-10 text-center"><CircleDollarSign className="mx-auto h-10 w-10 text-emerald-600" /><h3 className="mt-3 font-heading text-lg font-bold">Belum ada penyedia yang cocok</h3><p className="mt-1 text-sm text-muted-foreground">Jadilah yang pertama menawarkan keahlian di kategori ini.</p><Button onClick={() => setShowPost(true)} className="mt-5 rounded-full">Tawarkan keahlian</Button></CardContent></Card> : <div className="grid gap-4 md:grid-cols-2">{visibleProviders.map((provider) => <Card key={provider.id} className="group rounded-3xl border-emerald-100 bg-white transition hover:-translate-y-1 hover:shadow-lg"><CardContent className="p-5"><div className="flex gap-3"><div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-emerald-100 text-lg font-black text-emerald-800">{provider.provider_name.slice(0, 1).toUpperCase()}</div><div className="min-w-0 flex-1"><div className="flex items-center gap-2"><h3 className="truncate font-heading font-extrabold">{provider.provider_name}</h3>{provider.is_verified && <ShieldCheck className="h-4 w-4 shrink-0 text-emerald-600" />}</div><p className="truncate text-xs text-muted-foreground">{provider.village || 'Melayani area sekitar desa'}</p></div></div><h4 className="mt-4 font-bold text-foreground">{provider.headline}</h4><p className="mt-1 line-clamp-2 text-sm text-muted-foreground">{provider.bio || 'Siap membantu kebutuhan Anda dengan layanan yang rapi dan transparan.'}</p><div className="mt-4 flex flex-wrap gap-1.5">{provider.service_skills?.slice(0, 4).map((skill) => <Badge key={skill.subcategory_id} variant="secondary" className="rounded-full text-[10px]">{skill.service_subcategories?.name}</Badge>)}</div><div className="mt-5 flex items-end justify-between border-t border-emerald-50 pt-4"><div><div className="flex items-center gap-1 text-sm font-bold"><Star className="h-4 w-4 fill-amber-400 text-amber-400" />{Number(provider.rating || 0).toFixed(1)} <span className="font-normal text-muted-foreground">({provider.review_count || 0})</span></div><p className="mt-1 text-[11px] text-muted-foreground">Mulai dari <b className="text-foreground">{money(Number(provider.min_price || 0))}</b></p></div><Button onClick={() => { setSelectedProvider(provider); setShowOffer(true); }} className="rounded-full bg-emerald-700 hover:bg-emerald-800"><MessageCircle className="mr-2 h-4 w-4" />Hubungi</Button></div></CardContent></Card>)}</div>}</section></div>
    {isAdmin && <Card className="mt-8 rounded-3xl border-amber-200 bg-amber-50/60"><CardHeader><CardTitle className="flex items-center gap-2"><ShieldCheck className="h-5 w-5 text-amber-700" />Panel admin jasa</CardTitle></CardHeader><CardContent className="grid gap-3 sm:grid-cols-3"><div className="rounded-2xl bg-white p-4"><p className="text-xs text-muted-foreground">Peran admin</p><p className="mt-1 font-bold">Verifikasi pembayaran</p></div><div className="rounded-2xl bg-white p-4"><p className="text-xs text-muted-foreground">Alur pencairan</p><p className="mt-1 font-bold">Selesai → potong fee → teruskan</p></div><div className="rounded-2xl bg-white p-4"><p className="text-xs text-muted-foreground">Kelola taksonomi</p><p className="mt-1 font-bold">Kategori & subkategori dinamis</p></div><p className="text-xs leading-relaxed text-amber-900 sm:col-span-3">Data request, bukti transfer, fee layanan, dan payout tersimpan pada tabel marketplace jasa sehingga admin dapat memverifikasi sebelum penyedia mulai bekerja.</p></CardContent></Card>}
    </main><BottomNav />
    <Dialog open={showOffer} onOpenChange={setShowOffer}><DialogContent className="max-w-lg rounded-3xl"><DialogHeader><DialogTitle>Hubungi {selectedProvider?.provider_name}</DialogTitle><DialogDescription>Kirim detail pekerjaan. Harga boleh dikosongkan dan dibicarakan melalui chat.</DialogDescription></DialogHeader><div className="space-y-3"><Input placeholder="Judul kebutuhan, mis. TV tidak menyala" value={offer.title} onChange={(e) => setOffer({ ...offer, title: e.target.value })} /><Textarea placeholder="Jelaskan kerusakan atau pekerjaan yang dibutuhkan..." value={offer.description} onChange={(e) => setOffer({ ...offer, description: e.target.value })} /><Input placeholder="Lokasi pekerjaan" value={offer.location} onChange={(e) => setOffer({ ...offer, location: e.target.value })} /><Input type="number" placeholder="Budget awal (opsional)" value={offer.price} onChange={(e) => setOffer({ ...offer, price: e.target.value })} /></div><DialogFooter><Button onClick={createOffer} className="w-full rounded-full bg-emerald-700"><Send className="mr-2 h-4 w-4" />Kirim permintaan & mulai chat</Button></DialogFooter></DialogContent></Dialog>
    <Dialog open={showPost} onOpenChange={setShowPost}><DialogContent className="max-h-[90vh] overflow-y-auto rounded-3xl sm:max-w-xl"><DialogHeader><DialogTitle>Posting keahlian Anda</DialogTitle><DialogDescription>Pilih lebih dari satu subkategori jika Anda menguasai beberapa keahlian. Profil akan tampil bersama rating dan harga minimum.</DialogDescription></DialogHeader><div className="space-y-4"><Input placeholder="Nama yang tampil" value={post.name} onChange={(e) => setPost({ ...post, name: e.target.value })} /><Input placeholder="Judul, mis. Teknisi elektronik panggilan" value={post.headline} onChange={(e) => setPost({ ...post, headline: e.target.value })} /><Textarea placeholder="Ceritakan pengalaman dan area layanan" value={post.bio} onChange={(e) => setPost({ ...post, bio: e.target.value })} /><Input placeholder="Desa / area layanan" value={post.village} onChange={(e) => setPost({ ...post, village: e.target.value })} /><Input type="number" placeholder="Harga minimum jasa (Rp)" value={post.min_price} onChange={(e) => setPost({ ...post, min_price: e.target.value })} /><div><p className="mb-2 text-sm font-bold">Subkategori keahlian</p><div className="grid gap-3 sm:grid-cols-2">{categories.flatMap((category) => category.subcategories.map((sub) => <label key={sub.id} className={`cursor-pointer rounded-2xl border p-3 text-sm transition ${post.skills.includes(sub.id) ? 'border-emerald-500 bg-emerald-50 font-bold' : 'border-border bg-white'}`}><input type="checkbox" className="mr-2 accent-emerald-700" checked={post.skills.includes(sub.id)} onChange={(e) => setPost({ ...post, skills: e.target.checked ? [...post.skills, sub.id] : post.skills.filter((id) => id !== sub.id) })} />{sub.name}</label>))}</div></div></div><DialogFooter><Button onClick={publishProfile} className="w-full rounded-full bg-emerald-700">Publikasikan profil</Button></DialogFooter></DialogContent></Dialog>
  </div>;
}
