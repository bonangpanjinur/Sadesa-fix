-- Capture payment-gateway return data in the QRIS application flow.
-- NMID remains in the existing GDC profile as its canonical source; the secure
-- application-list RPC exposes it beside the application for admin review.
CREATE OR REPLACE FUNCTION public.admin_list_qris_applications()
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT to_jsonb(a) || jsonb_build_object(
    'merchant', jsonb_build_object('name', m.name, 'city', m.city),
    'nmid', gp.nmid
  )
  FROM public.qris_applications AS a
  LEFT JOIN public.merchants AS m ON m.id = a.merchant_id
  LEFT JOIN public.gdc_payment_profiles AS gp
    ON gp.merchant_id = a.merchant_id AND gp.provider = 'GDC'
  ORDER BY a.submitted_at DESC, a.created_at DESC;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_qris_applications() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_qris_applications() TO authenticated;

-- Save the merchant QRIS assignment and gateway profile in one transaction.
-- The profile stays pending until the final QRIS activation step.
CREATE OR REPLACE FUNCTION public.admin_issue_qris_mpm(
  p_application_id uuid,
  p_qris_reference text,
  p_qris_asset_key text,
  p_gdc_merchant_id text,
  p_gdc_account_number text,
  p_nmid text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_application public.qris_applications%ROWTYPE;
  v_profile public.gdc_payment_profiles%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;
  IF p_application_id IS NULL
     OR NULLIF(btrim(p_qris_reference), '') IS NULL
     OR NULLIF(btrim(p_qris_asset_key), '') IS NULL
     OR NULLIF(btrim(p_gdc_merchant_id), '') IS NULL
     OR NULLIF(btrim(p_gdc_account_number), '') IS NULL
     OR length(btrim(p_gdc_merchant_id)) > 100
     OR length(btrim(p_gdc_account_number)) > 160
     OR length(btrim(COALESCE(p_nmid, ''))) > 160 THEN
    RAISE EXCEPTION 'Data penerbitan QRIS dan identitas payment gateway tidak valid' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO STRICT v_application
  FROM public.qris_applications
  WHERE id = p_application_id
  FOR UPDATE;
  IF v_application.status <> 'APPROVED_PENDING_ISSUANCE' THEN
    RAISE EXCEPTION 'Application is not ready for QRIS issuance' USING ERRCODE = '22023';
  END IF;

  PERFORM set_config('app.qris_assignment', 'true', true);
  UPDATE public.merchants
  SET qris_image_url = left(btrim(p_qris_asset_key), 1000), updated_at = now()
  WHERE id = v_application.merchant_id;

  UPDATE public.qris_applications
  SET qris_reference = left(btrim(p_qris_reference), 200),
      qris_asset_key = left(btrim(p_qris_asset_key), 1000),
      gdc_merchant_id = left(btrim(p_gdc_merchant_id), 100),
      gdc_account_number = left(btrim(p_gdc_account_number), 160),
      status = 'ISSUED_PENDING_ACTIVATION',
      issued_by_admin_id = auth.uid(),
      issued_at = now(),
      updated_at = now()
  WHERE id = p_application_id;

  INSERT INTO public.gdc_payment_profiles(
    merchant_id, provider_merchant_id, provider_account_number, nmid,
    status, verified_at, verified_by
  ) VALUES (
    v_application.merchant_id, btrim(p_gdc_merchant_id), btrim(p_gdc_account_number), NULLIF(btrim(p_nmid), ''),
    'PENDING_VALIDATION', NULL, NULL
  )
  ON CONFLICT (merchant_id, provider) DO UPDATE SET
    provider_merchant_id = EXCLUDED.provider_merchant_id,
    provider_account_number = EXCLUDED.provider_account_number,
    nmid = COALESCE(EXCLUDED.nmid, gdc_payment_profiles.nmid),
    status = 'PENDING_VALIDATION',
    verified_at = NULL,
    verified_by = NULL,
    updated_at = now()
  RETURNING * INTO v_profile;

  INSERT INTO public.gdc_payment_profile_activity_logs(profile_id, actor_user_id, action, metadata)
  VALUES (
    v_profile.id, auth.uid(), 'PROFILE_CONFIGURED_FROM_QRIS_APPLICATION',
    jsonb_build_object('status', 'PENDING_VALIDATION', 'nmid_present', v_profile.nmid IS NOT NULL)
  );

  RETURN jsonb_build_object('success', true, 'application_id', p_application_id, 'status', 'ISSUED_PENDING_ACTIVATION');
END;
$$;
REVOKE ALL ON FUNCTION public.admin_issue_qris_mpm(uuid,text,text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_issue_qris_mpm(uuid,text,text,text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_issue_qris_mpm(uuid,text,text,text,text) FROM PUBLIC, anon, authenticated;

-- Keep the active application and operational GDC profile in sync if an admin
-- corrects gateway-return values after activation.
CREATE OR REPLACE FUNCTION public.admin_configure_qris_mpm(
  p_application_id uuid,
  p_gdc_merchant_id text,
  p_gdc_account_number text,
  p_nmid text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_application public.qris_applications%ROWTYPE;
  v_profile public.gdc_payment_profiles%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;
  IF p_application_id IS NULL
     OR NULLIF(btrim(p_gdc_merchant_id), '') IS NULL
     OR NULLIF(btrim(p_gdc_account_number), '') IS NULL
     OR length(btrim(p_gdc_merchant_id)) > 100
     OR length(btrim(p_gdc_account_number)) > 160
     OR length(btrim(COALESCE(p_nmid, ''))) > 160 THEN
    RAISE EXCEPTION 'Identitas payment gateway tidak valid' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO STRICT v_application
  FROM public.qris_applications
  WHERE id = p_application_id
  FOR UPDATE;
  IF v_application.status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Only an active QRIS application can be configured' USING ERRCODE = '22023';
  END IF;

  UPDATE public.qris_applications
  SET gdc_merchant_id = btrim(p_gdc_merchant_id),
      gdc_account_number = btrim(p_gdc_account_number),
      updated_at = now()
  WHERE id = p_application_id;

  INSERT INTO public.gdc_payment_profiles(
    merchant_id, provider_merchant_id, provider_account_number, nmid,
    status, verified_at, verified_by
  ) VALUES (
    v_application.merchant_id, btrim(p_gdc_merchant_id), btrim(p_gdc_account_number), NULLIF(btrim(p_nmid), ''),
    'ACTIVE', now(), auth.uid()
  )
  ON CONFLICT (merchant_id, provider) DO UPDATE SET
    provider_merchant_id = EXCLUDED.provider_merchant_id,
    provider_account_number = EXCLUDED.provider_account_number,
    nmid = COALESCE(EXCLUDED.nmid, gdc_payment_profiles.nmid),
    status = 'ACTIVE',
    verified_at = now(),
    verified_by = auth.uid(),
    updated_at = now()
  RETURNING * INTO v_profile;

  INSERT INTO public.gdc_payment_profile_activity_logs(profile_id, actor_user_id, action, metadata)
  VALUES (
    v_profile.id, auth.uid(), 'ACTIVE_PROFILE_UPDATED_FROM_QRIS_APPLICATION',
    jsonb_build_object('status', 'ACTIVE', 'nmid_present', v_profile.nmid IS NOT NULL)
  );

  RETURN jsonb_build_object('success', true, 'application_id', p_application_id, 'status', 'ACTIVE');
END;
$$;
REVOKE ALL ON FUNCTION public.admin_configure_qris_mpm(uuid,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_configure_qris_mpm(uuid,text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_configure_qris_mpm(uuid,text,text) FROM PUBLIC, anon, authenticated;

-- Promote the stored gateway profile when QRIS is activated; preserve NMID on
-- existing profile records created during the issuance step.
CREATE OR REPLACE FUNCTION public.admin_activate_qris(p_application_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_application public.qris_applications%ROWTYPE;
  v_profile public.gdc_payment_profiles%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Akses admin diperlukan' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO STRICT v_application
  FROM public.qris_applications
  WHERE id = p_application_id
  FOR UPDATE;
  IF v_application.status <> 'ISSUED_PENDING_ACTIVATION'
     OR NULLIF(btrim(v_application.qris_reference), '') IS NULL
     OR NULLIF(btrim(v_application.qris_asset_key), '') IS NULL
     OR NULLIF(btrim(v_application.gdc_merchant_id), '') IS NULL
     OR NULLIF(btrim(v_application.gdc_account_number), '') IS NULL THEN
    RAISE EXCEPTION 'QRIS belum diterbitkan lengkap dan belum dapat diaktifkan' USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.merchants m
    WHERE m.id = v_application.merchant_id AND m.qris_image_url = v_application.qris_asset_key
  ) THEN
    RAISE EXCEPTION 'QRIS tidak terpasang pada merchant yang diajukan' USING ERRCODE = '23514';
  END IF;

  UPDATE public.qris_applications
  SET status = 'ACTIVE', activated_by_admin_id = auth.uid(), activated_at = now(), updated_at = now()
  WHERE id = p_application_id;

  INSERT INTO public.gdc_payment_profiles(
    merchant_id, provider_merchant_id, provider_account_number,
    status, verified_at, verified_by
  ) VALUES (
    v_application.merchant_id, v_application.gdc_merchant_id, v_application.gdc_account_number,
    'ACTIVE', now(), auth.uid()
  )
  ON CONFLICT (merchant_id, provider) DO UPDATE SET
    provider_merchant_id = EXCLUDED.provider_merchant_id,
    provider_account_number = EXCLUDED.provider_account_number,
    status = 'ACTIVE',
    verified_at = now(),
    verified_by = auth.uid(),
    updated_at = now()
  RETURNING * INTO v_profile;

  INSERT INTO public.gdc_payment_profile_activity_logs(profile_id, actor_user_id, action, metadata)
  VALUES (
    v_profile.id, auth.uid(), 'PROFILE_ACTIVATED_FROM_QRIS_APPLICATION',
    jsonb_build_object('status', 'ACTIVE', 'nmid_present', v_profile.nmid IS NOT NULL)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.admin_activate_qris(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_activate_qris(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
