import { useEffect, useState } from 'react';
import { Bike, Car, Loader2, Save } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';

const VEHICLE_TYPES = [
  { value: 'motor', label: 'Motor', icon: Bike },
  { value: 'mobil', label: 'Mobil', icon: Car },
  { value: 'sepeda', label: 'Sepeda', icon: Bike },
] as const;

type VehicleType = (typeof VEHICLE_TYPES)[number]['value'];

interface CourierVehicleEditorProps {
  userId: string;
}

export function CourierVehicleEditor({ userId }: CourierVehicleEditorProps) {
  const [vehicleType, setVehicleType] = useState<VehicleType>('motor');
  const [vehiclePlate, setVehiclePlate] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let active = true;
    const loadVehicle = async () => {
      const { data, error } = await supabase
        .from('couriers')
        .select('vehicle_type, vehicle_plate')
        .eq('user_id', userId)
        .limit(1)
        .maybeSingle();
      if (!active) return;
      if (error) {
        toast({ title: 'Data kendaraan belum dapat dimuat', variant: 'destructive' });
      } else {
        const savedType = VEHICLE_TYPES.some((item) => item.value === data?.vehicle_type)
          ? data?.vehicle_type as VehicleType
          : 'motor';
        setVehicleType(savedType);
        setVehiclePlate(data?.vehicle_plate || '');
      }
      setLoading(false);
    };
    void loadVehicle();
    return () => { active = false; };
  }, [userId]);

  const handleSave = async () => {
    setSaving(true);
    const { error } = await supabase.rpc('update_own_courier_vehicle' as never, {
      p_vehicle_type: vehicleType,
      p_vehicle_plate: vehiclePlate.trim() || null,
    } as never);
    setSaving(false);

    if (error) {
      toast({ title: 'Gagal memperbarui kendaraan', description: error.message, variant: 'destructive' });
      return;
    }
    toast({ title: 'Kendaraan berhasil diperbarui' });
  };

  return (
    <section className="mt-4 rounded-xl border border-border bg-background/60 p-4">
      <div className="mb-3 flex items-start gap-3">
        <div className="rounded-lg bg-primary/10 p-2 text-primary"><Bike className="h-5 w-5" /></div>
        <div>
          <h3 className="font-semibold">Kendaraan Ojek</h3>
          <p className="text-xs text-muted-foreground">Ubah kendaraan yang tampil pada pesanan pelanggan.</p>
        </div>
      </div>
      {loading ? (
        <div className="flex items-center gap-2 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" /> Memuat kendaraan...</div>
      ) : (
        <div className="space-y-3">
          <div className="space-y-2">
            <Label htmlFor="courier-vehicle-type">Jenis kendaraan</Label>
            <Select value={vehicleType} onValueChange={(value) => setVehicleType(value as VehicleType)}>
              <SelectTrigger id="courier-vehicle-type"><SelectValue /></SelectTrigger>
              <SelectContent>
                {VEHICLE_TYPES.map((item) => <SelectItem key={item.value} value={item.value}>{item.label}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label htmlFor="courier-vehicle-plate">Nomor plat kendaraan</Label>
            <Input
              id="courier-vehicle-plate"
              value={vehiclePlate}
              onChange={(event) => setVehiclePlate(event.target.value.toUpperCase())}
              placeholder="B 1234 XYZ"
              maxLength={20}
            />
          </div>
          <Button type="button" onClick={() => void handleSave()} disabled={saving} className="w-full sm:w-auto">
            {saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Save className="mr-2 h-4 w-4" />}
            Simpan kendaraan
          </Button>
        </div>
      )}
    </section>
  );
}
