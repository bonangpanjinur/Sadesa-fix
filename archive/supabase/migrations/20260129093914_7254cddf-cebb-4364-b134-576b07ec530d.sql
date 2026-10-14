-- Insert homepage layout settings into app_settings table
INSERT INTO public.app_settings (key, value, category, description)
VALUES
  ('homepage_layout', '{
    "sections": [
      {"id": "hero", "name": "Hero Banner", "enabled": true, "order": 0},
      {"id": "categories", "name": "Kategori", "enabled": true, "order": 1},
      {"id": "popular_tourism", "name": "Wisata Populer", "enabled": true, "order": 2},
      {"id": "promo", "name": "Promo Spesial", "enabled": true, "order": 3},
      {"id": "recommendations", "name": "Rekomendasi Pilihan", "enabled": true, "order": 4},
      {"id": "villages", "name": "Jelajahi Desa", "enabled": true, "order": 5}
    ],
    "visible_categories": ["kuliner", "fashion", "kriya", "wisata"]
  }'::jsonb, 'display', 'Pengaturan tampilan dan urutan section di homepage')
ON CONFLICT (key) DO NOTHING$bootstrap_sql_b33c46c90c74$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b33c46c90c74$;

DO $bootstrap_do_6de88541714f$
BEGIN
  EXECUTE $bootstrap_sql_6de88541714f$
