import { useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
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
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { toast } from 'sonner';
import { Armchair, CarFront, Check, ChevronRight, CircleDollarSign, FileClock, GraduationCap, Hammer, HeartPulse, Leaf, MessageCircle, Search, Send, ShieldCheck, Star, Trees, Truck, Wallet, Wrench } from 'lucide-react';

const db = supabase as unknown as { from: typeof supabase.from; rpc: typeof supabase.rpc };
const iconMap: Record<string, typeof Wrench> = { Tv: Leaf, CarFront, Hammer, Trees, Truck, Armchair, HeartPulse, GraduationCap, Wrench };
const demoCategories = [
  { id: 'demo-elektronik', name: 'Jasa Elektronik', slug: 'elektronik', icon: 'Wrench', subcategories: [{ id: 'demo-tv', name: 'Perbaikan televisi' }, { id: 'demo-kulkas', name: 'Perbaikan kulkas' }, { id: 'demo-pompa', name: 'Servis pompa air' }] },
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
  const { roles, isServiceProvider, refetch: refetchRoles } = useUserRoles();
  const navigate = useNavigate();
  const isAdmin = roles.includes('admin');
  const isBuyer = roles.includes('buyer');
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('all');
  const [selectedProvider, setSelectedProvider] = useState<Provider | null>(null);
  const [showOffer, setShowOffer] = useState(false);
  const [showPost, setShowPost] = useState(false);
  const [showOnboarding, setShowOnboarding] = useState(false);
  const [activatingRole, setActivatingRole] = useState(false);
  const [offer, setOffer] = useState({ title: '', description: '', location: '', price: '' });
  const [post, setPost] = useState({ name: '', headline: '', bio: '', village: '', min_price: '', skills: [] as string[] });

  const { data: categories = demoCategories } = useQuery<Category[]>({ queryKey: ['service-categories'], queryFn: async () => { const { data, error } = await db.from('service_categories').select('id,name,slug,icon,subcategories:service_subcategories(id,name)').eq('is_active', true).order('sort_order'); return error || !data?.length ? demoCategories : (data as Category[]).map((category) => ({ ...category, subcategories: Array.isArray(category.subcategories) ? category.subcategories : [] })); }, staleTime: 300000 });
  const { data: providers = [], isLoading } = useQuery<Provider[]>({ queryKey: ['service-providers'], queryFn: async () => { const { data, error } = await db.from('service_profiles').select('*,service_skills(subcategory_id,service_subcategories(name,category_id))').eq('is_active', true).order('rating', { ascending: false }); return error ? [] : data || []; }, staleTime: 60000 });
  const visibleProviders = useMemo(() => providers.filter((provider) => { const haystack = `${provider.provider_name} ${provider.headline} ${provider.bio || ''} ${provider.village || ''}`.toLowerCase(); const categoryMatch = selectedCategory === 'all' || provider.service_skills?.some((skill) => skill.service_subcategories?.category_id === selectedCategory); return categoryMatch && haystack.includes(search.toLowerCase()); }), [providers, search, selectedCategory]);

  function startProviderFlow() {
    if (!user) return navigate('/auth');
    if (!isBuyer) return toast.error('Akun pembeli belum aktif. Silakan masuk kembali atau buat akun pembeli terlebih dahulu.');
    if (!isServiceProvider) return setShowOnboarding(true);
    setShowPost(true);
  }

  async function activateProviderRole() {
    if (!user || !isBuyer) return toast.error('Anda harus memiliki akun pembeli terlebih dahulu.');
    setActivatingRole(true);
    const { error } = await db.rpc('activate_service_provider');
    setActivatingRole(false);
    if (error) return toast.error(error.message?.includes('Buyer role') ? 'Role pembeli diperlukan sebelum mendaftar sebagai penyedia jasa.' : 'Role jasa belum dapat diaktifkan. Coba lagi.');
    await refetchRoles();
    setShowOnboarding(false);
    setShowPost(true);
    toast.success('Role Penyedia Jasa aktif. Lengkapi profil agar tampil di katalog.');
  }

  async function createOffer() {
    if (!user) return navigate('/auth');
    if (!isBuyer) return toast.error('Gunakan akun pembeli untuk menghubungi penyedia jasa.');
    if (!selectedProvider || offer.title.trim().length < 3 || offer.description.trim().length < 10 || offer.location.trim().length < 3) return toast.error('Isi judul (min. 3 karakter), detail pekerjaan (min. 10 karakter), dan lokasi.');
    const budget = offer.price.trim() === '' ? null : Number(offer.price);
    if (budget !== null && (!Number.isFinite(budget) || budget < 0)) return toast.error('Budget harus berupa angka nol atau lebih.');
    const { error } = await db.rpc('service_create_request', { p_provider_id: selectedProvider.provider_id, p_profile_id: selectedProvider.id, p_subcategory_id: selectedProvider.service_skills?.[0]?.subcategory_id || null, p_title: offer.title, p_description: offer.description, p_location: offer.location, p_budget: budget });
    if (error) return toast.error(error.message || 'Gagal membuat permintaan jasa. Coba lagi.');
    toast.success('Permintaan terkirim. Harga akan ditetapkan setelah penyedia mengirim penawaran dan Anda menyetujuinya.'); setShowOffer(false); setOffer({ title: '', description: '', location: '', price: '' }); navigate('/services/requests');
  }

  async function publishProfile() {
    if (!user || !isServiceProvider) return toast.error('Aktifkan role Penyedia Jasa terlebih dahulu.');
    const minPrice = Number(post.min_price || 0);
    if (post.name.trim().length < 2 || post.headline.trim().length < 3 || !post.skills.length || !Number.isFinite(minPrice) || minPrice < 0) return toast.error('Nama, judul, harga minimum yang valid, dan minimal satu subkategori wajib diisi.');
    const { error } = await db.rpc('service_publish_profile', { p_provider_name: post.name, p_headline: post.headline, p_bio: post.bio, p_village: post.village, p_min_price: minPrice, p_subcategory_ids: post.skills });
    if (error) return toast.error(error.message || 'Gagal menyimpan profil dan keahlian penyedia jasa.');
    toast.success('Profil dan keahlian tersimpan. Admin akan meninjau sebelum profil tampil di katalog.'); setShowPost(false); queryClient.invalidateQueries({ queryKey: ['service-providers'] });
  }

  const selectedCategoryName = categories.find((category) => category.id === selectedCategory)?.name;
  return <div className="mobile-shell min-h-screen bg-background pb-32"><Header /><main className="mx-auto max-w-6xl px-3 py-4 sm:px-6 sm:py-6">
    <section className="relative overflow-hidden rounded-[1.5rem] bg-[linear-gradient(135deg,#12372a,#1f6a4d_60%,#e2a83b)] p-5 text-white shadow-xl sm:rounded-[2rem] sm:p-9"><div className="relative z-10 max-w-3xl"><p className="text-xs font-bold uppercase tracking-[0.22em] text-amber-200">SaDesa Jasa · marketplace lokal</p><h1 className="mt-2 max-w-2xl font-heading text-2xl font-black leading-tight tracking-tight sm:text-5xl">Keahlian warga, solusi dekat rumah.</h1><p className="mt-3 max-w-2xl text-sm leading-relaxed text-emerald-50 sm:text-base">Cari penyedia jasa tepercaya, kirim kebutuhan, sepakati harga, lalu biarkan admin menjaga pembayaran sampai pekerjaan selesai.</p><div className="mt-5 grid gap-2 sm:flex sm:flex-wrap sm:gap-3"><Button onClick={startProviderFlow} className="w-full justify-center rounded-full bg-amber-400 px-5 font-bold text-emerald-950 hover:bg-amber-300 sm:w-auto"><Wrench className="mr-2 h-4 w-4" />{isServiceProvider ? 'Kelola profil jasa' : 'Daftar sebagai penyedia'}</Button><Button asChild variant="outline" className="w-full justify-center rounded-full border-white/30 bg-white/10 text-white hover:bg-white/20 hover:text-white sm:w-auto"><Link to="/services/requests"><FileClock className="mr-2 h-4 w-4" />Request saya</Link></Button><Button asChild variant="outline" className="w-full justify-center rounded-full border-white/30 bg-white/10 text-white hover:bg-white/20 hover:text-white sm:w-auto"><Link to="/services/provider-history"><Wallet className="mr-2 h-4 w-4" />Riwayat provider</Link></Button></div><div className="mt-5 grid max-w-xl grid-cols-3 gap-2 text-[10px] sm:mt-6 sm:text-xs"><div className="rounded-2xl bg-white/10 p-3"><b className="block text-amber-200">01</b>Cari jasa</div><div className="rounded-2xl bg-white/10 p-3"><b className="block text-amber-200">02</b>Sepakati detail</div><div className="rounded-2xl bg-white/10 p-3"><b className="block text-amber-200">03</b>Bayar aman</div></div></div><div className="pointer-events-none absolute -right-12 -top-20 h-72 w-72 rounded-full border-[28px] border-white/10" /></section>
    <div className="mt-4 rounded-2xl border border-emerald-100 bg-emerald-50/70 p-3.5 text-sm text-emerald-950 sm:mt-6 sm:p-4"><div className="flex items-start gap-3"><ShieldCheck className="mt-0.5 h-5 w-5 shrink-0 text-emerald-700" /><div><b>Alur aman untuk semua pihak</b><p className="mt-1 text-emerald-900/75">Dana dititipkan ke admin, penyedia mulai bekerja setelah pembayaran diverifikasi, dan pencairan dilakukan setelah pekerjaan dikonfirmasi.</p></div></div></div>
    <div className="mt-5 grid gap-5 sm:mt-6 sm:gap-6 lg:grid-cols-[240px_1fr]"><aside className="min-w-0">
      <div className="mb-2 flex items-center justify-between">
        <h2 className="font-heading text-lg font-extrabold">Kategori jasa</h2>
        <Badge variant="secondary">{categories.length}</Badge>
      </div>
      <div className="-mx-1 flex gap-2 overflow-x-auto px-1 pb-2 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden lg:mx-0 lg:block lg:space-y-3 lg:overflow-visible lg:px-0 lg:pb-0">
        <button onClick={() => setSelectedCategory('all')} className={`flex min-w-[132px] shrink-0 items-center gap-2 rounded-2xl px-3 py-3 text-left text-sm font-bold transition lg:w-full lg:min-w-0 ${selectedCategory === 'all' ? 'bg-emerald-700 text-white shadow-md' : 'bg-white hover:bg-emerald-50'}`}><Wrench className="h-4 w-4" />Semua jasa</button>
        {categories.map((category) => { const Icon = iconMap[category.icon] || Wrench; return <button key={category.id} onClick={() => setSelectedCategory(category.id)} className={`flex min-w-[160px] shrink-0 items-center gap-2 rounded-2xl px-3 py-3 text-left text-sm font-bold transition lg:w-full lg:min-w-0 ${selectedCategory === category.id ? 'bg-emerald-700 text-white shadow-md' : 'bg-white hover:bg-emerald-50'}`}><span className="rounded-xl bg-emerald-100 p-2 text-emerald-700"><Icon className="h-4 w-4" /></span><span className="min-w-0 flex-1 truncate">{category.name}</span><ChevronRight className="h-4 w-4 opacity-50" /></button> })}
      </div>
    </aside>
    <section><div className="mb-4 flex flex-col justify-between gap-3 sm:mb-5 sm:flex-row sm:items-center"><div><p className="text-xs font-bold uppercase tracking-[0.16em] text-emerald-700">Direktori penyedia</p><h2 className="font-heading text-2xl font-black">{selectedCategoryName || 'Cari tenaga ahli'}</h2><p className="mt-1 text-sm text-muted-foreground">{visibleProviders.length} penyedia siap membantu</p></div><div className="flex w-full gap-2 sm:w-auto"><div className="relative min-w-0 flex-1 sm:w-64"><Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" /><Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Cari keahlian..." className="rounded-full bg-white pl-9" /></div><Button variant="outline" onClick={startProviderFlow} className="hidden rounded-full sm:flex"><Wrench className="mr-2 h-4 w-4" />Daftar</Button></div></div>{isLoading ? <div className="rounded-3xl bg-white p-10 text-center text-sm text-muted-foreground">Memuat penyedia jasa...</div> : visibleProviders.length === 0 ? <Card className="rounded-3xl border-dashed"><CardContent className="p-10 text-center"><CircleDollarSign className="mx-auto h-10 w-10 text-emerald-600" /><h3 className="mt-3 font-heading text-lg font-bold">Belum ada penyedia yang cocok</h3><p className="mt-1 text-sm text-muted-foreground">Jadilah yang pertama menawarkan keahlian di kategori ini.</p><Button onClick={startProviderFlow} className="mt-5 rounded-full">Tawarkan keahlian</Button></CardContent></Card> : <div className="grid gap-4 md:grid-cols-2">{visibleProviders.map((provider) => <Card key={provider.id} className="group rounded-3xl border-emerald-100 bg-white transition hover:-translate-y-1 hover:shadow-lg"><CardContent className="p-5"><div className="flex gap-3"><div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-emerald-100 text-lg font-black text-emerald-800">{provider.provider_name.slice(0, 1).toUpperCase()}</div><div className="min-w-0 flex-1"><div className="flex items-center gap-2"><h3 className="truncate font-heading font-extrabold">{provider.provider_name}</h3>{provider.is_verified && <ShieldCheck className="h-4 w-4 shrink-0 text-emerald-600" />}</div><p className="truncate text-xs text-muted-foreground">{provider.village || 'Melayani area sekitar desa'}</p></div></div><h4 className="mt-4 font-bold">{provider.headline}</h4><p className="mt-1 line-clamp-2 text-sm text-muted-foreground">{provider.bio || 'Siap membantu kebutuhan Anda dengan layanan yang rapi dan transparan.'}</p><div className="mt-4 flex flex-wrap gap-1.5">{provider.service_skills?.slice(0, 4).map((skill) => <Badge key={skill.subcategory_id} variant="secondary" className="rounded-full text-[10px]">{skill.service_subcategories?.name}</Badge>)}</div><div className="mt-5 flex flex-col items-stretch gap-3 border-t border-emerald-50 pt-4 sm:flex-row sm:items-end sm:justify-between"><div><div className="flex items-center gap-1 text-sm font-bold"><Star className="h-4 w-4 fill-amber-400 text-amber-400" />{Number(provider.rating || 0).toFixed(1)} <span className="font-normal text-muted-foreground">({provider.review_count || 0})</span></div><p className="mt-1 text-[11px] text-muted-foreground">Mulai dari <b className="text-foreground">{money(Number(provider.min_price || 0))}</b></p></div><Button onClick={() => { if (!user) return navigate('/auth'); setSelectedProvider(provider); setShowOffer(true); }} className="w-full justify-center rounded-full bg-emerald-700 hover:bg-emerald-800 sm:w-auto"><MessageCircle className="mr-2 h-4 w-4" />Hubungi</Button></div></CardContent></Card>)}</div>}</section></div>
    {isAdmin && <Card className="mt-8 rounded-3xl border-amber-200 bg-amber-50/60"><CardHeader><CardTitle className="flex items-center gap-2"><ShieldCheck className="h-5 w-5 text-amber-700" />Panel admin jasa</CardTitle></CardHeader><CardContent><p className="text-sm leading-relaxed text-amber-900">Verifikasi pembayaran, pantau escrow, dan catat referensi transfer payout/refund setelah transfer manual benar-benar dilakukan.</p></CardContent></Card>}
    </main><BottomNav />
    <Dialog open={showOnboarding} onOpenChange={setShowOnboarding}><DialogContent className="max-w-lg rounded-2xl sm:rounded-3xl"><DialogHeader><DialogTitle>Daftar sebagai Penyedia Jasa</DialogTitle><DialogDescription>Ikuti alur singkat ini agar akun Anda tetap aman dan dapat menerima pesanan.</DialogDescription></DialogHeader><div className="space-y-3">{[['1','Akun pembeli','Anda perlu memiliki akun pembeli untuk bertransaksi di SaDesa.'],['2','Aktifkan role jasa','Role ini memberi akses untuk membuat profil dan menerima permintaan.'],['3','Lengkapi profil','Pilih keahlian, area layanan, dan harga mulai agar mudah ditemukan.']].map(([number, title, description]) => <div key={number} className="flex gap-3 rounded-2xl border bg-muted/30 p-3"><div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-emerald-700 text-sm font-bold text-white">{number}</div><div><b>{title}</b><p className="mt-0.5 text-sm text-muted-foreground">{description}</p></div></div>)}</div><DialogFooter><Button variant="outline" onClick={() => setShowOnboarding(false)}>Nanti</Button><Button onClick={activateProviderRole} disabled={activatingRole} className="rounded-full bg-emerald-700">{activatingRole ? 'Mengaktifkan...' : 'Aktifkan role jasa'}<ChevronRight className="h-4 w-4" /></Button></DialogFooter></DialogContent></Dialog>
    <Dialog open={showOffer} onOpenChange={setShowOffer}><DialogContent className="max-w-lg rounded-2xl sm:rounded-3xl"><DialogHeader><DialogTitle>Ajukan kebutuhan ke {selectedProvider?.provider_name}</DialogTitle><DialogDescription>Budget awal bersifat opsional dan bukan harga final. Harga baru disepakati setelah penyedia mengirim penawaran dan Anda menyetujuinya.</DialogDescription></DialogHeader><div className="space-y-3"><Input maxLength={120} placeholder="Judul kebutuhan" value={offer.title} onChange={(e) => setOffer({ ...offer, title: e.target.value })} /><Textarea maxLength={4000} placeholder="Jelaskan pekerjaan yang dibutuhkan..." value={offer.description} onChange={(e) => setOffer({ ...offer, description: e.target.value })} /><Input maxLength={250} placeholder="Lokasi pekerjaan" value={offer.location} onChange={(e) => setOffer({ ...offer, location: e.target.value })} /><Input type="number" min="0" step="1000" placeholder="Budget awal (opsional)" value={offer.price} onChange={(e) => setOffer({ ...offer, price: e.target.value })} /></div><DialogFooter><Button onClick={createOffer} className="w-full rounded-full bg-emerald-700"><Send className="mr-2 h-4 w-4" />Kirim permintaan</Button></DialogFooter></DialogContent></Dialog>
    <Dialog open={showPost} onOpenChange={setShowPost}><DialogContent className="max-h-[90vh] overflow-y-auto rounded-3xl sm:max-w-xl"><DialogHeader><DialogTitle>Lengkapi profil penyedia</DialogTitle><DialogDescription>Profil dan keahlian akan disimpan sekaligus. Profil hanya dianggap terverifikasi setelah persetujuan admin.</DialogDescription></DialogHeader><div className="space-y-4"><div className="rounded-2xl bg-emerald-50 p-3 text-sm text-emerald-900"><Check className="mr-2 inline h-4 w-4" />Role Penyedia Jasa aktif untuk akun ini.</div><Input maxLength={100} placeholder="Nama yang tampil" value={post.name} onChange={(e) => setPost({ ...post, name: e.target.value })} /><Input maxLength={120} placeholder="Judul, mis. Teknisi elektronik panggilan" value={post.headline} onChange={(e) => setPost({ ...post, headline: e.target.value })} /><Textarea maxLength={2000} placeholder="Ceritakan pengalaman dan area layanan" value={post.bio} onChange={(e) => setPost({ ...post, bio: e.target.value })} /><Input maxLength={150} placeholder="Desa / area layanan" value={post.village} onChange={(e) => setPost({ ...post, village: e.target.value })} /><Input type="number" min="0" step="1000" placeholder="Harga minimum jasa (Rp)" value={post.min_price} onChange={(e) => setPost({ ...post, min_price: e.target.value })} /><div><p className="mb-2 text-sm font-bold">Subkategori keahlian</p><div className="grid gap-3 sm:grid-cols-2">{categories.flatMap((category) => (category.subcategories ?? []).map((sub) => <label key={sub.id} className={`cursor-pointer rounded-2xl border p-3 text-sm transition ${post.skills.includes(sub.id) ? 'border-emerald-500 bg-emerald-50 font-bold' : 'border-border bg-white'}`}><input type="checkbox" className="mr-2 accent-emerald-700" checked={post.skills.includes(sub.id)} onChange={(e) => setPost({ ...post, skills: e.target.checked ? [...post.skills, sub.id] : post.skills.filter((id) => id !== sub.id) })} />{sub.name}</label>))}</div></div></div><DialogFooter><Button onClick={publishProfile} className="w-full rounded-full bg-emerald-700">Simpan profil & keahlian</Button></DialogFooter></DialogContent></Dialog>
  </div>;
}
