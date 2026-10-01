import { ArrowLeft, Bike, Building2, CheckCircle2, Mail, MapPin, ShoppingBag, Store } from 'lucide-react';
import { Link, useNavigate } from 'react-router-dom';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { useBusinessProfile } from '@/hooks/useBusinessProfile';
import { safeGoBack } from '@/lib/utils';

const offerings = [
  { icon: ShoppingBag, title: 'Produk lokal', description: 'Makanan, minuman, dan kebutuhan harian dari merchant lokal.' },
  { icon: Bike, title: 'Layanan antar', description: 'Ojek penumpang dan kurir barang dengan estimasi tarif sebelum pemesanan.' },
  { icon: Store, title: 'Ruang untuk UMKM', description: 'Membantu pelaku usaha desa menampilkan katalog dan menerima pesanan.' },
];

export default function AboutPage() {
  const navigate = useNavigate();
  const { profile } = useBusinessProfile();

  return (
    <div className="mobile-shell flex min-h-screen flex-col bg-background">
      <Header />
      <main className="flex-1 overflow-y-auto pb-[var(--bottom-nav-space)]">
        <div className="mx-auto max-w-4xl space-y-5 px-4 py-5 sm:px-6 sm:py-8">
          <button type="button" onClick={() => safeGoBack(navigate)} className="inline-flex min-h-10 items-center gap-2 rounded-lg px-2 text-sm text-muted-foreground hover:bg-muted hover:text-foreground">
            <ArrowLeft className="h-4 w-4" /> Kembali
          </button>

          <section className="rounded-3xl bg-gradient-to-br from-emerald-700 to-emerald-900 p-6 text-white shadow-lg sm:p-8">
            <p className="text-xs font-bold uppercase tracking-[0.18em] text-emerald-100">Tentang SaDesa</p>
            <h1 className="mt-2 text-2xl font-bold sm:text-3xl">Dari desa untuk Indonesia</h1>
            <p className="mt-3 max-w-2xl text-sm leading-relaxed text-emerald-50 sm:text-base">{profile.tagline} {profile.brandName} menghubungkan pembeli dengan pelaku usaha lokal melalui katalog, keranjang belanja, checkout, dan layanan antar.</p>
          </section>

          <Card>
            <CardHeader><CardTitle className="flex items-center gap-2 text-lg"><Building2 className="h-5 w-5 text-primary" /> Identitas usaha</CardTitle></CardHeader>
            <CardContent className="grid gap-4 text-sm sm:grid-cols-2">
              <div><p className="text-xs text-muted-foreground">Nama brand</p><p className="font-semibold">{profile.brandName}</p></div>
              <div><p className="text-xs text-muted-foreground">Badan usaha</p><p className="font-semibold">{profile.legalName}</p></div>
              <div className="sm:col-span-2"><p className="text-xs text-muted-foreground">Alamat operasional</p><p className="font-semibold">{profile.address}</p></div>
              <div><p className="text-xs text-muted-foreground">Wilayah layanan</p><p>{profile.serviceArea}</p></div>
              <div><p className="text-xs text-muted-foreground">Jam operasional</p><p>{profile.operatingHours}</p></div>
            </CardContent>
          </Card>

          <section>
            <div className="mb-3"><p className="text-xs font-bold uppercase tracking-[0.16em] text-primary">Yang tersedia</p><h2 className="mt-1 text-xl font-bold">Produk dan layanan SaDesa</h2></div>
            <div className="grid gap-3 sm:grid-cols-3">
              {offerings.map(({ icon: Icon, title, description }) => <Card key={title} className="border-border/70"><CardContent className="p-4"><Icon className="h-6 w-6 text-primary" /><h3 className="mt-3 font-semibold">{title}</h3><p className="mt-1 text-sm leading-relaxed text-muted-foreground">{description}</p></CardContent></Card>)}
            </div>
          </section>

          <Card className="border-emerald-200 bg-emerald-50/60 dark:border-emerald-900 dark:bg-emerald-950/20">
            <CardHeader><CardTitle className="text-lg">Cara berbelanja</CardTitle></CardHeader>
            <CardContent className="grid gap-3 text-sm sm:grid-cols-3">
              {['Pilih produk dan lihat harga serta stok.', 'Tambahkan ke keranjang dan isi alamat pengiriman.', 'Tinjau total lalu lanjutkan ke checkout dan pembayaran.'].map((step, index) => <div key={step} className="flex gap-3"><CheckCircle2 className="mt-0.5 h-5 w-5 shrink-0 text-emerald-600" /><p><span className="font-semibold">{index + 1}. </span>{step}</p></div>)}
            </CardContent>
          </Card>

          <div className="flex flex-wrap gap-3">
            <Link to="/products" className="inline-flex min-h-11 items-center gap-2 rounded-xl bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground hover:bg-primary/90"><ShoppingBag className="h-4 w-4" /> Lihat katalog</Link>
            <Link to="/contact" className="inline-flex min-h-11 items-center gap-2 rounded-xl border border-border px-4 py-2 text-sm font-semibold hover:bg-muted"><Mail className="h-4 w-4" /> Hubungi kami</Link>
            <Link to="/ride" className="inline-flex min-h-11 items-center gap-2 rounded-xl border border-border px-4 py-2 text-sm font-semibold hover:bg-muted"><MapPin className="h-4 w-4" /> Lihat layanan antar</Link>
          </div>
        </div>
      </main>
      <BottomNav />
    </div>
  );
}
