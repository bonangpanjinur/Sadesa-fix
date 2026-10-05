import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { cloneDefaultHomepageLayout } from '@/lib/homepageLayout';

export interface HomepageSection {
  id: string;
  name: string;
  enabled: boolean;
  order: number;
}

export interface HomepageLayoutSettings {
  sections: HomepageSection[];
  visible_categories: string[];
}

export function useHomepageLayout() {
  const [settings, setSettings] = useState<HomepageLayoutSettings>(() => cloneDefaultHomepageLayout());
  // Start with defaults already usable so the homepage can paint immediately;
  // remote settings are applied as soon as they arrive.
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    loadSettings();
  }, []);

  const loadSettings = async () => {
    try {
      const { data, error } = await supabase
        .from('app_settings')
        .select('value')
        .eq('key', 'homepage_layout')
        .maybeSingle();

      if (error) {
        console.error('Error loading homepage layout:', error);
        return;
      }

      if (data?.value) {
        const loadedSettings = data.value as unknown as HomepageLayoutSettings;
        const defaults = cloneDefaultHomepageLayout();
        setSettings({
          sections: loadedSettings.sections?.slice().sort((a, b) => a.order - b.order) || defaults.sections,
          visible_categories: loadedSettings.visible_categories || defaults.visible_categories,
        });
      }
    } catch (error) {
      console.error('Error loading homepage layout:', error);
    } finally {
      setLoading(false);
    }
  };

  const isSectionEnabled = (sectionId: string): boolean => {
    const section = settings.sections.find(s => s.id === sectionId);
    return section?.enabled ?? true;
  };

  const getSectionOrder = (sectionId: string): number => {
    const section = settings.sections.find(s => s.id === sectionId);
    return section?.order ?? 0;
  };

  const getEnabledSections = (): HomepageSection[] => {
    return settings.sections
      .filter(s => s.enabled)
      .slice()
      .sort((a, b) => a.order - b.order);
  };

  const isCategoryVisible = (categoryId: string): boolean => {
    return settings.visible_categories.includes(categoryId);
  };

  return {
    settings,
    loading,
    isSectionEnabled,
    getSectionOrder,
    getEnabledSections,
    isCategoryVisible,
    visibleCategories: settings.visible_categories,
  };
}
