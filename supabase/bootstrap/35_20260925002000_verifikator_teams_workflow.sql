-- Verifikator team workflow: teams, memberships, geographic scopes, cases, audit events,
-- scoped RLS, idempotent referral backfill columns, and protected review RPCs.

CREATE TABLE IF NOT EXISTS public.verifikator_teams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  lead_verifikator_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT verifikator_teams_name_check CHECK (length(trim(name)) BETWEEN 2 AND 120)
);

CREATE TABLE IF NOT EXISTS public.verifikator_team_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.verifikator_teams(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  role text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  joined_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT verifikator_team_members_role_check CHECK (role IN ('LEAD', 'MERCHANT_REVIEWER', 'COURIER_REVIEWER', 'QUALITY_CONTROL')),
  CONSTRAINT verifikator_team_members_dates_check CHECK (ended_at IS NULL OR ended_at >= joined_at),
  CONSTRAINT verifikator_team_members_active_dates_check CHECK (is_active OR ended_at IS NOT NULL),
  CONSTRAINT verifikator_team_members_unique_user_per_team UNIQUE (team_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.verifikator_team_scopes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.verifikator_teams(id) ON DELETE CASCADE,
  village_id uuid NOT NULL REFERENCES public.villages(id) ON DELETE RESTRICT,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT verifikator_team_scopes_unique_scope UNIQUE (team_id, village_id)
);

ALTER TABLE public.verifikator_codes
  ADD COLUMN IF NOT EXISTS team_id uuid REFERENCES public.verifikator_teams(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS verifikator_team_id uuid REFERENCES public.verifikator_teams(id) ON DELETE SET NULL;

ALTER TABLE public.couriers
  ADD COLUMN IF NOT EXISTS verifikator_team_id uuid REFERENCES public.verifikator_teams(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_verifikator_team_members_user_active ON public.verifikator_team_members(user_id, is_active, team_id);
CREATE INDEX IF NOT EXISTS idx_verifikator_team_scopes_village_active ON public.verifikator_team_scopes(village_id, is_active, team_id);
CREATE INDEX IF NOT EXISTS idx_verifikator_teams_lead_active ON public.verifikator_teams(lead_verifikator_id, is_active);
CREATE UNIQUE INDEX IF NOT EXISTS uq_verifikator_team_one_active_lead ON public.verifikator_team_members(team_id) WHERE role = 'LEAD' AND is_active = true;
CREATE INDEX IF NOT EXISTS idx_verifikator_codes_team_active ON public.verifikator_codes(team_id, is_active);
CREATE INDEX IF NOT EXISTS idx_merchants_verifikator_team ON public.merchants(verifikator_team_id, registration_status);
CREATE INDEX IF NOT EXISTS idx_couriers_verifikator_team ON public.couriers(verifikator_team_id, registration_status);

CREATE TABLE IF NOT EXISTS public.verification_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_type text NOT NULL,
  merchant_id uuid REFERENCES public.merchants(id) ON DELETE CASCADE,
  courier_id uuid REFERENCES public.couriers(id) ON DELETE CASCADE,
  team_id uuid NOT NULL REFERENCES public.verifikator_teams(id) ON DELETE RESTRICT,
  village_id uuid REFERENCES public.villages(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'PENDING',
  risk_level text NOT NULL DEFAULT 'NORMAL',
  assigned_to uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  assigned_at timestamptz,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  decision_reason text,
  due_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT verification_cases_type_check CHECK (case_type IN ('MERCHANT', 'COURIER')),
  CONSTRAINT verification_cases_status_check CHECK (status IN ('PENDING', 'IN_REVIEW', 'NEED_REVISION', 'READY_FOR_APPROVAL', 'APPROVED', 'REJECTED', 'ESCALATED', 'CLOSED')),
  CONSTRAINT verification_cases_risk_check CHECK (risk_level IN ('NORMAL', 'ELEVATED', 'HIGH')),
  CONSTRAINT verification_cases_one_subject_check CHECK ((case_type = 'MERCHANT' AND merchant_id IS NOT NULL AND courier_id IS NULL) OR (case_type = 'COURIER' AND courier_id IS NOT NULL AND merchant_id IS NULL)),
  CONSTRAINT verification_cases_decision_reason_check CHECK (status NOT IN ('REJECTED', 'NEED_REVISION', 'ESCALATED') OR length(trim(COALESCE(decision_reason, ''))) >= 3)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_verification_cases_open_merchant ON public.verification_cases(merchant_id) WHERE merchant_id IS NOT NULL AND status NOT IN ('APPROVED', 'REJECTED', 'CLOSED');
CREATE UNIQUE INDEX IF NOT EXISTS uq_verification_cases_open_courier ON public.verification_cases(courier_id) WHERE courier_id IS NOT NULL AND status NOT IN ('APPROVED', 'REJECTED', 'CLOSED');
CREATE INDEX IF NOT EXISTS idx_verification_cases_team_queue ON public.verification_cases(team_id, status, risk_level, due_at, submitted_at);
CREATE INDEX IF NOT EXISTS idx_verification_cases_assignee ON public.verification_cases(assigned_to, status, due_at);

CREATE TABLE IF NOT EXISTS public.verification_case_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid NOT NULL REFERENCES public.verification_cases(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  from_status text,
  to_status text,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  assigned_to uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reason text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT verification_case_events_type_check CHECK (event_type IN ('CREATED', 'ASSIGNED', 'REASSIGNED', 'STATUS_CHANGED', 'DECIDED', 'ESCALATED', 'NOTE_ADDED', 'SLA_BREACHED'))
);

CREATE INDEX IF NOT EXISTS idx_verification_case_events_case_time ON public.verification_case_events(case_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_verification_case_events_actor_time ON public.verification_case_events(actor_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.is_active_verifikator_team_member(p_team_id uuid, p_roles text[] DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET row_security = off AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.verifikator_team_members tm
    WHERE tm.team_id = p_team_id AND tm.user_id = auth.uid() AND tm.is_active = true
      AND (p_roles IS NULL OR tm.role = ANY(p_roles))
  ) AND (public.is_verifikator() OR public.is_admin());
$$;

CREATE OR REPLACE FUNCTION public.team_has_village_scope(p_team_id uuid, p_village_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET row_security = off AS $$
  SELECT p_village_id IS NULL OR EXISTS (
    SELECT 1 FROM public.verifikator_team_scopes ts
    WHERE ts.team_id = p_team_id AND ts.village_id = p_village_id AND ts.is_active = true
  );
$$;

CREATE OR REPLACE FUNCTION public.resolve_verifikator_team(p_code text)
RETURNS TABLE (code text, verifikator_id uuid, team_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT vc.code, vc.verifikator_id, vc.team_id
  FROM public.verifikator_codes vc
  WHERE vc.code = upper(trim(p_code)) AND vc.is_active = true
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.is_active_verifikator_team_member(uuid, text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.team_has_village_scope(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resolve_verifikator_team(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_active_verifikator_team_member(uuid, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.team_has_village_scope(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_verifikator_team(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.sync_verifikator_team_for_subject()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_team_id uuid; v_verifikator_id uuid;
BEGIN
  IF NEW.verifikator_code IS NULL OR trim(NEW.verifikator_code) = '' THEN
    RETURN NEW;
  END IF;
  SELECT vc.team_id, vc.verifikator_id INTO v_team_id, v_verifikator_id
  FROM public.verifikator_codes vc
  WHERE vc.code = upper(trim(NEW.verifikator_code)) AND vc.is_active = true
  LIMIT 1;
  IF v_verifikator_id IS NOT NULL THEN
    NEW.verifikator_id := v_verifikator_id;
    NEW.verifikator_team_id := v_team_id;
    NEW.verifikator_code := upper(trim(NEW.verifikator_code));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_merchant_verifikator_team ON public.merchants;
CREATE TRIGGER trg_sync_merchant_verifikator_team BEFORE INSERT OR UPDATE OF verifikator_code ON public.merchants FOR EACH ROW EXECUTE FUNCTION public.sync_verifikator_team_for_subject();
DROP TRIGGER IF EXISTS trg_sync_courier_verifikator_team ON public.couriers;
CREATE TRIGGER trg_sync_courier_verifikator_team BEFORE INSERT OR UPDATE OF verifikator_code ON public.couriers FOR EACH ROW EXECUTE FUNCTION public.sync_verifikator_team_for_subject();

CREATE OR REPLACE FUNCTION public.ensure_verification_case()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_team_id uuid; v_village_id uuid; v_case_type text; v_merchant_id uuid; v_courier_id uuid;
BEGIN
  IF NEW.registration_status <> 'PENDING' OR NEW.verifikator_team_id IS NULL THEN RETURN NEW; END IF;
  IF TG_TABLE_NAME = 'merchants' THEN
    v_case_type := 'MERCHANT'; v_merchant_id := NEW.id; v_village_id := NEW.village_id; v_courier_id := NULL;
  ELSE
    v_case_type := 'COURIER'; v_merchant_id := NULL; v_courier_id := NEW.id; v_village_id := NEW.village_id;
  END IF;
  v_team_id := NEW.verifikator_team_id;
  IF NOT EXISTS (
    SELECT 1 FROM public.verification_cases vc
    WHERE ((v_case_type = 'MERCHANT' AND vc.merchant_id = v_merchant_id) OR (v_case_type = 'COURIER' AND vc.courier_id = v_courier_id))
      AND vc.status NOT IN ('APPROVED', 'REJECTED', 'CLOSED')
  ) THEN
    INSERT INTO public.verification_cases(case_type, merchant_id, courier_id, team_id, village_id, due_at)
    VALUES (v_case_type, v_merchant_id, v_courier_id, v_team_id, v_village_id, now() + interval '1 day');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ensure_merchant_verification_case ON public.merchants;
CREATE TRIGGER trg_ensure_merchant_verification_case AFTER INSERT OR UPDATE OF registration_status, verifikator_team_id ON public.merchants FOR EACH ROW EXECUTE FUNCTION public.ensure_verification_case();
DROP TRIGGER IF EXISTS trg_ensure_courier_verification_case ON public.couriers;
CREATE TRIGGER trg_ensure_courier_verification_case AFTER INSERT OR UPDATE OF registration_status, verifikator_team_id ON public.couriers FOR EACH ROW EXECUTE FUNCTION public.ensure_verification_case();

CREATE OR REPLACE FUNCTION public.claim_verification_case(p_case_id uuid)
RETURNS public.verification_cases LANGUAGE plpgsql SECURITY DEFINER SET search_path = public SET row_security = off AS $$
DECLARE v_case public.verification_cases;
BEGIN
  SELECT * INTO v_case FROM public.verification_cases WHERE id = p_case_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Verification case not found' USING ERRCODE = 'P0002'; END IF;
  IF NOT public.is_active_verifikator_team_member(v_case.team_id, ARRAY['LEAD','MERCHANT_REVIEWER','COURIER_REVIEWER']) THEN RAISE EXCEPTION 'Not allowed to claim this case' USING ERRCODE = '42501'; END IF;
  IF v_case.status NOT IN ('PENDING','ESCALATED') THEN RAISE EXCEPTION 'Case is not available for claiming' USING ERRCODE = '55000'; END IF;
  UPDATE public.verification_cases SET status = 'IN_REVIEW', assigned_to = auth.uid(), assigned_at = now(), updated_at = now() WHERE id = p_case_id RETURNING * INTO v_case;
  INSERT INTO public.verification_case_events(case_id, event_type, from_status, to_status, actor_id, assigned_to) VALUES (p_case_id, 'ASSIGNED', 'PENDING', 'IN_REVIEW', auth.uid(), auth.uid());
  RETURN v_case;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_verification_case(p_case_id uuid, p_decision text, p_reason text DEFAULT NULL)
RETURNS public.verification_cases LANGUAGE plpgsql SECURITY DEFINER SET search_path = public SET row_security = off AS $$
DECLARE v_case public.verification_cases; v_previous_status text;
BEGIN
  IF p_decision NOT IN ('READY_FOR_APPROVAL','APPROVED','REJECTED','NEED_REVISION','ESCALATED') THEN RAISE EXCEPTION 'Invalid verification decision' USING ERRCODE = '22023'; END IF;
  IF p_decision IN ('REJECTED','NEED_REVISION','ESCALATED') AND NULLIF(trim(COALESCE(p_reason,'')), '') IS NULL THEN RAISE EXCEPTION 'Reason is required' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_case FROM public.verification_cases WHERE id = p_case_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Verification case not found' USING ERRCODE = 'P0002'; END IF;
  IF NOT public.is_active_verifikator_team_member(v_case.team_id, ARRAY['LEAD','MERCHANT_REVIEWER','COURIER_REVIEWER']) THEN RAISE EXCEPTION 'Not allowed to review this case' USING ERRCODE = '42501'; END IF;
  IF v_case.case_type = 'MERCHANT' AND NOT public.is_active_verifikator_team_member(v_case.team_id, ARRAY['LEAD','MERCHANT_REVIEWER']) THEN RAISE EXCEPTION 'Merchant reviewer role required' USING ERRCODE = '42501'; END IF;
  IF v_case.case_type = 'COURIER' AND NOT public.is_active_verifikator_team_member(v_case.team_id, ARRAY['LEAD','COURIER_REVIEWER']) THEN RAISE EXCEPTION 'Courier reviewer role required' USING ERRCODE = '42501'; END IF;
  v_previous_status := v_case.status;
  UPDATE public.verification_cases SET status = p_decision, reviewed_by = auth.uid(), reviewed_at = now(), decision_reason = NULLIF(trim(p_reason), ''), closed_at = CASE WHEN p_decision IN ('APPROVED','REJECTED') THEN now() ELSE NULL END, updated_at = now() WHERE id = p_case_id RETURNING * INTO v_case;
  IF p_decision = 'APPROVED' AND v_case.case_type = 'MERCHANT' THEN UPDATE public.merchants SET registration_status = 'APPROVED', status = 'ACTIVE', verified_by = auth.uid(), verified_at = now(), updated_at = now() WHERE id = v_case.merchant_id; END IF;
  IF p_decision = 'REJECTED' AND v_case.case_type = 'MERCHANT' THEN UPDATE public.merchants SET registration_status = 'REJECTED', rejection_reason = trim(p_reason), updated_at = now() WHERE id = v_case.merchant_id; END IF;
  IF p_decision = 'APPROVED' AND v_case.case_type = 'COURIER' THEN UPDATE public.couriers SET registration_status = 'APPROVED', status = 'ACTIVE', approved_by = auth.uid(), approved_at = now(), rejection_reason = NULL, updated_at = now() WHERE id = v_case.courier_id; END IF;
  IF p_decision = 'REJECTED' AND v_case.case_type = 'COURIER' THEN UPDATE public.couriers SET registration_status = 'REJECTED', status = 'INACTIVE', approved_by = auth.uid(), approved_at = NULL, rejection_reason = trim(p_reason), updated_at = now() WHERE id = v_case.courier_id; END IF;
  INSERT INTO public.verification_case_events(case_id, event_type, from_status, to_status, actor_id, reason) VALUES (p_case_id, CASE WHEN p_decision = 'ESCALATED' THEN 'ESCALATED' ELSE 'DECIDED' END, v_previous_status, p_decision, auth.uid(), NULLIF(trim(p_reason), ''));
  RETURN v_case;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_verification_case(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.review_verification_case(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_verification_case(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_verification_case(uuid, text, text) TO authenticated;

ALTER TABLE public.verifikator_teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verifikator_team_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verifikator_team_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verification_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verification_case_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Team members can view own teams" ON public.verifikator_teams;
CREATE POLICY "Team members can view own teams" ON public.verifikator_teams FOR SELECT TO authenticated USING (public.is_admin() OR public.is_active_verifikator_team_member(id, NULL));
DROP POLICY IF EXISTS "Admins manage verifier teams" ON public.verifikator_teams;
CREATE POLICY "Admins manage verifier teams" ON public.verifikator_teams FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Team members can view own membership" ON public.verifikator_team_members;
CREATE POLICY "Team members can view own membership" ON public.verifikator_team_members FOR SELECT TO authenticated USING (public.is_admin() OR user_id = auth.uid() OR public.is_active_verifikator_team_member(team_id, ARRAY['LEAD']));
DROP POLICY IF EXISTS "Admins manage team membership" ON public.verifikator_team_members;
CREATE POLICY "Admins manage team membership" ON public.verifikator_team_members FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Team leads manage team membership" ON public.verifikator_team_members;
CREATE POLICY "Team leads manage team membership" ON public.verifikator_team_members FOR ALL TO authenticated USING (public.is_active_verifikator_team_member(team_id, ARRAY['LEAD'])) WITH CHECK (public.is_active_verifikator_team_member(team_id, ARRAY['LEAD']));
DROP POLICY IF EXISTS "Team members can view own scopes" ON public.verifikator_team_scopes;
CREATE POLICY "Team members can view own scopes" ON public.verifikator_team_scopes FOR SELECT TO authenticated USING (public.is_admin() OR public.is_active_verifikator_team_member(team_id, NULL));
DROP POLICY IF EXISTS "Admins manage team scopes" ON public.verifikator_team_scopes;
CREATE POLICY "Admins manage team scopes" ON public.verifikator_team_scopes FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Team members can view scoped cases" ON public.verification_cases;
CREATE POLICY "Team members can view scoped cases" ON public.verification_cases FOR SELECT TO authenticated USING (public.is_admin() OR (public.is_active_verifikator_team_member(team_id, NULL) AND public.team_has_village_scope(team_id, village_id)));
DROP POLICY IF EXISTS "Team members can view case events" ON public.verification_case_events;
CREATE POLICY "Team members can view case events" ON public.verification_case_events FOR SELECT TO authenticated USING (public.is_admin() OR EXISTS (SELECT 1 FROM public.verification_cases vc WHERE vc.id = case_id AND public.is_active_verifikator_team_member(vc.team_id, NULL)));

COMMENT ON TABLE public.verifikator_teams IS 'Operational verifier teams by region.';
COMMENT ON TABLE public.verifikator_team_members IS 'Operational team roles, separate from application role.';
COMMENT ON TABLE public.verification_cases IS 'Unified merchant/courier verification queue.';
COMMENT ON TABLE public.verification_case_events IS 'Append-only workflow and audit events.';

DO $bootstrap_do_verifikator_teams_workflow$
BEGIN
  NULL;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR unique_violation THEN NULL;
END $bootstrap_do_verifikator_teams_workflow$;

-- Team read scope for existing referral and commerce tables. Existing owner policies remain active.
DROP POLICY IF EXISTS "Team members can view team codes" ON public.verifikator_codes;
CREATE POLICY "Team members can view team codes"
  ON public.verifikator_codes FOR SELECT TO authenticated
  USING (public.is_admin() OR (team_id IS NOT NULL AND public.is_active_verifikator_team_member(team_id, NULL)));

DROP POLICY IF EXISTS "Team members can view team merchants" ON public.merchants;
CREATE POLICY "Team members can view team merchants"
  ON public.merchants FOR SELECT TO authenticated
  USING (verifikator_team_id IS NOT NULL AND public.is_active_verifikator_team_member(verifikator_team_id, NULL));

DROP POLICY IF EXISTS "Team members can view team couriers" ON public.couriers;
CREATE POLICY "Team members can view team couriers"
  ON public.couriers FOR SELECT TO authenticated
  USING (verifikator_team_id IS NOT NULL AND public.is_active_verifikator_team_member(verifikator_team_id, NULL));

DROP POLICY IF EXISTS "Team members can view team verifier earnings" ON public.verifikator_earnings;
CREATE POLICY "Team members can view team verifier earnings"
  ON public.verifikator_earnings FOR SELECT TO authenticated
  USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = verifikator_earnings.merchant_id
        AND m.verifikator_team_id IS NOT NULL
        AND public.is_active_verifikator_team_member(m.verifikator_team_id, NULL)
    )
  );
