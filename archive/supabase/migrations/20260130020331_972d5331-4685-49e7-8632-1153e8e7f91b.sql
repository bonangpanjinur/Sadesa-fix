-- Add location coordinates to villages table
ALTER TABLE public.villages
ADD COLUMN IF NOT EXISTS location_lat DECIMAL(10, 8),
ADD COLUMN IF NOT EXISTS location_lng DECIMAL(11, 8)$bootstrap_sql_6de88541714f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6de88541714f$;

DO $bootstrap_do_6db0df3984e0$
BEGIN
  EXECUTE $bootstrap_sql_6db0df3984e0$-- Add location coordinates to merchants table for precise location
ALTER TABLE public.merchants
ADD COLUMN IF NOT EXISTS location_lat DECIMAL(10, 8),
ADD COLUMN IF NOT EXISTS location_lng DECIMAL(11, 8)$bootstrap_sql_6db0df3984e0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6db0df3984e0$;

DO $bootstrap_do_46a1ce93f348$
BEGIN
  EXECUTE $bootstrap_sql_46a1ce93f348$-- Update existing villages with approximate coordinates (Tasikmalaya area)
UPDATE public.villages SET
  location_lat = -7.3274,
  location_lng = 108.2207
WHERE district = 'Megamendung' AND location_lat IS NULL$bootstrap_sql_46a1ce93f348$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_46a1ce93f348$;

DO $bootstrap_do_e630d83e335f$
BEGIN
  EXECUTE $bootstrap_sql_e630d83e335f$UPDATE public.villages SET
  location_lat = -7.3350,
  location_lng = 108.2150
WHERE district = 'Cisarua' AND location_lat IS NULL$bootstrap_sql_e630d83e335f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e630d83e335f$;

DO $bootstrap_do_670cce9cc624$
BEGIN
  EXECUTE $bootstrap_sql_670cce9cc624$-- Create index for location queries
CREATE INDEX IF NOT EXISTS idx_villages_location ON public.villages(location_lat, location_lng)$bootstrap_sql_670cce9cc624$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_670cce9cc624$;

DO $bootstrap_do_c6ae99cbba5c$
BEGIN
  EXECUTE $bootstrap_sql_c6ae99cbba5c$CREATE INDEX IF NOT EXISTS idx_merchants_location ON public.merchants(location_lat, location_lng)$bootstrap_sql_c6ae99cbba5c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c6ae99cbba5c$;

DO $bootstrap_do_67decc123dd6$
BEGIN
  EXECUTE $bootstrap_sql_67decc123dd6$CREATE INDEX IF NOT EXISTS idx_tourism_location ON public.tourism(location_lat, location_lng)$bootstrap_sql_67decc123dd6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_67decc123dd6$;

DO $bootstrap_do_d69e09238f26$
BEGIN
  EXECUTE $bootstrap_sql_d69e09238f26$
