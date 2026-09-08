import { useMemo, useState } from 'react';
import { ArrowLeft, Box, CalendarDays, Check, Info, MapPin, PackageCheck, UserRound } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Label } from '@/components/ui/label';
import { Separator } from '@/components/ui/separator';
import { toast } from '@/hooks/use-toast';

type CourierMode = 'send' | 'pickup';
type DistanceBand = 'near' | 'medium' | 'far';

const distanceOptions: Array<{ value: DistanceBand; label: string; price: number }> = [
  { value: 'near', label: '0–3 km', price: 8000 },
  { value: 'medium', label: '3–7 km', price: 12000 },
  { value: 'far', label: 'Lebih dari 7 km', price: 18000 },
];

export default function CourierBookingPage() {
  const navigate = useNavigate();
  const [mode, setMode] = useState<CourierMode>('send');
  const [pickupAddress, setPickupAddress] = useState('');
  const [destinationAddress, setDestinationAddress] = useState('');
  const [recipientName, setRecipientName] = useState('');
  const [recipientPhone, setRecipientPhone] = useState('');
  const [packageType, setPackageType] = useState('');
  const [weight, setWeight] = useState('1');
  const [distanceBand, setDistanceBand] = useState<DistanceBand>('near');
  const [scheduled, setScheduled] = useState(false);
  const [notes, setNotes] = useState('');
  const [cod, setCod] = useState(false);

  const estimate = useMemo(() => {
    const base = distanceOptions.find((option) => option.value === distanceBand)?.price ?? 8000;
    const weightFee = Math.max(0, Number(weight || 0) - 2) * 2500;
    const codFee = cod ? 2000 : 0;
    return { base, weightFee, codFee, total: base + weightFee + codFee };
  }, [cod, distanceBand, weight]);

  const canContinue = pickupAddress.trim() && destinationAddress.trim() && recipientName.trim() && recipientPhone.trim() && packageType.trim();

  const handleContinue = () => {
    if (!canContinue) {
      toast({ title: 'Lengkapi detail pengiriman', description: 'Alamat, penerima, nomor telepon, dan jenis barang wajib diisi.', variant: 'destructive' });
      return;
    }
    toast({ title: 'Detail kurir tersimpan', description: 'Pencarian mitra kurir akan tersedia setelah dispatch kurir diaktifkan.' });
  };

  return (
    <div className="mobile-shell min-h-screen bg-background">
      <Header />
      <main className="px-5 pb-28 pt-5">
        <div className="mb-5 flex items-center gap-3">
          <Button variant="ghost" size="icon" className="h-9 w-9" onClick={() => navigate('/ride')}>
            <ArrowLeft className="h-4 w-4" />
            <span className="sr-only">Kembali</span>
          </Button>
          <div>
            <p className="text-[10px] font-bold uppercase tracking-wide text-amber-600">Layanan antar</p>
            <h1 className="font-heading text-xl font-bold">Kurir Barang</h1>
          </div>
        </div>

        <Card className="mb-4 border-amber-200 bg-amber-50/70 p-4 dark:border-amber-900 dark:bg-amber-950/25">
          <div className="flex gap-3">
            <Info className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" />
            <p className="text-xs leading-relaxed text-muted-foreground">
              Isi detail barang dengan lengkap. Tarif di bawah adalah estimasi awal berdasarkan jarak dan berat barang.
            </p>
          </div>
        </Card>

        <div className="space-y-4">
          <Card className="p-4">
            <div className="mb-3 flex items-center gap-2">
              <PackageCheck className="h-4 w-4 text-amber-600" />
              <h2 className="text-sm font-bold">Jenis layanan</h2>
            </div>
            <RadioGroup value={mode} onValueChange={(value) => setMode(value as CourierMode)} className="grid grid-cols-2 gap-3">
              <Label htmlFor="send" className={`flex cursor-pointer items-center gap-2 rounded-xl border p-3 text-xs ${mode === 'send' ? 'border-amber-500 bg-amber-50 dark:bg-amber-950/30' : 'border-border'}`}>
                <RadioGroupItem value="send" id="send" />
                <span><strong>Kirim barang</strong><br /><span className="text-muted-foreground">Saya mengirim</span></span>
              </Label>
              <Label htmlFor="pickup" className={`flex cursor-pointer items-center gap-2 rounded-xl border p-3 text-xs ${mode === 'pickup' ? 'border-amber-500 bg-amber-50 dark:bg-amber-950/30' : 'border-border'}`}>
                <RadioGroupItem value="pickup" id="pickup" />
                <span><strong>Ambil barang</strong><br /><span className="text-muted-foreground">Kurir mengambil</span></span>
              </Label>
            </RadioGroup>
          </Card>

          <Card className="space-y-4 p-4">
            <div className="flex items-center gap-2">
              <MapPin className="h-4 w-4 text-primary" />
              <h2 className="text-sm font-bold">Rute pengiriman</h2>
            </div>
            <div className="space-y-3">
              <div>
                <Label htmlFor="courier-pickup" className="mb-1.5 block text-xs text-muted-foreground">Lokasi pengambilan</Label>
                <Input id="courier-pickup" value={pickupAddress} onChange={(event) => setPickupAddress(event.target.value)} placeholder="Contoh: Pasar Desa Sukamaju" />
              </div>
              <div>
                <Label htmlFor="courier-destination" className="mb-1.5 block text-xs text-muted-foreground">Lokasi tujuan</Label>
                <Input id="courier-destination" value={destinationAddress} onChange={(event) => setDestinationAddress(event.target.value)} placeholder="Contoh: Jl. Merdeka No. 10" />
              </div>
            </div>
          </Card>

          <Card className="space-y-4 p-4">
            <div className="flex items-center gap-2">
              <UserRound className="h-4 w-4 text-primary" />
              <h2 className="text-sm font-bold">Detail penerima</h2>
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              <div>
                <Label htmlFor="recipient-name" className="mb-1.5 block text-xs text-muted-foreground">Nama penerima</Label>
                <Input id="recipient-name" value={recipientName} onChange={(event) => setRecipientName(event.target.value)} placeholder="Nama lengkap" />
              </div>
              <div>
                <Label htmlFor="recipient-phone" className="mb-1.5 block text-xs text-muted-foreground">Nomor telepon</Label>
                <Input id="recipient-phone" value={recipientPhone} onChange={(event) => setRecipientPhone(event.target.value)} placeholder="08xxxxxxxxxx" inputMode="tel" />
              </div>
            </div>
          </Card>

          <Card className="space-y-4 p-4">
            <div className="flex items-center gap-2">
              <Box className="h-4 w-4 text-primary" />
              <h2 className="text-sm font-bold">Detail barang</h2>
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              <div>
                <Label htmlFor="package-type" className="mb-1.5 block text-xs text-muted-foreground">Jenis barang</Label>
                <Input id="package-type" value={packageType} onChange={(event) => setPackageType(event.target.value)} placeholder="Contoh: makanan" />
              </div>
              <div>
                <Label htmlFor="weight" className="mb-1.5 block text-xs text-muted-foreground">Perkiraan berat (kg)</Label>
                <Input id="weight" value={weight} onChange={(event) => setWeight(event.target.value.replace(/[^\d.]/g, ''))} inputMode="decimal" />
              </div>
            </div>
            <div>
              <Label htmlFor="distance" className="mb-1.5 block text-xs text-muted-foreground">Perkiraan jarak</Label>
              <select id="distance" value={distanceBand} onChange={(event) => setDistanceBand(event.target.value as DistanceBand)} className="h-10 w-full rounded-md border border-input bg-background px-3 text-sm focus:outline-none focus:ring-2 focus:ring-ring">
                {distanceOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
              </select>
            </div>
            <label className="flex cursor-pointer items-center gap-3 rounded-xl border border-border p-3 text-xs">
              <input type="checkbox" checked={cod} onChange={(event) => setCod(event.target.checked)} className="h-4 w-4 accent-primary" />
              <span><strong>Aktifkan COD</strong><br /><span className="text-muted-foreground">Biaya layanan COD ditambahkan ke estimasi.</span></span>
            </label>
            <Textarea value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Catatan untuk kurir (opsional)" className="min-h-[70px]" />
          </Card>

          <Card className="p-4">
            <button type="button" onClick={() => setScheduled((value) => !value)} className="flex w-full items-center gap-3 text-left">
              <CalendarDays className="h-4 w-4 text-primary" />
              <span className="flex-1 text-xs font-semibold">Jadwalkan pengambilan</span>
              <span className={`flex h-5 w-5 items-center justify-center rounded-full border ${scheduled ? 'border-primary bg-primary text-primary-foreground' : 'border-muted-foreground/40'}`}>
                {scheduled && <Check className="h-3 w-3" />}
              </span>
            </button>
            {scheduled && <p className="mt-2 pl-7 text-[10px] text-muted-foreground">Jadwal spesifik dapat dipilih saat dispatch kurir diaktifkan.</p>}
          </Card>
        </div>

        <div className="sticky bottom-20 mt-5 rounded-2xl border border-border/70 bg-card/95 p-4 shadow-lg backdrop-blur-xl">
          <div className="mb-3 flex items-center justify-between">
            <div>
              <p className="text-[10px] text-muted-foreground">Estimasi biaya layanan</p>
              <p className="font-heading text-xl font-bold text-primary">Rp{estimate.total.toLocaleString('id-ID')}</p>
            </div>
            <div className="text-right text-[10px] text-muted-foreground">
              <p>Jarak {distanceOptions.find((option) => option.value === distanceBand)?.label}</p>
              {estimate.weightFee > 0 && <p>Tambahan berat Rp{estimate.weightFee.toLocaleString('id-ID')}</p>}
              {estimate.codFee > 0 && <p>COD Rp{estimate.codFee.toLocaleString('id-ID')}</p>}
            </div>
          </div>
          <Separator className="mb-3" />
          <Button className="h-11 w-full rounded-xl font-bold" onClick={handleContinue}>
            Tinjau pesanan kurir
          </Button>
        </div>
      </main>
      <BottomNav />
    </div>
  );
}