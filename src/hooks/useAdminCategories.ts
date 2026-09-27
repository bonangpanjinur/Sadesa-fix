import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { ProductCategory } from '@/lib/productCategories';

export type AdminCategory = ProductCategory;

export const ADMIN_CATEGORIES_QUERY_KEY = ['admin-categories', 'active'] as const;

async function fetchActiveAdminCategories(): Promise<AdminCategory[]> {
  const { data, error } = await supabase
    .from('categories')
    .select('id, slug, name, parent_id, icon, description, sort_order')
    .eq('is_active', true)
    .order('sort_order', { ascending: true })
    .order('name', { ascending: true });

  if (error) throw error;
  return (data || []) as AdminCategory[];
}

export function useAdminCategories() {
  return useQuery({
    queryKey: ADMIN_CATEGORIES_QUERY_KEY,
    queryFn: fetchActiveAdminCategories,
    staleTime: 60_000,
  });
}

export function getCategorySlugs(categories: AdminCategory[]): string[] {
  return categories.map((category) => category.slug);
}

export function isActiveAdminCategory(slug: string, categories: AdminCategory[]): boolean {
  return categories.some((category) => category.slug === slug);
}

export { fetchActiveAdminCategories };
