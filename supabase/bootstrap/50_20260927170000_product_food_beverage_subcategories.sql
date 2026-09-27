-- Seed subkategori produk untuk kategori Makanan dan Minuman.
-- Idempoten: aman dijalankan lebih dari satu kali.
-- Membutuhkan migrasi 47_20260927143000_product_category_hierarchy.sql.

WITH parents (slug) AS (
  VALUES
    ('makanan'),
    ('minuman')
),
children (parent_slug, name, slug, description, icon, sort_order) AS (
  VALUES
    -- Subkategori Makanan
    ('makanan', 'Nasi dan Mi', 'nasi-dan-mi', 'Nasi, mi, bubur, dan hidangan sejenis.', '🍚', 1),
    ('makanan', 'Lauk Pauk', 'lauk-pauk', 'Lauk pauk, ayam, ikan, daging, dan telur.', '🍗', 2),
    ('makanan', 'Camilan', 'camilan', 'Camilan, keripik, snack, dan makanan ringan.', '🍿', 3),
    ('makanan', 'Kue dan Roti', 'kue-dan-roti', 'Kue, roti, pastry, dan jajanan pasar.', '🍞', 4),
    ('makanan', 'Makanan Tradisional', 'makanan-tradisional', 'Makanan khas dan olahan tradisional daerah.', '🍲', 5),
    ('makanan', 'Makanan Beku', 'makanan-beku', 'Frozen food dan makanan siap olah.', '❄️', 6),
    ('makanan', 'Sambal dan Bumbu', 'sambal-dan-bumbu', 'Sambal, bumbu masak, dan bahan pelengkap.', '🌶️', 7),

    -- Subkategori Minuman
    ('minuman', 'Kopi', 'kopi', 'Kopi bubuk, kopi seduh, dan minuman berbahan kopi.', '☕', 1),
    ('minuman', 'Teh', 'teh', 'Teh seduh, teh celup, dan minuman berbahan teh.', '🍵', 2),
    ('minuman', 'Jus dan Smoothie', 'jus-dan-smoothie', 'Jus buah, smoothie, dan minuman berbahan buah.', '🧃', 3),
    ('minuman', 'Minuman Tradisional', 'minuman-tradisional', 'Jamu, wedang, dan minuman khas tradisional.', '🥛', 4),
    ('minuman', 'Minuman Dingin', 'minuman-dingin', 'Es, minuman segar, dan minuman dingin lainnya.', '🧊', 5),
    ('minuman', 'Susu dan Olahan', 'susu-dan-olahan', 'Susu dan minuman berbahan susu.', '🥛', 6),
    ('minuman', 'Minuman Kemasan', 'minuman-kemasan', 'Minuman botol, kaleng, dan minuman siap minum.', '🧴', 7)
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
JOIN parents AS wanted_parent
  ON wanted_parent.slug = child.parent_slug
JOIN public.categories AS parent
  ON parent.slug = wanted_parent.slug
ON CONFLICT (slug) DO NOTHING;

-- Verifikasi hasil (opsional):
-- SELECT child.name AS subkategori, parent.name AS kategori_induk
-- FROM public.categories AS child
-- JOIN public.categories AS parent ON parent.id = child.parent_id
-- WHERE parent.slug IN ('makanan', 'minuman')
-- ORDER BY parent.sort_order, child.sort_order;
