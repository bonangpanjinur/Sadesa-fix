import { useCallback, useEffect, useState } from 'react';
import { Truck, MapPin, Package, Loader2, Zap, User, Map, List } from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { toast } from 'sonner';
import { autoAssignCourier, manualAssignCourier, getAvailableCouriers } from '@/lib/courierApi';
import { CourierMapSelector } from '@/components/merchant/CourierMapSelector';

interface CourierAssignDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  orderId: string;
  merchantLat?: number;
  merchantLng?: number;
  deliveryLat?: number;
  deliveryLng?: number;
  onSuccess?: () => void;
}

interface AvailableCourier {
  id: string;
  name: string;
  vehicle_type: string;
  distance_km?: number;
  active_orders: number;
  current_lat?: number;
  current_lng?: number;
}

export function CourierAssignDialog({
  open,
  onOpenChange,
  orderId,
  merchantLat,
  merchantLng,
  deliveryLat,
  deliveryLng,
  onSuccess,
}: CourierAssignDialogProps) {
  const [couriers, setCouriers] = useState<AvailableCourier[]>([]);
  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState(false);
  const [assigning, setAssigning] = useState(false);
  const [autoAssigning, setAutoAssigning] = useState(false);
  const [viewMode, setViewMode] = useState<'list' | 'map'>('list');
  const isBusy = assigning || autoAssigning;

  const loadCouriers = useCallback(async () => {
    setLoading(true);
    setLoadError(false);
    try {
      const data = await getAvailableCouriers(merchantLat, merchantLng);
      setCouriers(data);
    } catch (error) {
      console.error('Error loading couriers:', error);
      setLoadError(true);
    } finally {
      setLoading(false);
    }
  }, [merchantLat, merchantLng]);

  useEffect(() => {
    if (open) {
      void loadCouriers();
    }
  }, [open, loadCouriers]);

  const handleAutoAssign = async () => {
    if (isBusy) return;
    setAutoAssigning(true);
    try {
      const result = await autoAssignCourier(orderId, merchantLat, merchantLng);

      if (result.success && result.courier) {
        toast.success(`Kurir ${result.courier.name} berhasil ditugaskan`);
        onOpenChange(false);
        onSuccess?.();
      } else {
        toast.error(result.error || 'Tidak ada kurir yang tersedia');
      }
    } catch {
      toast.error('Gagal menugaskan kurir otomatis');
    } finally {
      setAutoAssigning(false);
    }
  };

  const handleManualAssign = async (courierId: string) => {
    if (isBusy) return;
    setAssigning(true);
    try {
      const result = await manualAssignCourier(orderId, courierId);

      if (result.success) {
        toast.success('Kurir berhasil ditugaskan');
        onOpenChange(false);
        onSuccess?.();
      } else {
        toast.error(result.error || 'Gagal menugaskan kurir');
      }
    } catch {
      toast.error('Gagal menugaskan kurir');
    } finally {
      setAssigning(false);
    }
  };

  // Prepare couriers with GPS for map view
  const couriersWithGps = couriers.filter(c => c.current_lat && c.current_lng).map(c => ({
    id: c.id,
    name: c.name,
    lat: c.current_lat!,
    lng: c.current_lng!,
    vehicle_type: c.vehicle_type,
    active_orders: c.active_orders,
    distance_km: c.distance_km,
  }));

  const hasMapData = couriersWithGps.length > 0 || (merchantLat !== undefined && merchantLng !== undefined);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="flex h-[min(90dvh,44rem)] max-h-[calc(100dvh-2rem)] w-[calc(100vw-2rem)] max-w-2xl flex-col overflow-hidden p-4 sm:p-6">
        <DialogHeader className="shrink-0 pr-8 text-left">
          <DialogTitle className="flex items-center gap-2">
            <Truck className="h-5 w-5 shrink-0" />
            Tugaskan Kurir
          </DialogTitle>
          <DialogDescription>
            Pilih kurir untuk mengantarkan pesanan ini
          </DialogDescription>
        </DialogHeader>

        <div role="region" aria-label="Konten penugasan kurir" className="min-h-0 flex-1 space-y-4 overflow-y-auto overscroll-contain pr-1">
          <Button
            onClick={() => void handleAutoAssign()}
            disabled={isBusy || loading}
            className="w-full"
            size="lg"
          >
            {autoAssigning ? (
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            ) : (
              <Zap className="mr-2 h-4 w-4" />
            )}
            {autoAssigning ? 'Mencari kurir terdekat...' : 'Tugaskan Otomatis (Terdekat)'}
          </Button>

          {hasMapData && (
            <div role="group" aria-label="Tampilan kurir" className="flex overflow-hidden rounded-lg border border-border">
              <button
                type="button"
                aria-pressed={viewMode === 'list'}
                className={`flex min-h-10 flex-1 items-center justify-center gap-1.5 text-sm font-medium transition ${
                  viewMode === 'list' ? 'bg-primary text-primary-foreground' : 'bg-background text-muted-foreground hover:bg-secondary'
                }`}
                onClick={() => setViewMode('list')}
              >
                <List className="h-4 w-4" />
                Daftar
              </button>
              <button
                type="button"
                aria-pressed={viewMode === 'map'}
                className={`flex min-h-10 flex-1 items-center justify-center gap-1.5 border-l border-border text-sm font-medium transition ${
                  viewMode === 'map' ? 'bg-primary text-primary-foreground' : 'bg-background text-muted-foreground hover:bg-secondary'
                }`}
                onClick={() => setViewMode('map')}
              >
                <Map className="h-4 w-4" />
                Peta
              </button>
            </div>
          )}

          {viewMode === 'map' && hasMapData && (
            <CourierMapSelector
              merchantLat={merchantLat}
              merchantLng={merchantLng}
              deliveryLat={deliveryLat}
              deliveryLng={deliveryLng}
              couriers={couriersWithGps}
              onSelectCourier={(courierId) => void handleManualAssign(courierId)}
              assigning={isBusy}
            />
          )}

          {viewMode === 'list' && (
            <>
              <div className="relative py-1">
                <div className="absolute inset-0 flex items-center" aria-hidden="true">
                  <span className="w-full border-t" />
                </div>
                <div className="relative flex justify-center text-xs uppercase">
                  <span className="bg-background px-2 text-muted-foreground">atau pilih manual</span>
                </div>
              </div>

              {loading ? (
                <div className="flex items-center justify-center gap-2 py-8 text-sm text-muted-foreground" role="status">
                  <Loader2 className="h-5 w-5 animate-spin" />
                  Memuat daftar kurir...
                </div>
              ) : loadError ? (
                <div className="space-y-3 rounded-lg border border-destructive/20 bg-destructive/5 p-4 text-center" role="alert">
                  <p className="text-sm text-muted-foreground">Daftar kurir gagal dimuat. Periksa koneksi lalu coba lagi.</p>
                  <Button type="button" variant="outline" size="sm" onClick={() => void loadCouriers()}>
                    Coba Lagi
                  </Button>
                </div>
              ) : couriers.length === 0 ? (
                <div className="py-8 text-center text-muted-foreground">
                  <Truck className="mx-auto mb-2 h-10 w-10 opacity-50" />
                  <p className="font-medium">Belum ada kurir tersedia</p>
                  <p className="mt-1 text-xs">Coba assign otomatis atau periksa kembali nanti.</p>
                </div>
              ) : (
                <div className="space-y-2">
                  {couriers.map((courier) => (
                    <div
                      key={courier.id}
                      className="flex flex-col gap-3 rounded-lg border border-border p-3 transition hover:bg-secondary/60 sm:flex-row sm:items-center"
                    >
                      <div className="flex min-w-0 flex-1 items-center gap-3">
                        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary/10">
                          <User className="h-5 w-5 text-primary" />
                        </div>
                        <div className="min-w-0 flex-1">
                          <p className="truncate font-medium">{courier.name}</p>
                          <div className="mt-0.5 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                            <span className="capitalize">{courier.vehicle_type}</span>
                            {courier.distance_km !== undefined && (
                              <span className="flex items-center gap-1">
                                <MapPin className="h-3 w-3" />
                                {courier.distance_km.toFixed(1)} km
                              </span>
                            )}
                          </div>
                        </div>
                      </div>
                      <div className="flex items-center justify-between gap-2 sm:flex-col sm:items-end">
                        <Badge variant={courier.active_orders === 0 ? 'success' : 'secondary'} className="text-xs">
                          <Package className="mr-1 h-3 w-3" />
                          {courier.active_orders} aktif
                        </Badge>
                        <Button
                          type="button"
                          size="sm"
                          variant="outline"
                          disabled={isBusy}
                          aria-label={`Tugaskan ${courier.name}`}
                          onClick={() => void handleManualAssign(courier.id)}
                        >
                          {assigning ? <Loader2 className="mr-1 h-3.5 w-3.5 animate-spin" /> : null}
                          {assigning ? 'Menugaskan...' : 'Pilih'}
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
