import { useEffect, useRef, useState } from 'react';
import { Loader2, MapPin, Search } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { searchAddressSuggestions, type AddressSuggestion } from '@/hooks/useGeocoding';

type Point = { lat: number; lng: number };

interface NominatimAddressInputProps {
  id: string;
  value: string;
  placeholder: string;
  className?: string;
  onChange: (value: string) => void;
  onFocus: () => void;
  onPlaceSelected: (place: { address: string; location: Point }) => void;
}

export function NominatimAddressInput({
  id,
  value,
  placeholder,
  className,
  onChange,
  onFocus,
  onPlaceSelected,
}: NominatimAddressInputProps) {
  const [suggestions, setSuggestions] = useState<AddressSuggestion[]>([]);
  const [loading, setLoading] = useState(false);
  const [open, setOpen] = useState(false);
  const typingRef = useRef(false);
  const requestIdRef = useRef(0);

  useEffect(() => {
    if (!typingRef.current) return;
    const query = value.trim();
    if (query.length < 3) {
      setSuggestions([]);
      setOpen(false);
      return;
    }

    const requestId = ++requestIdRef.current;
    const timer = window.setTimeout(async () => {
      setLoading(true);
      const results = await searchAddressSuggestions(query);
      if (requestId === requestIdRef.current) {
        setSuggestions(results);
        setOpen(results.length > 0);
        setLoading(false);
      }
    }, 550);

    return () => window.clearTimeout(timer);
  }, [value]);

  const handleChange = (nextValue: string) => {
    typingRef.current = true;
    onChange(nextValue);
    setOpen(nextValue.trim().length >= 3);
  };

  const handleSelect = (suggestion: AddressSuggestion) => {
    typingRef.current = false;
    setSuggestions([]);
    setOpen(false);
    onPlaceSelected({
      address: suggestion.displayName || value,
      location: { lat: suggestion.lat, lng: suggestion.lng },
    });
  };

  return (
    <div className="relative min-w-0 flex-1">
      <div className="relative">
        <Input
          id={id}
          type="text"
          inputMode="text"
          autoComplete="off"
          placeholder={placeholder}
          value={value}
          onFocus={onFocus}
          onChange={(event) => handleChange(event.target.value)}
          className={className}
          onBlur={() => window.setTimeout(() => setOpen(false), 150)}
        />
        {loading && <Loader2 className="pointer-events-none absolute right-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 animate-spin text-primary" />}
      </div>
      {open && suggestions.length > 0 && (
        <div className="absolute left-0 right-0 top-[calc(100%+6px)] z-[1200] overflow-hidden rounded-xl border border-border bg-background shadow-xl">
          <div className="flex items-center gap-1.5 border-b border-border/70 px-3 py-2 text-[10px] font-semibold text-muted-foreground">
            <Search className="h-3 w-3 text-primary" /> Pilih alamat dari OpenStreetMap
          </div>
          {suggestions.map((suggestion) => (
            <button
              key={suggestion.id}
              type="button"
              className="flex w-full items-start gap-2 border-b border-border/50 px-3 py-2.5 text-left last:border-0 hover:bg-muted/70"
              onMouseDown={(event) => event.preventDefault()}
              onClick={() => handleSelect(suggestion)}
            >
              <MapPin className="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary" />
              <span className="line-clamp-2 text-xs leading-relaxed text-foreground">{suggestion.displayName}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
