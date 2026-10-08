import { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertCircle, ArrowLeft, Building2, Map, MapPin, RefreshCw, Users } from 'lucide-react';
import { CircleMarker, MapContainer, Popup, TileLayer, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { supabase } from '@/integrations/supabase/client';
import {
  aggregateGeography,
  aggregateUserMapPoints,
  getGeographyMetrics,
  normalizeLocationName,
  UNKNOWN_LOCATION_KEY,
  type GeographyLevel,
  type UserGeographyRecord,
  type UserMapPoint,
} from '@/lib/userGeography';

const PAGE_SIZE = 1000;
const INDONESIA_CENTER: [number, number] = [-2.5, 118];

async function fetchAllUserLocations(): Promise<UserGeographyRecord[]> {
  const rows: UserGeographyRecord[] = [];
  let offset = 0;

  while (true) {
    const { data, error } = await supabase
      .from('profiles')
      .select('user_id, province_name, city_name, district_name, address')
      .order('user_id', { ascending: true })
      .range(offset, offset + PAGE_SIZE - 1);

    if (error) throw error;
    const page = (data || []) as UserGeographyRecord[];
    rows.push(...page);
    if (page.length < PAGE_SIZE) break;
    offset += PAGE_SIZE;
  }

  return rows;
}

function formatCount(value: number): string {
  return new Intl.NumberFormat('id-ID').format(value);
}

function MapViewport({ points }: { points: UserMapPoint[] }) {
  const map = useMap();
  useEffect(() => {
    if (points.length === 1) {
      map.setView([points[0].lat, points[0].lng], 7, { animate: true });
    } else if (points.length > 1) {
      map.fitBounds(L.latLngBounds(points.map((point) => [point.lat, point.lng])), { padding: [28, 28], maxZoom: 7 });
    }
  }, [map, points]);
  return null;
}

function UserDistributionMap({ points }: { points: UserMapPoint[] }) {
  return (
    <div className="h-[340px] w-full overflow-hidden rounded-lg border sm:h-[440px]">
      <MapContainer center={INDONESIA_CENTER} zoom={4} minZoom={3} scrollWheelZoom className="h-full w-full">
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        <MapViewport points={points} />
        {points.map((point) => (
          <CircleMarker
            key={point.key}
            center={[point.lat, point.lng]}
            radius={Math.min(24, 8 + Math.sqrt(point.count) * 2)}
            pathOptions={{ color: '#ffffff', weight: 2, fillColor: '#137c68', fillOpacity: 0.8 }}
          >
            <Popup>
              <div className="space-y-1">
                <p className="font-semibold">{formatCount(point.count)} pengguna</p>
                <p className="whitespace-pre-line text-xs">{point.areas.length ? point.areas.slice(0, 5).join('\n') : 'Wilayah tidak tercantum'}</p>
                {point.areas.length > 5 && <p className="text-xs">+{point.areas.length - 5} wilayah lain</p>}
                <p className="text-[10px] text-slate-500">Titik dibulatkan untuk menjaga privasi</p>
              </div>
            </Popup>
          </CircleMarker>
        ))}
      </MapContainer>
    </div>
  );
}

function StatCard({ label, value, detail, icon: Icon }: {
  label: string;
  value: number;
  detail: string;
  icon: typeof Users;
}) {
  return (
    <Card>
      <CardContent className="flex items-center gap-4 p-5">
        <div className="rounded-xl bg-primary/10 p-3 text-primary"><Icon className="h-5 w-5" /></div>
        <div className="min-w-0">
          <p className="text-sm text-muted-foreground">{label}</p>
          <p className="text-2xl font-semibold">{formatCount(value)}</p>
          <p className="text-xs text-muted-foreground">{detail}</p>
        </div>
      </CardContent>
    </Card>
  );
}

export default function AdminUserGeographyPage() {
  const [records, setRecords] = useState<UserGeographyRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [selectedProvince, setSelectedProvince] = useState<string | null>(null);
  const [selectedCity, setSelectedCity] = useState<string | null>(null);
  const [realtimeStatus, setRealtimeStatus] = useState<'connecting' | 'live' | 'offline'>('connecting');

  const refresh = useCallback(async () => {
    setLoading(true);
    setErrorMessage(null);
    try {
      setRecords(await fetchAllUserLocations());
    } catch (error) {
      console.error('Gagal memuat audit lokasi pengguna:', error);
      setErrorMessage('Data lokasi pengguna gagal dimuat. Periksa koneksi atau izin admin, lalu coba lagi.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  useEffect(() => {
    let refreshTimer: ReturnType<typeof setTimeout> | undefined;
    const refreshDebounced = () => {
      if (refreshTimer) clearTimeout(refreshTimer);
      refreshTimer = setTimeout(() => { void refresh(); }, 500);
    };
    const channel = supabase
      .channel('admin-user-geography-live')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'profiles' }, refreshDebounced)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'profiles' }, refreshDebounced)
      .subscribe((status) => setRealtimeStatus(status === 'SUBSCRIBED' ? 'live' : 'offline'));

    return () => {
      if (refreshTimer) clearTimeout(refreshTimer);
      void supabase.removeChannel(channel);
    };
  }, [refresh]);

  const metrics = useMemo(() => getGeographyMetrics(records), [records]);
  const level: GeographyLevel = selectedCity ? 'district' : selectedProvince ? 'city' : 'province';
  const buckets = useMemo(
    () => aggregateGeography(records, level, selectedProvince ?? undefined, selectedCity ?? undefined),
    [records, level, selectedProvince, selectedCity],
  );
  const mapPoints = useMemo(
    () => aggregateUserMapPoints(records, selectedProvince ?? undefined, selectedCity ?? undefined),
    [records, selectedProvince, selectedCity],
  );
  const selectedScopeUserCount = records.filter((record) =>
    (!selectedProvince || normalizeLocationName(record.province_name) === selectedProvince)
    && (!selectedCity || normalizeLocationName(record.city_name) === selectedCity),
  ).length;
  const mappedUserCount = mapPoints.reduce((total, point) => total + point.count, 0);
  const scopeTotal = buckets.reduce((sum, bucket) => sum + bucket.count, 0);
  const maxCount = Math.max(1, ...buckets.map((bucket) => bucket.count));
  const selectedProvinceLabel = useMemo(
    () => records.find((record) => normalizeLocationName(record.province_name) === selectedProvince)?.province_name?.trim() ?? selectedProvince,
    [records, selectedProvince],
  );
  const selectedCityLabel = useMemo(
    () => records.find((record) => normalizeLocationName(record.province_name) === selectedProvince && normalizeLocationName(record.city_name) === selectedCity)?.city_name?.trim() ?? selectedCity,
    [records, selectedProvince, selectedCity],
  );

  const goToProvince = (key: string) => {
    if (key === UNKNOWN_LOCATION_KEY) return;
    setSelectedProvince(key);
    setSelectedCity(null);
  };
  const goToCity = (key: string) => {
    if (key === UNKNOWN_LOCATION_KEY) return;
    setSelectedCity(key);
  };

  const sectionTitle = level === 'province'
    ? 'Pengguna per provinsi'
    : level === 'city'
      ? `Pengguna per kota/kabupaten di ${selectedProvinceLabel}`
      : `Pengguna per kecamatan di ${selectedCityLabel}`;
  const sectionDescription = level === 'province'
    ? 'Pilih provinsi untuk melihat rincian kota/kabupaten.'
    : level === 'city'
      ? 'Pilih kota/kabupaten untuk melihat rincian kecamatan.'
      : 'Jumlah akun unik yang terdaftar pada setiap kecamatan.';

  return (
    <AdminLayout title="Sebaran Pengguna" subtitle="Audit sebaran akun berdasarkan lokasi profil terdaftar">
      <div className="space-y-6">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="flex items-center gap-2 text-2xl font-bold"><MapPin className="h-6 w-6 text-primary" />Audit Lokasi Pengguna</h1>
            <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
              Lihat jumlah pengguna dari provinsi, kota/kabupaten, hingga kecamatan. Setiap akun dihitung satu kali dari lokasi pada profilnya.
            </p>
          </div>
          <Button variant="outline" onClick={() => void refresh()} disabled={loading} className="gap-2 self-start sm:self-auto">
            <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} /> Perbarui data
          </Button>
        </div>

        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <StatCard label="Total pengguna" value={metrics.totalUsers} detail="Akun unik dalam profil" icon={Users} />
          <StatCard label="Lokasi lengkap" value={metrics.completeUsers} detail="Provinsi, kota, dan kecamatan terisi" icon={MapPin} />
          <StatCard label="Lokasi belum lengkap" value={metrics.incompleteUsers} detail="Minimal satu tingkat lokasi kosong" icon={AlertCircle} />
          <StatCard label="Cakupan wilayah" value={metrics.provinceCount} detail={`${formatCount(metrics.cityCount)} kota/kabupaten · ${formatCount(metrics.districtCount)} kecamatan`} icon={Building2} />
        </div>

        <Card>
          <CardHeader className="gap-2 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <CardTitle>Peta interaktif sebaran pengguna</CardTitle>
              <CardDescription>Marker menunjukkan kelompok akun pada area perkiraan; pilih provinsi atau kota di bawah untuk memfilter peta.</CardDescription>
            </div>
            <Badge variant={realtimeStatus === 'live' ? 'default' : 'secondary'} className="w-fit">
              {realtimeStatus === 'live' ? 'Realtime aktif' : realtimeStatus === 'connecting' ? 'Menghubungkan…' : 'Realtime terputus'}
            </Badge>
          </CardHeader>
          <CardContent className="space-y-3">
            {loading && records.length === 0 ? (
              <div className="flex h-[340px] items-center justify-center rounded-lg border bg-muted/20 text-sm text-muted-foreground">Memuat titik sebaran…</div>
            ) : errorMessage ? (
              <div className="flex h-48 items-center justify-center rounded-lg border bg-muted/20 text-sm text-muted-foreground">Peta tidak tersedia sampai data profil berhasil dimuat.</div>
            ) : (
              <UserDistributionMap points={mapPoints} />
            )}
            <p className="text-xs leading-relaxed text-muted-foreground">
              {formatCount(mappedUserCount)} dari {formatCount(selectedScopeUserCount)} pengguna pada tampilan ini memiliki titik peta di profil. Peta diperbarui otomatis saat profil ditambah atau diperbarui; setelah akun dihapus, tekan “Perbarui data”. Titik diringkas ke grid ±0,1° (sekitar 10 km), tanpa alamat persis atau identitas akun. Peta dasar dari OpenStreetMap.
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <CardTitle>{sectionTitle}</CardTitle>
              <CardDescription>{sectionDescription}</CardDescription>
            </div>
            <Badge variant="secondary" className="w-fit">{formatCount(scopeTotal)} pengguna pada tampilan ini</Badge>
          </CardHeader>
          <CardContent>
            {(selectedProvince || selectedCity) && (
              <div className="mb-5 flex flex-wrap items-center gap-2 text-sm">
                <Button variant="ghost" size="sm" className="gap-2 px-2" onClick={() => { setSelectedProvince(null); setSelectedCity(null); }}>
                  <ArrowLeft className="h-4 w-4" /> Semua provinsi
                </Button>
                {selectedProvince && <>
                  <span className="text-muted-foreground">/</span>
                  <Button variant={selectedCity ? 'ghost' : 'secondary'} size="sm" onClick={() => setSelectedCity(null)}>{selectedProvinceLabel}</Button>
                </>}
                {selectedCity && <>
                  <span className="text-muted-foreground">/</span>
                  <span className="rounded-md bg-muted px-2 py-1">{selectedCityLabel}</span>
                </>}
              </div>
            )}

            {loading ? (
              <div className="flex min-h-56 items-center justify-center gap-3 text-sm text-muted-foreground">
                <RefreshCw className="h-5 w-5 animate-spin" /> Memuat seluruh profil pengguna…
              </div>
            ) : errorMessage ? (
              <div className="flex min-h-48 flex-col items-center justify-center gap-3 text-center">
                <AlertCircle className="h-8 w-8 text-destructive" />
                <p className="max-w-md text-sm text-muted-foreground">{errorMessage}</p>
                <Button variant="outline" onClick={() => void refresh()}>Coba lagi</Button>
              </div>
            ) : buckets.length === 0 ? (
              <div className="flex min-h-48 flex-col items-center justify-center gap-2 text-center text-muted-foreground">
                <Map className="h-8 w-8 opacity-50" />
                <p className="text-sm">Belum ada data lokasi pada tingkat ini.</p>
              </div>
            ) : (
              <div className="space-y-2">
                {buckets.map((bucket) => {
                  const isUnknown = bucket.key === UNKNOWN_LOCATION_KEY;
                  const canDrill = !isUnknown && level !== 'district';
                  const percentage = scopeTotal ? Math.round((bucket.count / scopeTotal) * 100) : 0;
                  return (
                    <button
                      key={bucket.key}
                      type="button"
                      onClick={() => level === 'province' ? goToProvince(bucket.key) : level === 'city' ? goToCity(bucket.key) : undefined}
                      disabled={!canDrill}
                      aria-label={`${bucket.name}: ${formatCount(bucket.count)} pengguna${canDrill ? ', lihat rincian' : ''}`}
                      className={`group w-full rounded-lg border px-3 py-3 text-left transition-colors ${canDrill ? 'hover:border-primary/40 hover:bg-primary/[0.03]' : 'cursor-default'} ${isUnknown ? 'bg-muted/40' : 'bg-card'}`}
                    >
                      <div className="mb-2 flex items-center justify-between gap-4">
                        <span className="flex min-w-0 items-center gap-2 truncate text-sm font-medium">
                          {level === 'province' ? <MapPin className="h-4 w-4 shrink-0 text-primary" /> : <Building2 className="h-4 w-4 shrink-0 text-primary" />}
                          <span className="truncate">{bucket.name}</span>
                          {isUnknown && <Badge variant="outline" className="shrink-0 text-[10px]">Tidak diketahui</Badge>}
                        </span>
                        <span className="flex shrink-0 items-center gap-2 text-sm">
                          <span className="font-semibold">{formatCount(bucket.count)}</span>
                          <span className="w-10 text-right text-xs text-muted-foreground">{percentage}%</span>
                          {canDrill && <span className="text-xs text-primary opacity-0 transition-opacity group-hover:opacity-100">Rincian →</span>}
                        </span>
                      </div>
                      <div className="h-2 overflow-hidden rounded-full bg-muted">
                        <div className={`h-full rounded-full transition-all ${isUnknown ? 'bg-slate-400' : 'bg-primary'}`} style={{ width: `${Math.max(2, (bucket.count / maxCount) * 100)}%` }} />
                      </div>
                    </button>
                  );
                })}
              </div>
            )}
            <p className="mt-5 border-t pt-4 text-xs leading-relaxed text-muted-foreground">
              Sumber: lokasi provinsi, kota/kabupaten, dan kecamatan pada profil pengguna. Pengguna tanpa nama wilayah masuk kategori “Belum diisi”; data alamat rinci dan identitas pribadi tidak ditampilkan.
            </p>
          </CardContent>
        </Card>
      </div>
    </AdminLayout>
  );
}
