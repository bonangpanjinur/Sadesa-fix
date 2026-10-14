-- Auto-generate slug on merchant insert
CREATE OR REPLACE FUNCTION auto_set_merchant_slug()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.slug IS NULL OR NEW.slug = '' THEN
    NEW.slug := generate_merchant_slug(NEW.name);
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_006c2cc346ab$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_006c2cc346ab$;

DO $bootstrap_do_9d3a704288a3$
BEGIN
  EXECUTE $bootstrap_sql_9d3a704288a3$DROP TRIGGER IF EXISTS trg_auto_merchant_slug ON merchants$bootstrap_sql_9d3a704288a3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9d3a704288a3$;

DO $bootstrap_do_db2ea00e6dc1$
BEGIN
  EXECUTE $bootstrap_sql_db2ea00e6dc1$CREATE TRIGGER trg_auto_merchant_slug
  BEFORE INSERT ON merchants
  FOR EACH ROW EXECUTE FUNCTION auto_set_merchant_slug()$bootstrap_sql_db2ea00e6dc1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_db2ea00e6dc1$;

DO $bootstrap_do_c747d486f5fb$
BEGIN
  EXECUTE $bootstrap_sql_c747d486f5fb$-- Also auto-update slug when name changes and slug was auto-generated
CREATE OR REPLACE FUNCTION auto_update_merchant_slug()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  -- Only auto-update if name changed and old slug was derived from old name
  IF NEW.name IS DISTINCT FROM OLD.name AND (OLD.slug IS NULL OR OLD.slug = '' OR OLD.slug = generate_merchant_slug(OLD.name)) THEN
    NEW.slug := generate_merchant_slug(NEW.name);
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_c747d486f5fb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c747d486f5fb$;

DO $bootstrap_do_117d181db9a9$
BEGIN
  EXECUTE $bootstrap_sql_117d181db9a9$DROP TRIGGER IF EXISTS trg_auto_update_merchant_slug ON merchants$bootstrap_sql_117d181db9a9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_117d181db9a9$;

DO $bootstrap_do_8083d8da1be6$
BEGIN
  EXECUTE $bootstrap_sql_8083d8da1be6$CREATE TRIGGER trg_auto_update_merchant_slug
  BEFORE UPDATE ON merchants
  FOR EACH ROW EXECUTE FUNCTION auto_update_merchant_slug()$bootstrap_sql_8083d8da1be6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8083d8da1be6$;

DO $bootstrap_do_0fa1b63ea59c$
BEGIN
  EXECUTE $bootstrap_sql_0fa1b63ea59c$
