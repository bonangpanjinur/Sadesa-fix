import { useEffect, useState } from 'react';
import { SlidersHorizontal, MapPin, Banknote, Star } from 'lucide-react';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip';

export interface FilterOptions {
  priceRange: [number, number] | null;
  districts: string[];
  minRating: number | null;
}

interface FilterSheetProps {
  isOpen: boolean;
  onClose: () => void;
  filters: FilterOptions;
  onApplyFilters: (filters: FilterOptions) => void;
  availableDistricts: string[];
}

const priceRanges: { label: string; value: [number, number] }[] = [
  { label: '< Rp 10.000', value: [0, 10000] },
  { label: 'Rp 10.000 - 25.000', value: [10000, 25000] },
  { label: 'Rp 25.000 - 50.000', value: [25000, 50000] },
  { label: 'Rp 50.000 - 100.000', value: [50000, 100000] },
  { label: '> Rp 100.000', value: [100000, 999999999] },
];

const ratingOptions = [4, 3, 2, 1];

export function FilterSheet({ 
  isOpen, 
  onClose, 
  filters, 
  onApplyFilters,
  availableDistricts 
}: FilterSheetProps) {
  const [localFilters, setLocalFilters] = useState<FilterOptions>(filters);

  useEffect(() => {
    if (isOpen) setLocalFilters(filters);
  }, [filters, isOpen]);

  const handlePriceSelect = (range: [number, number]) => {
    const isSame = localFilters.priceRange?.[0] === range[0] && localFilters.priceRange?.[1] === range[1];
    setLocalFilters(prev => ({
      ...prev,
      priceRange: isSame ? null : range
    }));
  };

  const handleDistrictToggle = (district: string) => {
    setLocalFilters(prev => ({
      ...prev,
      districts: prev.districts.includes(district)
        ? prev.districts.filter(d => d !== district)
        : [...prev.districts, district]
    }));
  };

  const handleRatingSelect = (rating: number) => {
    setLocalFilters(prev => ({
      ...prev,
      minRating: prev.minRating === rating ? null : rating
    }));
  };

  const handleApply = () => {
    onApplyFilters(localFilters);
    onClose();
  };

  const handleReset = () => {
    const resetFilters: FilterOptions = {
      priceRange: null,
      districts: [],
      minRating: null
    };
    setLocalFilters(resetFilters);
    onApplyFilters(resetFilters);
  };

  const activeFilterCount = 
    (localFilters.priceRange ? 1 : 0) + 
    (localFilters.districts.length > 0 ? 1 : 0) + 
    (localFilters.minRating ? 1 : 0);

  return (
      <Dialog open={isOpen} onOpenChange={(open) => { if (!open) onClose(); }}>
          <DialogContent className="fixed bottom-0 left-0 right-0 top-auto grid max-h-[85dvh] w-full max-w-none grid-rows-[auto_1fr_auto] translate-x-0 translate-y-0 gap-0 overflow-hidden rounded-t-3xl p-0 sm:bottom-auto sm:left-1/2 sm:right-auto sm:top-1/2 sm:w-[calc(100%-2rem)] sm:max-w-lg sm:-translate-x-1/2 sm:-translate-y-1/2 sm:rounded-xl">
            <DialogHeader className="border-b border-border px-5 py-4 pr-14 text-left">
              <div className="flex items-center gap-2">
                <SlidersHorizontal aria-hidden="true" className="h-5 w-5 text-primary" />
                <DialogTitle className="font-bold text-lg">Filter</DialogTitle>
                {activeFilterCount > 0 && (
                  <span className="bg-primary text-primary-foreground text-xs px-2 py-0.5 rounded-full">
                    {activeFilterCount}
                  </span>
                )}
              </div>
              <DialogDescription className="sr-only">Pilih rentang harga, lokasi, dan rating minimum untuk menyaring produk.</DialogDescription>
            </DialogHeader>

            {/* Content */}
            <div className="min-h-0 overflow-y-auto px-5 py-4 space-y-6">
              {/* Price Range */}
              <div>
                <div className="flex items-center gap-2 mb-3">
                  <Banknote className="h-4 w-4 text-muted-foreground" />
                  <h3 className="font-semibold text-sm">Rentang Harga</h3>
                </div>
                <div className="flex flex-wrap gap-2">
                  {priceRanges.map((range) => {
                    const isSelected = localFilters.priceRange?.[0] === range.value[0] && 
                                       localFilters.priceRange?.[1] === range.value[1];
                    return (
                      <button
                        key={range.label}
                        type="button"
                        aria-pressed={isSelected}
                        onClick={() => handlePriceSelect(range.value)}
                        className={cn(
                          "px-3 py-1.5 rounded-full text-xs font-medium transition-all",
                          isSelected
                            ? "bg-primary text-primary-foreground"
                            : "bg-secondary text-muted-foreground hover:bg-secondary/80"
                        )}
                      >
                        {range.label}
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* District/Location */}
              {availableDistricts.length > 0 && (
                <div>
                  <div className="flex items-center gap-2 mb-3">
                    <MapPin className="h-4 w-4 text-muted-foreground" />
                    <h3 className="font-semibold text-sm">Lokasi / Kecamatan</h3>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {availableDistricts.map((district) => {
                      const isSelected = localFilters.districts.includes(district);
                      return (
                        <button
                          key={district}
                          type="button"
                          aria-pressed={isSelected}
                          onClick={() => handleDistrictToggle(district)}
                          className={cn(
                            "px-3 py-1.5 rounded-full text-xs font-medium transition-all",
                            isSelected
                              ? "bg-primary text-primary-foreground"
                              : "bg-secondary text-muted-foreground hover:bg-secondary/80"
                          )}
                        >
                          {district}
                        </button>
                      );
                    })}
                  </div>
                </div>
              )}

              {/* Rating */}
              <div>
                <div className="flex items-center gap-2 mb-3">
                  <Star className="h-4 w-4 text-muted-foreground" />
                  <h3 className="font-semibold text-sm">Rating Minimum</h3>
                </div>
                <div className="flex gap-2">
                  {ratingOptions.map((rating) => {
                    const isSelected = localFilters.minRating === rating;
                    return (
                      <button
                        key={rating}
                        type="button"
                        aria-pressed={isSelected}
                        onClick={() => handleRatingSelect(rating)}
                        className={cn(
                          "flex items-center gap-1 px-3 py-1.5 rounded-full text-xs font-medium transition-all",
                          isSelected
                            ? "bg-primary text-primary-foreground"
                            : "bg-secondary text-muted-foreground hover:bg-secondary/80"
                        )}
                      >
                        <Star className={cn("h-3 w-3", isSelected ? "fill-current" : "")} />
                        {rating}+
                      </button>
                    );
                  })}
                </div>
              </div>
            </div>

            {/* Footer Actions */}
            <div className="px-5 py-4 border-t border-border flex gap-3">
              <Button
                variant="outline"
                className="flex-1"
                onClick={handleReset}
              >
                Reset
              </Button>
              <Button
                className="flex-1"
                onClick={handleApply}
              >
                Terapkan Filter
              </Button>
            </div>
          </DialogContent>
      </Dialog>
  );
}

// Filter Button Component
interface FilterButtonProps {
  onClick: () => void;
  activeCount: number;
}

export function FilterButton({ onClick, activeCount }: FilterButtonProps) {
  return (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <button
            type="button"
            aria-label={activeCount > 0 ? `Filter, ${activeCount} filter aktif` : 'Filter produk'}
            onClick={onClick}
            className={cn(
              "relative flex items-center justify-center w-9 h-9 rounded-xl transition-all border",
              activeCount > 0
                ? "bg-primary text-primary-foreground border-primary"
                : "bg-background text-muted-foreground border-border hover:border-primary/50 hover:text-foreground"
            )}
          >
            <SlidersHorizontal className="h-4 w-4" />
            {activeCount > 0 && (
              <span className="absolute -top-1 -right-1 bg-primary-foreground text-primary text-[10px] w-4 h-4 rounded-full flex items-center justify-center font-medium shadow-sm">
                {activeCount}
              </span>
            )}
          </button>
        </TooltipTrigger>
        <TooltipContent side="bottom" className="text-xs">
          Filter
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  );
}
