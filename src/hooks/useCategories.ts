import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';

export interface CategoryItem {
  id: string;
  name: string;
  slug: string;
  icon: string | null;
  description: string | null;
}

export interface HomepageCategoryItem {
  id: string;
  name: string;
  icon: string;
  colorClass: string;
  route?: string;
}

// Map emoji/icon from DB to lucide icon key for homepage display
const iconMap: Record<string, string> = {
  '🍔': 'utensils',
  '🍜': 'utensils',
  '🥘': 'utensils',
  '🍽': 'utensils',
  '👕': 'shirt',
  '👗': 'shirt',
  '🎨': 'shapes',
  '🏺': 'shapes',
  '🧶': 'shapes',
  '🗺': 'map-location-dot',
  '🏔': 'map-location-dot',
  '🏖': 'map-location-dot',
  '🛒': 'shopping-basket',
  '🥬': 'sprout',
  '🌾': 'sprout',
  '🐟': 'wheat',
  '🔧': 'wrench',
  '🗺️': 'map-location-dot',
};

const categoryStyles: Record<string, { icon: string; colorClass: string; route?: string }> = {
  makanan: { icon: 'utensils', colorClass: 'bg-orange-100 text-orange-700 border-orange-200' },
  kuliner: { icon: 'utensils', colorClass: 'bg-orange-100 text-orange-700 border-orange-200' },
  minuman: { icon: 'utensils', colorClass: 'bg-rose-100 text-rose-700 border-rose-200' },
  sembako: { icon: 'shopping-basket', colorClass: 'bg-amber-100 text-amber-700 border-amber-200' },
  sayuran: { icon: 'sprout', colorClass: 'bg-green-100 text-green-700 border-green-200' },
  pertanian: { icon: 'sprout', colorClass: 'bg-green-100 text-green-700 border-green-200' },
  wisata: { icon: 'map-location-dot', colorClass: 'bg-cyan-100 text-cyan-700 border-cyan-200', route: '/tourism' },
  jasa: { icon: 'wrench', colorClass: 'bg-blue-100 text-blue-700 border-blue-200' },
  peternakan: { icon: 'wheat', colorClass: 'bg-lime-100 text-lime-700 border-lime-200' },
  ojek: { icon: 'bike', colorClass: 'bg-emerald-100 text-emerald-700 border-emerald-200', route: '/ride' },
};

const colorClasses = [
  'bg-orange-100 text-orange-700 border-orange-200',
  'bg-amber-100 text-amber-700 border-amber-200',
  'bg-teal-100 text-teal-700 border-teal-200',
  'bg-cyan-100 text-cyan-700 border-cyan-200',
  'bg-blue-100 text-blue-700 border-blue-200',
  'bg-green-100 text-green-700 border-green-200',
  'bg-lime-100 text-lime-700 border-lime-200',
  'bg-emerald-100 text-emerald-700 border-emerald-200',
];

export function useCategories() {
  const [categories, setCategories] = useState<CategoryItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void fetchCategories();
  }, []);

  const fetchCategories = async () => {
    setError(null);
    try {
      const { data, error } = await supabase
        .from('categories')
        .select('id, name, slug, icon, description')
        .eq('is_active', true)
        .order('sort_order', { ascending: true });

      if (error) throw error;
      setCategories(data || []);
    } catch (error) {
      console.error('Error fetching categories:', error);
      setError('Kategori belum dapat dimuat');
    } finally {
      setLoading(false);
    }
  };

  // Get categories formatted for homepage display
  const getHomepageCategories = (): HomepageCategoryItem[] => {
    return categories.map((cat, index) => ({
      id: cat.slug,
      name: cat.name,
      icon: (cat.icon ? iconMap[cat.icon] : null) || categoryStyles[cat.slug]?.icon || getDefaultIcon(index),
      colorClass: categoryStyles[cat.slug]?.colorClass || colorClasses[index % colorClasses.length],
      route: categoryStyles[cat.slug]?.route,
    }));
  };

  return { categories, loading, error, getHomepageCategories, refetch: fetchCategories };
}

function getDefaultIcon(index: number): string {
  const defaults = ['utensils', 'shopping-basket', 'shapes', 'map-location-dot', 'wrench', 'sprout', 'wheat', 'bike'];
  return defaults[index % defaults.length];
}
