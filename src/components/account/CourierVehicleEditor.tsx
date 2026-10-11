import { useCallback, useEffect, useState } from 'react';
import { Bike, Car, Clock3, Filter, History, Loader2, Save, X } from 'lucide-react';
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

interface VehicleHistoryItem {
  id: string;
  previous_vehicle_type: string;
  previous_vehicle_plate: string | null;
  new_vehicle_type: string;
  new_vehicle_plate: string | null;
  changed_at: string;
}

interface CourierVehicleEditorProps {
  userId: string;
}

const vehicleLabel = (value: string) => VEHICLE_TYPES.find((item) => item.value === value)?.label || value;
const plateLabel = (value: string | null) => value || 'Tanpa plat';

export function CourierVehicleEditor({ userId }: CourierVehicleEditorProps) {
  const [vehicleType, setVehicleType] = useState<VehicleType>('motor');
  const [vehiclePlate, setVehiclePlate] = useState('');
  const [history, setHistory] = useState<VehicleHistoryItem[]>([]);
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [appliedDateFrom, setAppliedDateFrom] = useState('');
  const [appliedDateTo, setAppliedDateTo] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const loadVehicle = useCallback(async (from = '', to = '') => {
    const historyQuery = supabase
      .from('courier_vehicle_history' as never)
      .select('id, previous_vehicle_type, previous_vehicle_plate, new_vehicle_type, new_vehicle_plate, changed_at')
      .order('changed_at', { ascending: false })
      .limit(100);
    if (from) historyQuery.gte('changed_at', new Date(`${from}T00:00:00`).toISOString());
    if (to) {
      const endDate = new Date(`${to}T00:00:00`);
      endDate.setDate(endDate.getDate() + 1);
      historyQuery.lt('changed_at', endDate.toISOString());
    }

    const [vehicleResult, historyResult] = await Promise.all([
      supabase
        .from('couriers')
        .select('vehicle_type, vehicle_plate')
        .eq('user_id', userId)
        .limit(1)
        .maybeSingle(),
      historyQuery,
    ]);

    if (vehicleResult.error) {
      toast({ title: 'Data kendaraan belum dapat dimuat', variant: 'destructive' });
    } else {
      const savedType = VEHICLE_TYPES.some((item) => item.value === vehicleResult.data?.vehicle_type)
        ? vehicleResult.data?.vehicle_type as VehicleType
        : 'motor';
      setVehicleType(savedType);
      setVehiclePlate(vehicleResult.data?.vehicle_plate || '');
    }
    if (historyResult.error) {
      toast({ title: 'Riwayat kendaraan belum dapat dimuat', variant: 'destructive' });
    } else {
      setHistory((historyResult.data || []) as unknown as VehicleHistoryItem[]);
    }
    setLoading(false);
  }, [userId]);

  useEffect(() => {
    void loadVehicle();
  }, [loadVehicle]);

  const handleSave = async () => {
    setSaving(true);
    const { error } = await supabase.rpc('update_own_courier_vehicle' as never, {
      p_vehicle_type: vehicleType,
      p_vehicle_plate: vehiclePlate.trim() || null,
    } as never);
    if (error) {
      toast({ title: 'Gagal memperbarui kendaraan', description: error.message, variant: 'destructive' });
    } else {
      toast({ title: 'Kendaraan berhasil diperbarui' });
      await loadVehicle(appliedDateFrom, appliedDateTo);
    }
    setSaving(false);
  };

  const handleFilter = () => {
    if (dateFrom && dateTo && dateFrom > dateTo) {
      toast({ title: 'Rentang tanggal tidak valid', description: 'Tanggal mulai tidak boleh melewati tanggal akhir.', variant: 'destructive' });
      return;
    }
    setAppliedDateFrom(dateFrom);
    setAppliedDateTo(dateTo);
    void loadVehicle(dateFrom, dateTo);
  };

  const handleResetFilter = () => {
    setDateFrom('');
    setDateTo('');
    setAppliedDateFrom('');
    setAppliedDateTo('');
    void loadVehicle();
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
        <>
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

          <div className="mt-5 border-t border-border pt-4">
            <div className="mb-3 flex items-center gap-2">
              <History className="h-4 w-4 text-primary" />
              <h4 className="font-semibold">Riwayat perubahan kendaraan</h4>
            </div>
            <div className="mb-4 rounded-lg border border-border bg-card p-3">
              <div className="mb-3 flex items-center gap-2 text-sm font-medium">
                <Filter className="h-4 w-4 text-primary" />
                Filter berdasarkan tanggal
              </div>
              <div className="grid gap-3 sm:grid-cols-2">
                <div className="space-y-1.5">
                  <Label htmlFor="courier-vehicle-history-from" className="text-xs">Dari tanggal</Label>
                  <Input id="courier-vehicle-history-from" type="date" value={dateFrom} onChange={(event) => setDateFrom(event.target.value)} />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="courier-vehicle-history-to" className="text-xs">Sampai tanggal</Label>
                  <Input id="courier-vehicle-history-to" type="date" value={dateTo} onChange={(event) => setDateTo(event.target.value)} />
                </div>
              </div>
              <div className="mt-3 flex flex-wrap gap-2">
                <Button type="button" size="sm" onClick={handleFilter}>
                  <Filter className="mr-2 h-3.5 w-3.5" /> Terapkan filter
                </Button>
                {(appliedDateFrom || appliedDateTo) && (
                  <Button type="button" size="sm" variant="outline" onClick={handleResetFilter}>
                    <X className="mr-2 h-3.5 w-3.5" /> Reset
                  </Button>
                )}
              </div>
            </div>
            {history.length === 0 ? (
              <p className="text-sm text-muted-foreground">{appliedDateFrom || appliedDateTo ? 'Tidak ada perubahan kendaraan pada rentang tanggal tersebut.' : 'Belum ada perubahan kendaraan yang tercatat.'}</p>
            ) : (
              <div className="space-y-3">
                {history.map((item) => (
                  <div key={item.id} className="rounded-lg border border-border bg-card p-3 text-sm">
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <p className="font-medium">
                          {vehicleLabel(item.previous_vehicle_type)} → {vehicleLabel(item.new_vehicle_type)}
                        </p>
                        <p className="text-xs text-muted-foreground">
                          {plateLabel(item.previous_vehicle_plate)} → {plateLabel(item.new_vehicle_plate)}
                        </p>
                      </div>
                      <span className="flex shrink-0 items-center gap-1 text-right text-[11px] text-muted-foreground">
                        <Clock3 className="h-3 w-3" />
                        {new Date(item.changed_at).toLocaleString('id-ID', { dateStyle: 'medium', timeStyle: 'short' })}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </>
      )}
    </section>
  );
}
