import { useEffect, useState } from 'react';
import { Check, Filter, Leaf, RotateCcw, Store, Tag } from 'lucide-react';
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import { Slider } from '@/components/ui/slider';
import { ScrollArea } from '@/components/ui/scroll-area';
import { defaultFoodFilters } from './foodFilters';
import type { CategoryFilterOption, FoodFilters, FoodType } from './foodFilters';
export type { CategoryFilterOption, FoodFilters, FoodType } from './foodFilters';

interface FoodFilterSheetProps {
  filters: FoodFilters;
  onFiltersChange: (filters: FoodFilters) => void;
  activeFilterCount: number;
  categories?: CategoryFilterOption[];
  title?: string;
  description?: string;
  showHalal?: boolean;
  resetType?: FoodType;
  foodOnly?: boolean;
  primaryCategory?: { slug: string; name: string };
}

export function FoodFilterSheet({
  filters,
  onFiltersChange,
  activeFilterCount,
  categories = [],
  title = 'Filter katalog',
  description = 'Temukan produk lokal yang paling sesuai dengan kebutuhanmu.',
  showHalal = true,
  resetType = 'all',
  foodOnly = false,
  primaryCategory = { slug: 'kuliner', name: 'Makanan & Minuman' },
}: FoodFilterSheetProps) {
  const [open, setOpen] = useState(false);
  const [localFilters, setLocalFilters] = useState(filters);

  useEffect(() => setLocalFilters(filters), [filters]);

  const update = (patch: Partial<FoodFilters>) => setLocalFilters((previous) => ({ ...previous, ...patch }));

  const apply = () => {
    onFiltersChange(localFilters);
    setOpen(false);
  };

  const reset = () => {
    const nextFilters = { ...defaultFoodFilters, type: resetType };
    setLocalFilters(nextFilters);
    onFiltersChange(nextFilters);
  };

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger asChild>
        <Button variant="outline" className="relative h-11 shrink-0 rounded-2xl px-3">
          <Filter className="mr-1.5 h-4 w-4" />
          Filter
          {activeFilterCount > 0 && (
            <Badge variant="destructive" className="absolute -right-2 -top-2 h-5 min-w-5 justify-center px-1 text-[10px]">
              {activeFilterCount}
            </Badge>
          )}
        </Button>
      </SheetTrigger>
      <SheetContent side="right" className="w-full sm:max-w-md">
        <SheetHeader>
          <SheetTitle className="flex items-center gap-2"><Filter className="h-5 w-5" /> {title}</SheetTitle>
          <SheetDescription>{description}</SheetDescription>
        </SheetHeader>

        <ScrollArea className="mt-5 h-[calc(100vh-210px)] pr-4">
          <div className="space-y-7">
            <section className="space-y-3">
              <Label className="text-sm font-semibold">Kategori produk</Label>
              <div className="grid grid-cols-2 gap-2">
                {[{ slug: 'all', name: 'Semua produk' }, primaryCategory, ...(foodOnly ? [] : [{ slug: primaryCategory.slug === 'kuliner' ? 'belanja' : 'kuliner', name: primaryCategory.slug === 'kuliner' ? 'Belanja' : 'Makanan & Minuman' }]), ...categories.filter((category) => !['kuliner', 'belanja'].includes(category.slug))].map(({ slug, name }) => (
                  <Button key={slug} type="button" variant={localFilters.type === slug ? 'default' : 'outline'} className="justify-start" onClick={() => update({ type: slug })}>
                    {localFilters.type === slug && <Check className="mr-2 h-4 w-4" />}
                    {name}
                  </Button>
                ))}
              </div>
            </section>

            <section className="space-y-3">
              <Label className="text-sm font-semibold">Preferensi</Label>
              <label className="flex cursor-pointer items-center gap-3 rounded-xl border p-3">
                <Checkbox checked={localFilters.openNow} onCheckedChange={(checked) => update({ openNow: checked === true })} />
                <Store className="h-4 w-4 text-green-600" />
                <span className="text-sm">Buka sekarang</span>
              </label>
              <label className="flex cursor-pointer items-center gap-3 rounded-xl border p-3">
                <Checkbox checked={localFilters.promoOnly} onCheckedChange={(checked) => update({ promoOnly: checked === true })} />
                <Tag className="h-4 w-4 text-primary" />
                <span className="text-sm">Sedang promo</span>
              </label>
              {showHalal && (
                <label className="flex cursor-pointer items-center gap-3 rounded-xl border p-3">
                  <Checkbox checked={localFilters.halalOnly} onCheckedChange={(checked) => update({ halalOnly: checked === true })} />
                  <Leaf className="h-4 w-4 text-green-600" />
                  <span className="text-sm">Halal terverifikasi</span>
                </label>
              )}
            </section>

            <section className="space-y-3">
              <Label className="text-sm font-semibold">Harga maksimal</Label>
              <Slider value={[localFilters.maxPrice]} min={5000} max={100000} step={5000} onValueChange={([value]) => update({ maxPrice: value })} />
              <div className="flex justify-between text-xs text-muted-foreground">
                <span>Rp5.000</span>
                <span className="font-semibold text-foreground">{localFilters.maxPrice >= 100000 ? 'Semua harga' : `sampai Rp${localFilters.maxPrice.toLocaleString('id-ID')}`}</span>
                <span>Rp100.000</span>
              </div>
            </section>
          </div>
        </ScrollArea>

        <div className="mt-4 flex gap-3 border-t pt-4">
          <Button variant="outline" className="flex-1" onClick={reset}><RotateCcw className="mr-2 h-4 w-4" />Reset</Button>
          <Button className="flex-1" onClick={apply}>Terapkan filter</Button>
        </div>
      </SheetContent>
    </Sheet>
  );
}
