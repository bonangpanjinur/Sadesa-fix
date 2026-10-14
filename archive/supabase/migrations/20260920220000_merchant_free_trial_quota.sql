-- Free merchant onboarding: 100 transactions valid for 2 months.
-- A database trigger is used so the entitlement is granted atomically and cannot
-- be skipped by alternate clients or direct inserts.

INSERT INTO public.transaction_packages (
  name,
  description,
  classification_price,
  price_per_transaction,
  kas_fee,
  transaction_quota,
  validity_days,
  is_active
)
SELECT
  'Paket Gratis 2 Bulan',
  '100 transaksi gratis untuk merchant baru selama 2 bulan sejak pendaftaran.',
  'FREE',
  0,
  0,
  100,
  60,
  true
WHERE NOT EXISTS (
  SELECT 1 FROM public.transaction_packages
  WHERE name = 'Paket Gratis 2 Bulan'
)
ON CONFLICT DO NOTHING$bootstrap_sql_10e541a8cbed$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_10e541a8cbed$;

DO $bootstrap_do_9ccb36343852$
BEGIN
  EXECUTE $bootstrap_sql_9ccb36343852$CREATE OR REPLACE FUNCTION public.grant_new_merchant_free_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_package public.transaction_packages%ROWTYPE;
  v_subscription_id uuid;
BEGIN
  SELECT * INTO v_package
  FROM public.transaction_packages
  WHERE name = 'Paket Gratis 2 Bulan'
    AND is_active = true
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_package.id IS NULL THEN
    RAISE EXCEPTION 'Paket Gratis 2 Bulan belum tersedia';
  END IF;

  INSERT INTO public.merchant_subscriptions (
    merchant_id,
    package_id,
    transaction_quota,
    used_quota,
    status,
    payment_status,
    payment_amount,
    started_at,
    expired_at
  )
  VALUES (
    NEW.id,
    v_package.id,
    v_package.transaction_quota,
    0,
    'ACTIVE',
    'PAID',
    0,
    COALESCE(NEW.registered_at, now()),
    COALESCE(NEW.registered_at, now()) + make_interval(days => v_package.validity_days)
  )
  RETURNING id INTO v_subscription_id;

  UPDATE public.merchants
  SET current_subscription_id = v_subscription_id,
      status = 'ACTIVE',
      registration_status = 'APPROVED',
      approved_at = COALESCE(approved_at, now()),
      updated_at = now()
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$$bootstrap_sql_9ccb36343852$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9ccb36343852$;

DO $bootstrap_do_a5e1dce1a62f$
BEGIN
  EXECUTE $bootstrap_sql_a5e1dce1a62f$DROP TRIGGER IF EXISTS grant_new_merchant_free_trial_trigger ON public.merchants$bootstrap_sql_a5e1dce1a62f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a5e1dce1a62f$;

DO $bootstrap_do_c204026a54e3$
BEGIN
  EXECUTE $bootstrap_sql_c204026a54e3$CREATE TRIGGER grant_new_merchant_free_trial_trigger
AFTER INSERT ON public.merchants
FOR EACH ROW
EXECUTE FUNCTION public.grant_new_merchant_free_trial()$bootstrap_sql_c204026a54e3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c204026a54e3$;

DO $bootstrap_do_83ec56bb217c$
BEGIN
  EXECUTE $bootstrap_sql_83ec56bb217c$COMMENT ON FUNCTION public.grant_new_merchant_free_trial() IS
  'Automatically activates new merchants and grants the 2-month free transaction quota.'$bootstrap_sql_83ec56bb217c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_83ec56bb217c$;

DO $bootstrap_do_2076255cf32a$
BEGIN
  EXECUTE $bootstrap_sql_2076255cf32a$
