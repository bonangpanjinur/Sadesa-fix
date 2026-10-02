import { ArrowLeft, CheckCircle2, CreditCard, Link2, MapPin, ShoppingCart, Truck } from 'lucide-react';
import { Link, useNavigate } from 'react-router-dom';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { safeGoBack } from '@/lib/utils';

const steps = [
  { icon: ShoppingCart, title: 'Keranjang', description: 'Pilih produk aktif, jumlah, dan merchant yang ingin dipesan.' },
  { icon: MapPin, title: 'Alamat pengiriman', description: 'Isi nama penerima, nomor telepon, alamat, dan catatan pengantaran.' },
  { icon: Truck, title: 'Biaya dan pengiriman', description: 'Tinjau tipe pengiriman, estimasi biaya, subtotal, dan total pesanan.' },
  { icon: CreditCard, title: 'Pembayaran', description: 'Pilih metode pembayaran yang tersedia lalu konfirmasi pesanan.' },
];

export default function CheckoutInfoPage() {
  const navigate = useNavigate();

  return (
    <div className="mobile-shell flex min-h-screen flex-col bg-background">
      <Header />
      <main className="flex-1 overflow-y-auto pb-[var(--bottom-nav-space)]">
        <div className="mx-auto max-w-3xl space-y-5 px-4 py-5 sm:px-6 sm:py-8">
          <button type="button" onClick={() => safeGoBack(navigate)} className="inline-flex min-h-10 items-center gap-2 rounded-lg px-2 text-sm text-muted-foreground hover:bg-muted hover:text-foreground"><ArrowLeft className="h-4 w-4" /> Kembali</button>
          <section><p className="text-xs font-bold uppercase tracking-[0.16em] text-primary">Checkout SaDesa</p><h1 className="mt-1 text-2xl font-bold">Tinjau pesanan sebelum pembayaran</h1><p className="mt-2 text-sm leading-relaxed text-muted-foreground">Checkout menampilkan produk, alamat, biaya pengiriman, total, dan metode pembayaran sebelum pesanan dikonfirmasi.</p></section>

          <Card className="border-primary/20 bg-primary/[0.04]"><CardHeader><CardTitle className="flex items-center gap-2 text-lg"><Link2 className="h-5 w-5 text-primary" /> Checkout tanpa login tersedia</CardTitle></CardHeader><CardContent className="space-y-3 text-sm text-muted-foreground"><p>Anda dapat membuat pesanan sebagai guest menggunakan link token yang berlaku beberapa hari. Simpan link status setelah checkout untuk melihat pesanan dan mengunggah bukti transfer.</p><div className="flex flex-wrap gap-3"><Button asChild><Link to="/checkout">Mulai checkout</Link></Button><Button asChild variant="outline"><Link to="/auth">Masuk atau daftar</Link></Button></div></CardContent></Card>

          <section><h2 className="mb-3 text-lg font-bold">Alur checkout</h2><div className="grid gap-3 sm:grid-cols-2">{steps.map(({ icon: Icon, title, description }, index) => <Card key={title} className="border-border/70"><CardContent className="flex gap-3 p-4"><div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-primary/10 text-sm font-bold text-primary">{index + 1}</div><div><h3 className="flex items-center gap-2 font-semibold"><Icon className="h-4 w-4 text-primary" />{title}</h3><p className="mt-1 text-sm leading-relaxed text-muted-foreground">{description}</p></div></CardContent></Card>)}</div></section>

          <Card><CardHeader><CardTitle className="text-lg">Yang ditampilkan sebelum konfirmasi</CardTitle></CardHeader><CardContent className="grid gap-2 text-sm sm:grid-cols-2">{['Nama dan harga setiap produk', 'Jumlah dan subtotal pesanan', 'Biaya pengiriman atau pickup', 'Diskon/voucher yang digunakan', 'Total pembayaran dalam Rupiah', 'Metode pembayaran yang tersedia'].map((item) => <div key={item} className="flex items-center gap-2"><CheckCircle2 className="h-4 w-4 text-emerald-600" />{item}</div>)}</CardContent></Card>
        </div>
      </main>
      <BottomNav />
    </div>
  );
}
