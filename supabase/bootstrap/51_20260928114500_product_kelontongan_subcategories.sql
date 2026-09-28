-- Seed hierarki kategori Kelontongan.
-- Membutuhkan kolom public.categories.parent_id dari migrasi 47.
-- Idempoten: aman dijalankan lebih dari satu kali.
-- Makanan, Minuman, Fashion, dan Kerajinan sengaja tidak dipindahkan.

-- Pastikan Kelontongan tersedia sebagai kategori induk.
INSERT INTO public.categories (slug, name, icon, sort_order, is_active, parent_id)
VALUES ('kelontongan', 'Kelontongan', '🛒', 3, true, NULL)
ON CONFLICT (slug) DO UPDATE
SET name = EXCLUDED.name,
    icon = EXCLUDED.icon,
    sort_order = EXCLUDED.sort_order,
    is_active = true,
    parent_id = NULL;

-- Pertahankan slug kategori lama agar produk yang sudah ada tetap cocok
-- dengan filter katalog, sekaligus menambahkan subkategori yang belum ada.
WITH children (name, slug, description, icon, sort_order) AS (
  VALUES
    ('Sembako', 'sembako', 'Beras, minyak, gula, telur, dan kebutuhan pokok.', '🛒', 1),
    ('Sayuran & Buah', 'sayuran', 'Sayur, buah, dan hasil kebun segar.', '🥬', 2),
    ('Rumah Tangga', 'rumah-tangga', 'Perlengkapan dan kebutuhan rumah tangga.', '🏠', 3),
    ('Kesehatan', 'kesehatan', 'Produk kesehatan dan kebutuhan perawatan dasar.', '💊', 4),
    ('Elektronik', 'elektronik', 'Peralatan elektronik dan aksesori rumah.', '🔌', 5),
    ('Perawatan Diri', 'perawatan-diri', 'Sabun, sampo, kosmetik, dan produk perawatan diri.', '🧴', 6),
    ('Kebutuhan Bayi', 'kebutuhan-bayi', 'Popok, perlengkapan, dan kebutuhan bayi.', '🍼', 7),
    ('Alat Tulis & Kantor', 'alat-tulis-kantor', 'Alat tulis, kertas, dan perlengkapan kantor.', '✏️', 8),
    ('Peralatan Dapur', 'peralatan-dapur', 'Peralatan masak dan perlengkapan dapur.', '🍳', 9)
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
WHERE parent.slug = 'kelontongan'
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
-- WHERE parent.slug = 'kelontongan'
-- ORDER BY child.sort_order, child.name;
