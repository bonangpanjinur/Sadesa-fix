-- Seed hierarki kategori Pertanian.
-- Membutuhkan kolom public.categories.parent_id dari migrasi 47.
-- Idempoten: aman dijalankan lebih dari satu kali.

-- Pastikan Pertanian tersedia sebagai kategori induk.
INSERT INTO public.categories (slug, name, icon, sort_order, is_active, parent_id)
VALUES ('pertanian', 'Pertanian', '🌾', 4, true, NULL)
ON CONFLICT (slug) DO UPDATE
SET name = EXCLUDED.name,
    icon = EXCLUDED.icon,
    sort_order = EXCLUDED.sort_order,
    is_active = true,
    parent_id = NULL;

-- Slug bibit, benih, pupuk, pestisida, pakan, alat-tani, dan hasil-tani
-- selaras dengan filter kategori Pertanian yang telah digunakan aplikasi.
WITH children (name, slug, description, icon, sort_order) AS (
  VALUES
    ('Bibit Tanaman', 'bibit', 'Bibit tanaman pangan, hortikultura, dan perkebunan.', '🌱', 1),
    ('Benih', 'benih', 'Benih tanaman untuk kebutuhan pertanian dan kebun.', '🌾', 2),
    ('Pupuk & Nutrisi Tanaman', 'pupuk', 'Pupuk organik, anorganik, dan nutrisi tanaman.', '🪴', 3),
    ('Pestisida & Pengendali Hama', 'pestisida', 'Pestisida dan produk pengendalian hama tanaman.', '🛡️', 4),
    ('Alat & Mesin Pertanian', 'alat-tani', 'Peralatan, mesin, dan perlengkapan pertanian.', '🛠️', 5),
    ('Pakan Ternak', 'pakan', 'Pakan dan nutrisi untuk ternak.', '🐄', 6),
    ('Peternakan', 'peternakan', 'Kebutuhan dan produk usaha peternakan.', '🐓', 7),
    ('Perikanan', 'perikanan', 'Benih ikan, pakan, dan kebutuhan budidaya perikanan.', '🐟', 8),
    ('Hasil Tani & Panen', 'hasil-tani', 'Hasil panen dan produk pertanian lokal.', '🧺', 9),
    ('Perkebunan', 'perkebunan', 'Kebutuhan dan hasil usaha perkebunan.', '🌴', 10)
)
INSERT INTO public.categories (
  parent_id,
  name,
  slug,
  description,
  icon,
  is_active,
  sort_order
)
SELECT
  parent.id,
  child.name,
  child.slug,
  child.description,
  child.icon,
  true,
  child.sort_order
FROM children AS child
CROSS JOIN public.categories AS parent
WHERE parent.slug = 'pertanian'
  AND parent.parent_id IS NULL
ON CONFLICT (slug) DO UPDATE
SET parent_id = EXCLUDED.parent_id,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    icon = EXCLUDED.icon,
    sort_order = EXCLUDED.sort_order;

-- Verifikasi opsional:
-- SELECT parent.name AS kategori_induk, child.name AS subkategori, child.slug, child.is_active
-- FROM public.categories AS child
-- JOIN public.categories AS parent ON parent.id = child.parent_id
-- WHERE parent.slug = 'pertanian'
-- ORDER BY child.sort_order, child.name;
