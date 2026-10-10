import { useState, useEffect, useCallback } from 'react';
import { MapPin, Loader2, LocateFixed, Navigation, AlertCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { getDeliveryDistanceKm } from '@/lib/routeCalculation';
import { MapContainer, TileLayer, Marker, useMapEvents, useMap } from 'react-leaflet';
import { useTranslation } from '@/lib/i18n';
import { isGoogleMapsBrowserKeyConfigured } from '@/lib/googleMaps';
import { GoogleLocationCanvas } from '@/components/maps/GoogleLocationCanvas';
import L from 'leaflet';

// Checkout delivery point uses a location pin, not a vehicle icon.
delete (L.Icon.Default.prototype as unknown as { _getIconUrl?: unknown })._getIconUrl;
L.Icon.Default.mergeOptions({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-blue.png',
  iconRetinaUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-blue.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-shadow.png',
  iconSize: [25, 41],
  iconAnchor: [12, 41],
  popupAnchor: [1, -34],
});

interface LocationPickerProps {
  value: { lat: number; lng: number } | null;
  onChange: (location: { lat: number; lng: number }) => void;
  merchantLocation?: { lat: number; lng: number } | null;
  onDistanceChange?: (distanceKm: number | null) => void;
  onDistanceSourceChange?: (source: 'google' | 'fallback' | 'straight-line' | 'calculating' | null) => void;
  onLocationSelected?: (lat: number, lng: number) => void;
  onLocationSourceChange?: (source: 'gps' | 'manual') => void;
  disabled?: boolean;
  externalCenter?: { lat: number; lng: number } | null;
}

// Component to handle map clicks
function MapClickHandler({ onLocationSelect }: { onLocationSelect: (lat: number, lng: number) => void }) {
  useMapEvents({
    click(e) {
      onLocationSelect(e.latlng.lat, e.latlng.lng);
    },
  });
  return null;
}

// Component to recenter map when external center changes
function MapCenterUpdater({ center, zoom }: { center: { lat: number; lng: number }; zoom?: number }) {
  const map = useMap();
  
  useEffect(() => {
    map.setView([center.lat, center.lng], zoom || map.getZoom(), { animate: true });
  }, [center.lat, center.lng, zoom, map]);
  
  return null;
}

export function LocationPicker({
  value,
  onChange,
  merchantLocation,
  onDistanceChange,
  onDistanceSourceChange,
  onLocationSelected,
  onLocationSourceChange,
  disabled,
  externalCenter,
}: LocationPickerProps) {
  const { t } = useTranslation();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [googleMapFailed, setGoogleMapFailed] = useState(!isGoogleMapsBrowserKeyConfigured());
  const [mapCenter, setMapCenter] = useState<{ lat: number; lng: number }>({ lat: -7.3274, lng: 108.2207 });
  
  // Update map center when external center changes (from address geocoding)
  useEffect(() => {
    if (externalCenter) {
      setMapCenter(externalCenter);
    }
  }, [externalCenter]);

  // Calculate the drivable delivery distance. Abort old requests so a slower
  // response for a previous pin can never overwrite the current checkout.
  useEffect(() => {
    if (!value || !merchantLocation || !onDistanceChange) {
      onDistanceChange?.(null);
      onDistanceSourceChange?.(null);
      return;
    }
    const controller = new AbortController();
    onDistanceChange(null);
    onDistanceSourceChange?.('calculating');
    const timeout = window.setTimeout(() => {
      void getDeliveryDistanceKm(merchantLocation, value, controller.signal)
        .then(({ distanceKm, source }) => {
          if (controller.signal.aborted) return;
          onDistanceChange(distanceKm);
          onDistanceSourceChange?.(source);
        })
        .catch((error) => {
          if (error instanceof DOMException && error.name === 'AbortError') return;
          console.error('Delivery distance calculation failed:', error);
        });
    }, 350);
    return () => {
      window.clearTimeout(timeout);
      controller.abort();
    };
  }, [value, merchantLocation, onDistanceChange, onDistanceSourceChange]);

  const handleGetCurrentLocation = useCallback(() => {
    if (!navigator.geolocation) {
      setError(t('checkout.location.gpsUnsupported'));
      return;
    }

    setLoading(true);
    setError(null);

    navigator.geolocation.getCurrentPosition(
      (position) => {
        const location = {
          lat: position.coords.latitude,
          lng: position.coords.longitude,
        };
        onChange(location);
        onLocationSourceChange?.('gps');
        setMapCenter(location);
        
        // Notify parent to update address based on coordinates
        if (onLocationSelected) {
          onLocationSelected(location.lat, location.lng);
        }
        
        setLoading(false);
      },
      (err) => {
        console.error('Geolocation error:', err);
        setError(t('checkout.location.gpsFailed'));
        setLoading(false);
      },
      {
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 0,
      }
    );
  }, [onChange, onLocationSelected, onLocationSourceChange, t]);

  const handleMapClick = useCallback((lat: number, lng: number) => {
    if (!disabled) {
      const location = { lat, lng };
      onChange(location);
      onLocationSourceChange?.('manual');
      
      // Notify parent to update address based on coordinates
      if (onLocationSelected) {
        onLocationSelected(lat, lng);
      }
    }
  }, [onChange, onLocationSelected, onLocationSourceChange, disabled]);

  return (
    <div className="space-y-3">
      {/* Header with action buttons */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <MapPin className="h-4 w-4 text-primary" />
          <span className="text-sm font-medium">{t('checkout.address.locationTitle')}</span>
        </div>
        <div className="flex gap-2">
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={handleGetCurrentLocation}
            disabled={loading || disabled}
            title={t('checkout.location.gpsTitle')}
          >
            {loading ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <>
                <LocateFixed className="h-4 w-4 mr-1" />
                <span className="hidden sm:inline">{t('checkout.location.useGps')}</span>
                <span className="sm:hidden">{t('checkout.location.gpsShort')}</span>
              </>
            )}
          </Button>
        </div>
      </div>

      {/* Error message */}
      {error && (
        <div className="rounded-lg border border-destructive/50 bg-destructive/5 p-3 flex items-start gap-2">
          <AlertCircle className="h-4 w-4 text-destructive mt-0.5 flex-shrink-0" />
          <p className="text-xs text-destructive">{error}</p>
        </div>
      )}

      {/* OpenStreetMap Container - Enhanced UI */}
      <div 
        className="relative h-[220px] overflow-hidden rounded-lg border-2 border-primary/30 bg-muted shadow-sm transition-colors hover:border-primary/50 sm:h-[280px] cursor-crosshair"
        style={{ width: '100%', zIndex: 0 }}
      >
        {isGoogleMapsBrowserKeyConfigured() && !googleMapFailed ? (
          <GoogleLocationCanvas
            center={mapCenter}
            value={value}
            disabled={disabled}
            onSelect={(point) => handleMapClick(point.lat, point.lng)}
            onReady={() => undefined}
            onFailure={() => setGoogleMapFailed(true)}
          />
        ) : (
        <>
        <style>
          {`
            .leaflet-container {
              height: 100% !important;
              width: 100% !important;
              z-index: 0 !important;
              cursor: crosshair !important;
            }
            .leaflet-container.leaflet-touch-zoom {
              cursor: grab !important;
            }
            .leaflet-container.leaflet-touch-zoom.leaflet-dragging {
              cursor: grabbing !important;
            }
            .leaflet-pane { z-index: 1 !important; }
            .leaflet-tile-pane { z-index: 1 !important; }
            .leaflet-overlay-pane { z-index: 2 !important; }
            .leaflet-marker-pane { z-index: 3 !important; }
            .leaflet-tooltip-pane { z-index: 4 !important; }
            .leaflet-popup-pane { z-index: 5 !important; }
            .leaflet-control-container { z-index: 6 !important; }
            .leaflet-top, .leaflet-bottom { z-index: 6 !important; }
            .leaflet-tile { position: absolute; }
            .leaflet-marker-icon {
              filter: drop-shadow(0 2px 4px rgba(0, 0, 0, 0.2));
            }
          `}
        </style>
        <MapContainer
          center={[mapCenter.lat, mapCenter.lng]}
          zoom={15}
          scrollWheelZoom={true}
          style={{ height: '100%', width: '100%', position: 'relative' }}
          attributionControl={true}
        >
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
          <MapClickHandler onLocationSelect={handleMapClick} />
          <MapCenterUpdater center={mapCenter} />
          {value && (
            <Marker position={[value.lat, value.lng]} />
          )}
        </MapContainer>
        </>
        )}
      </div>
      {googleMapFailed && isGoogleMapsBrowserKeyConfigured() && (
        <p className="text-xs text-muted-foreground" role="status">
          Google Maps belum tersedia; peta cadangan OpenStreetMap aktif.
        </p>
      )}

      {/* Helper text is collapsible on mobile to keep the address flow short. */}
      <details className="group rounded-lg border border-blue-200 bg-blue-50 p-3 text-xs text-blue-700">
        <summary className="flex cursor-pointer list-none items-center gap-2 font-medium [&::-webkit-details-marker]:hidden">
          <Navigation className="h-4 w-4 flex-shrink-0" />
          <span>{t('checkout.location.instructions')}</span>
          <span className="ml-auto text-blue-500 transition group-open:rotate-180">⌄</span>
        </summary>
        <ul className="mt-2 list-disc space-y-0.5 pl-5">
          <li>{t('checkout.location.manualStart')}</li>
          <li>{t('checkout.location.refine')}</li>
        </ul>
      </details>
      <p className="text-xs text-muted-foreground">
        Untuk menghitung rute dan membantu mengenali alamat, titik lokasi dapat diproses oleh Google Maps. Jika layanan tidak tersedia, aplikasi memakai layanan peta cadangan.
      </p>

      {/* Location status - Enhanced */}
      <div className="rounded-lg border p-3 bg-card">
        {value ? (
          <div className="space-y-3">
            <div className="flex items-center gap-2 text-primary">
              <div className="h-2 w-2 rounded-full bg-green-500 animate-pulse" />
              <span className="text-sm font-semibold">{t('checkout.location.selected')}</span>
            </div>
            <div className="grid grid-cols-2 gap-2 text-[11px]">
              <div className="bg-muted p-2 rounded">
                <p className="text-muted-foreground">{t('checkout.location.latitude')}</p>
                <p className="font-mono font-medium">{value.lat.toFixed(6)}</p>
              </div>
              <div className="bg-muted p-2 rounded">
                <p className="text-muted-foreground">{t('checkout.location.longitude')}</p>
                <p className="font-mono font-medium">{value.lng.toFixed(6)}</p>
              </div>
            </div>
            <p className="text-xs text-muted-foreground">
              {t('checkout.location.accuracy')}
            </p>
          </div>
        ) : (
          <div className="text-center py-4">
            <MapPin className="h-8 w-8 text-muted-foreground/50 mx-auto mb-2" />
            <p className="text-sm font-medium text-muted-foreground">{t('checkout.location.none')}</p>
            <p className="text-xs text-muted-foreground mt-1">
              {t('checkout.location.clickToStart')}
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
