-- QRIS Sadesa merchant application workflow, admin decisions and audit trail.
CREATE TABLE IF NOT EXISTS public.qris_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_number text NOT NULL UNIQUE DEFAULT ('QR-' || to_char(now(), 'YYYYMMDD') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  applicant_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  default_account_id uuid,
  default_bank_name text,
  default_account_number text,
  default_account_name text,
  business_criteria_code text NOT NULL CHECK (business_criteria_code IN ('UMI','UME','UBE')),
  business_age_code text NOT NULL,
  qris_merchant_name_short varchar(25) NOT NULL,
  qris_merchant_name varchar(50) NOT NULL,
  documents jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'SUBMITTED' CHECK (status IN ('SUBMITTED','IN_REVIEW','NEEDS_CORRECTION','REJECTED','APPROVED_PENDING_ISSUANCE','ISSUED_PENDING_ACTIVATION','ACTIVE')),
  revision_number integer NOT NULL DEFAULT 1,
  assigned_admin_id uuid REFERENCES auth.users(id),
  decision_by_admin_id uuid REFERENCES auth.users(id),
  decision_note text,
  qris_reference text,
  qris_asset_key text,
  issued_by_admin_id uuid REFERENCES auth.users(id),
  issued_at timestamptz,
  activated_by_admin_id uuid REFERENCES auth.users(id),
  activated_at timestamptz,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS qris_applications_status_submitted_idx ON public.qris_applications(status, submitted_at DESC);
CREATE INDEX IF NOT EXISTS qris_applications_merchant_created_idx ON public.qris_applications(merchant_id, created_at DESC);
ALTER TABLE public.qris_applications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Merchant reads own QRIS applications" ON public.qris_applications;
CREATE POLICY "Merchant reads own QRIS applications" ON public.qris_applications FOR SELECT TO authenticated
USING (applicant_user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS "Merchant creates own QRIS application" ON public.qris_applications;
CREATE POLICY "Merchant creates own QRIS application" ON public.qris_applications FOR INSERT TO authenticated
WITH CHECK (applicant_user_id = auth.uid() AND status = 'SUBMITTED' AND EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = merchant_id AND m.user_id = auth.uid()));
DROP POLICY IF EXISTS "Merchant updates correction requested application" ON public.qris_applications;
CREATE POLICY "Merchant updates correction requested application" ON public.qris_applications FOR UPDATE TO authenticated
USING (applicant_user_id = auth.uid() AND status = 'NEEDS_CORRECTION')
WITH CHECK (applicant_user_id = auth.uid() AND status IN ('NEEDS_CORRECTION','SUBMITTED'));
DROP POLICY IF EXISTS "Admins manage QRIS applications" ON public.qris_applications;
CREATE POLICY "Admins manage QRIS applications" ON public.qris_applications FOR ALL TO authenticated
USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE TABLE IF NOT EXISTS public.qris_application_activity_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES public.qris_applications(id) ON DELETE CASCADE,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id),
  actor_role text NOT NULL,
  action text NOT NULL,
  from_status text,
  to_status text,
  reason text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS qris_activity_application_time_idx ON public.qris_application_activity_logs(application_id, occurred_at DESC);
ALTER TABLE public.qris_application_activity_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Merchant reads own QRIS application activity" ON public.qris_application_activity_logs;
CREATE POLICY "Merchant reads own QRIS application activity" ON public.qris_application_activity_logs FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.qris_applications a WHERE a.id = application_id AND a.applicant_user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Admins write QRIS application activity" ON public.qris_application_activity_logs;
CREATE POLICY "Admins write QRIS application activity" ON public.qris_application_activity_logs FOR INSERT TO authenticated
WITH CHECK (public.is_admin() AND actor_user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.protect_merchant_qris_assignment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.qris_image_url IS DISTINCT FROM OLD.qris_image_url AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'QRIS Sadesa hanya dapat ditetapkan oleh admin' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS protect_merchant_qris_assignment_trigger ON public.merchants;
CREATE TRIGGER protect_merchant_qris_assignment_trigger BEFORE UPDATE OF qris_image_url ON public.merchants
FOR EACH ROW EXECUTE FUNCTION public.protect_merchant_qris_assignment();

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('qris-applications', 'qris-applications', false, 2097152, ARRAY['image/jpeg','image/png'])
ON CONFLICT (id) DO UPDATE SET public = false, file_size_limit = 2097152, allowed_mime_types = ARRAY['image/jpeg','image/png'];
DROP POLICY IF EXISTS "QRIS owner upload application documents" ON storage.objects;
CREATE POLICY "QRIS owner upload application documents" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'qris-applications' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "QRIS owner and admin read application documents" ON storage.objects;
CREATE POLICY "QRIS owner and admin read application documents" ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'qris-applications' AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin()));
DROP POLICY IF EXISTS "QRIS owner replace application documents" ON storage.objects;
CREATE POLICY "QRIS owner replace application documents" ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'qris-applications' AND (storage.foldername(name))[1] = auth.uid()::text)
WITH CHECK (bucket_id = 'qris-applications' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "QRIS owner delete application documents" ON storage.objects;
CREATE POLICY "QRIS owner delete application documents" ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'qris-applications' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE OR REPLACE FUNCTION public.enforce_qris_application_transition()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_is_admin boolean := public.is_admin();
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'SUBMITTED' OR NEW.applicant_user_id <> v_actor THEN
      RAISE EXCEPTION 'Pengajuan QRIS baru hanya dapat dikirim oleh merchant pemilik' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;
  IF NOT v_is_admin AND (NEW.merchant_id <> OLD.merchant_id OR NEW.applicant_user_id <> OLD.applicant_user_id OR NEW.qris_reference IS DISTINCT FROM OLD.qris_reference OR NEW.qris_asset_key IS DISTINCT FROM OLD.qris_asset_key OR NEW.issued_by_admin_id IS DISTINCT FROM OLD.issued_by_admin_id OR NEW.activated_by_admin_id IS DISTINCT FROM OLD.activated_by_admin_id) THEN
    RAISE EXCEPTION 'Merchant tidak dapat mengubah data penetapan QRIS' USING ERRCODE = '42501';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT v_is_admin THEN
      IF NOT (OLD.status = 'NEEDS_CORRECTION' AND NEW.status = 'SUBMITTED' AND OLD.applicant_user_id = v_actor) THEN
        RAISE EXCEPTION 'Transisi status QRIS ini hanya dapat dilakukan oleh admin' USING ERRCODE = '42501';
      END IF;
    ELSIF NOT (
      (OLD.status IN ('SUBMITTED','IN_REVIEW') AND NEW.status IN ('IN_REVIEW','NEEDS_CORRECTION','REJECTED','APPROVED_PENDING_ISSUANCE')) OR
      (OLD.status = 'APPROVED_PENDING_ISSUANCE' AND NEW.status = 'ISSUED_PENDING_ACTIVATION') OR
      (OLD.status = 'ISSUED_PENDING_ACTIVATION' AND NEW.status = 'ACTIVE')
    ) THEN
      RAISE EXCEPTION 'Transisi status QRIS tidak valid: % -> %', OLD.status, NEW.status USING ERRCODE = '23514';
    END IF;
  ELSIF NOT v_is_admin THEN
    IF OLD.status <> 'NEEDS_CORRECTION' OR NEW.status <> 'NEEDS_CORRECTION' OR OLD.applicant_user_id <> v_actor THEN
      RAISE EXCEPTION 'Merchant hanya dapat memperbarui pengajuan saat diminta perbaikan' USING ERRCODE = '42501';
    END IF;
    IF NEW.merchant_id <> OLD.merchant_id OR NEW.applicant_user_id <> OLD.applicant_user_id OR NEW.qris_reference IS DISTINCT FROM OLD.qris_reference OR NEW.qris_asset_key IS DISTINCT FROM OLD.qris_asset_key THEN
      RAISE EXCEPTION 'Merchant tidak dapat mengubah data penetapan QRIS' USING ERRCODE = '42501';
    END IF;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS enforce_qris_application_transition_trigger ON public.qris_applications;
CREATE TRIGGER enforce_qris_application_transition_trigger BEFORE INSERT OR UPDATE ON public.qris_applications
FOR EACH ROW EXECUTE FUNCTION public.enforce_qris_application_transition();

CREATE OR REPLACE FUNCTION public.log_qris_application_activity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_action text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_action := 'APPLICATION_SUBMITTED';
    INSERT INTO public.qris_application_activity_logs(application_id, actor_user_id, actor_role, action, from_status, to_status)
    VALUES (NEW.id, v_actor, CASE WHEN public.is_admin() THEN 'admin' ELSE 'merchant' END, v_action, NULL, NEW.status);
    INSERT INTO public.notifications(user_id, title, message, type, link)
    VALUES (NEW.applicant_user_id, 'Pengajuan QRIS Sadesa diterima', 'Pengajuan ' || NEW.application_number || ' telah diterima dan menunggu verifikasi admin.', 'qris', '/merchant/settings');
    RETURN NEW;
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    v_action := CASE NEW.status
      WHEN 'IN_REVIEW' THEN 'REVIEW_STARTED'
      WHEN 'NEEDS_CORRECTION' THEN 'CORRECTION_REQUESTED'
      WHEN 'REJECTED' THEN 'APPLICATION_REJECTED'
      WHEN 'APPROVED_PENDING_ISSUANCE' THEN 'APPLICATION_APPROVED'
      WHEN 'ISSUED_PENDING_ACTIVATION' THEN 'QRIS_ISSUED'
      WHEN 'ACTIVE' THEN 'QRIS_ACTIVATED'
      WHEN 'SUBMITTED' THEN 'APPLICATION_RESUBMITTED'
      ELSE 'STATUS_UPDATED' END;
    INSERT INTO public.qris_application_activity_logs(application_id, actor_user_id, actor_role, action, from_status, to_status, reason)
    VALUES (NEW.id, v_actor, CASE WHEN public.is_admin() THEN 'admin' ELSE 'merchant' END, v_action, OLD.status, NEW.status, NEW.decision_note);
    INSERT INTO public.notifications(user_id, title, message, type, link)
    VALUES (
      NEW.applicant_user_id,
      CASE NEW.status
        WHEN 'SUBMITTED' THEN 'Pengajuan QRIS Sadesa diterima'
        WHEN 'IN_REVIEW' THEN 'Pengajuan QRIS sedang ditinjau'
        WHEN 'NEEDS_CORRECTION' THEN 'Perlu perbaikan pengajuan QRIS'
        WHEN 'REJECTED' THEN 'Pengajuan QRIS belum disetujui'
        WHEN 'APPROVED_PENDING_ISSUANCE' THEN 'Pengajuan QRIS disetujui'
        WHEN 'ISSUED_PENDING_ACTIVATION' THEN 'QRIS Sadesa menunggu aktivasi'
        WHEN 'ACTIVE' THEN 'QRIS Sadesa aktif'
        ELSE 'Status pengajuan QRIS diperbarui' END,
      CASE NEW.status
        WHEN 'SUBMITTED' THEN 'Pengajuan ' || NEW.application_number || ' telah diterima dan menunggu verifikasi admin.'
        WHEN 'IN_REVIEW' THEN 'Pengajuan ' || NEW.application_number || ' sedang ditinjau admin.'
        WHEN 'NEEDS_CORRECTION' THEN 'Pengajuan ' || NEW.application_number || ' perlu diperbaiki. Catatan: ' || COALESCE(NEW.decision_note, 'Silakan periksa aplikasi.')
        WHEN 'REJECTED' THEN 'Pengajuan ' || NEW.application_number || ' belum dapat disetujui. Alasan: ' || COALESCE(NEW.decision_note, 'Silakan lihat detail di aplikasi.')
        WHEN 'APPROVED_PENDING_ISSUANCE' THEN 'Pengajuan ' || NEW.application_number || ' disetujui. Admin sedang menyiapkan QRIS.'
        WHEN 'ISSUED_PENDING_ACTIVATION' THEN 'QRIS untuk ' || NEW.application_number || ' sedang menjalani pemeriksaan aktivasi.'
        WHEN 'ACTIVE' THEN 'QRIS Sadesa untuk toko Anda sudah aktif dan siap digunakan.'
        ELSE 'Status pengajuan ' || NEW.application_number || ' telah diperbarui.' END,
      'qris', '/merchant/settings'
    );
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS log_qris_application_activity_trigger ON public.qris_applications;
CREATE TRIGGER log_qris_application_activity_trigger AFTER INSERT OR UPDATE ON public.qris_applications
FOR EACH ROW EXECUTE FUNCTION public.log_qris_application_activity();

CREATE OR REPLACE FUNCTION public.admin_issue_qris(p_application_id uuid, p_qris_reference text, p_qris_asset_key text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_application public.qris_applications%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan' USING ERRCODE = '42501'; END IF;
  IF NULLIF(trim(p_qris_reference), '') IS NULL OR NULLIF(trim(p_qris_asset_key), '') IS NULL THEN
    RAISE EXCEPTION 'Referensi dan gambar QRIS wajib diisi' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO STRICT v_application FROM public.qris_applications WHERE id = p_application_id FOR UPDATE;
  IF v_application.status <> 'APPROVED_PENDING_ISSUANCE' THEN RAISE EXCEPTION 'Pengajuan belum berada pada tahap penerbitan' USING ERRCODE = '23514'; END IF;
  UPDATE public.merchants SET qris_image_url = trim(p_qris_asset_key), updated_at = now() WHERE id = v_application.merchant_id;
  UPDATE public.qris_applications SET status = 'ISSUED_PENDING_ACTIVATION', qris_reference = trim(p_qris_reference), qris_asset_key = trim(p_qris_asset_key), issued_by_admin_id = auth.uid(), issued_at = now(), updated_at = now() WHERE id = p_application_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_issue_qris(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_issue_qris(uuid, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_activate_qris(p_application_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_application public.qris_applications%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan' USING ERRCODE = '42501'; END IF;
  SELECT * INTO STRICT v_application FROM public.qris_applications WHERE id = p_application_id FOR UPDATE;
  IF v_application.status <> 'ISSUED_PENDING_ACTIVATION' OR NULLIF(v_application.qris_reference, '') IS NULL OR NULLIF(v_application.qris_asset_key, '') IS NULL THEN
    RAISE EXCEPTION 'QRIS belum diterbitkan lengkap dan belum dapat diaktifkan' USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = v_application.merchant_id AND m.qris_image_url = v_application.qris_asset_key) THEN
    RAISE EXCEPTION 'QRIS tidak terpasang pada merchant yang diajukan' USING ERRCODE = '23514';
  END IF;
  UPDATE public.qris_applications SET status = 'ACTIVE', activated_by_admin_id = auth.uid(), activated_at = now(), updated_at = now() WHERE id = p_application_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_activate_qris(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_activate_qris(uuid) TO authenticated;

REVOKE ALL ON TABLE public.qris_applications FROM anon;
GRANT SELECT, INSERT, UPDATE ON TABLE public.qris_applications TO authenticated;
REVOKE ALL ON TABLE public.qris_application_activity_logs FROM anon;
GRANT SELECT ON TABLE public.qris_application_activity_logs TO authenticated;
