import { useEffect, useRef } from 'react';
import { Input } from '@/components/ui/input';
import { isGoogleMapsRideEnabled, loadGoogleMaps } from '@/lib/googleMaps';

type Point = { lat: number; lng: number };

interface GoogleAddressInputProps {
  id: string;
  value: string;
  placeholder: string;
  className?: string;
  onChange: (value: string) => void;
  onFocus: () => void;
  onPlaceSelected: (place: { address: string; location: Point }) => void;
}

export function GoogleAddressInput({
  id,
  value,
  placeholder,
  className,
  onChange,
  onFocus,
  onPlaceSelected,
}: GoogleAddressInputProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const onPlaceSelectedRef = useRef(onPlaceSelected);
  onPlaceSelectedRef.current = onPlaceSelected;

  useEffect(() => {
    let disposed = false;
    if (!isGoogleMapsRideEnabled()) return;
    loadGoogleMaps().then(() => {
      if (disposed || !inputRef.current || !google.maps.places) return;
      const autocomplete = new google.maps.places.Autocomplete(inputRef.current, {
        componentRestrictions: { country: 'id' },
        fields: ['formatted_address', 'geometry', 'name'],
        types: ['geocode', 'establishment'],
      });
      autocomplete.addListener('place_changed', () => {
        const place = autocomplete.getPlace();
        const location = place.geometry?.location;
        if (!location) return;
        onPlaceSelectedRef.current({
          address: place.formatted_address || place.name || inputRef.current?.value || '',
          location: { lat: location.lat(), lng: location.lng() },
        });
      });
    }).catch(() => {
      // The field remains usable as a normal text input when the API key is absent
      // or the Places API is not enabled; map selection remains available.
    });

    return () => { disposed = true; };
  }, []);

  return (
    <Input
      ref={inputRef}
      id={id}
      type="text"
      inputMode="text"
      autoComplete="off"
      placeholder={placeholder}
      value={value}
      onFocus={onFocus}
      onChange={(event) => onChange(event.target.value)}
      className={className}
    />
  );
}
