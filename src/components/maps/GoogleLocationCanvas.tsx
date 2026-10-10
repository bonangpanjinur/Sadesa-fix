import { useEffect, useRef, useState } from 'react';
import { Loader2 } from 'lucide-react';
import { loadGoogleMaps } from '@/lib/googleMaps';

interface Point {
  lat: number;
  lng: number;
}

interface GoogleLocationCanvasProps {
  center: Point;
  value: Point | null;
  disabled?: boolean;
  onSelect: (point: Point) => void;
  onReady: () => void;
  onFailure: () => void;
}

export function GoogleLocationCanvas({
  center,
  value,
  disabled,
  onSelect,
  onReady,
  onFailure,
}: GoogleLocationCanvasProps) {
  const elementRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<google.maps.Map | null>(null);
  const markerRef = useRef<google.maps.Marker | null>(null);
  const clickListenerRef = useRef<google.maps.MapsEventListener | null>(null);
  const onSelectRef = useRef(onSelect);
  const disabledRef = useRef(disabled);
  const [loading, setLoading] = useState(true);

  onSelectRef.current = onSelect;
  disabledRef.current = disabled;

  useEffect(() => {
    let disposed = false;

    void loadGoogleMaps().then(() => {
      if (disposed || !elementRef.current) return;
      const map = new google.maps.Map(elementRef.current, {
        center,
        zoom: 15,
        mapTypeControl: false,
        streetViewControl: false,
        fullscreenControl: false,
        clickableIcons: false,
        gestureHandling: disabled ? 'cooperative' : 'greedy',
      });
      const marker = new google.maps.Marker({
        map,
        position: value ?? center,
        draggable: !disabled,
        title: 'Lokasi pengiriman',
      });
      mapRef.current = map;
      markerRef.current = marker;
      clickListenerRef.current = map.addListener('click', (event: google.maps.MapMouseEvent) => {
        if (disabledRef.current || !event.latLng) return;
        onSelectRef.current({ lat: event.latLng.lat(), lng: event.latLng.lng() });
      });
      marker.addListener('dragend', () => {
        if (disabledRef.current) return;
        const position = marker.getPosition();
        if (position) onSelectRef.current({ lat: position.lat(), lng: position.lng() });
      });
      setLoading(false);
      onReady();
    }).catch(() => {
      if (!disposed) onFailure();
    });

    return () => {
      disposed = true;
      clickListenerRef.current?.remove();
      clickListenerRef.current = null;
      markerRef.current?.setMap(null);
      markerRef.current = null;
      if (mapRef.current) google.maps.event.clearInstanceListeners(mapRef.current);
      mapRef.current = null;
    };
    // Map initialization is intentionally one-time. Mutable props are read
    // through refs and updated by the effect below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    map.setCenter(center);
    map.setZoom(15);
    markerRef.current?.setPosition(value ?? center);
    markerRef.current?.setDraggable(!disabled);
    map.setOptions({ gestureHandling: disabled ? 'cooperative' : 'greedy' });
  }, [center, disabled, value]);

  return (
    <div className="relative h-full min-h-[220px] w-full sm:min-h-[280px]">
      <div ref={elementRef} className="h-full min-h-[220px] w-full sm:min-h-[280px]" />
      {loading && (
        <div className="absolute inset-0 flex items-center justify-center bg-muted/80">
          <div className="flex items-center gap-2 rounded-full bg-background px-4 py-2 text-xs shadow">
            <Loader2 className="h-4 w-4 animate-spin text-primary" />
            Memuat Google Maps…
          </div>
        </div>
      )}
    </div>
  );
}
