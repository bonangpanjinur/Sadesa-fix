CREATE TABLE IF NOT EXISTS public.business_disputes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  reporter_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  subject_type text NOT NULL CHECK (subject_type IN ('order','payment','refund','delivery','product','account','payout')),
  subject_id uuid,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','investigating','resolved','rejected','closed')),
  priority text NOT NULL DEFAULT 'normal' CHECK (priority IN ('low','normal','high','urgent')),
  amount numeric(15,2) CHECK (amount IS NULL OR amount >= 0),
  evidence jsonb NOT NULL DEFAULT '[]'::jsonb,
  resolution text,
  assigned_to uuid REFERENCES auth.users(id),
  resolved_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_business_disputes_status ON public.business_disputes(status, priority, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_business_disputes_subject ON public.business_disputes(subject_type, subject_id);

CREATE TABLE IF NOT EXISTS public.approval_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  requester_id uuid NOT NULL REFERENCES auth.users(id),
  request_type text NOT NULL CHECK (request_type IN ('refund','discount','void','negative_stock','payout','bank_account','stock_adjustment','price_override')),
  subject_id uuid,
  requested_amount numeric(15,2) CHECK (requested_amount IS NULL OR requested_amount >= 0),
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','cancelled')),
  required_level integer NOT NULL DEFAULT 1 CHECK (required_level > 0),
  approved_level integer NOT NULL DEFAULT 0 CHECK (approved_level >= 0),
  decided_by uuid REFERENCES auth.users(id),
  decided_at timestamptz,
  decision_notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_approval_requests_pending ON public.approval_requests(tenant_id, request_type, status, created_at DESC);

ALTER TABLE public.business_disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.approval_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users create disputes" ON public.business_disputes FOR INSERT TO authenticated WITH CHECK (reporter_id = auth.uid());
CREATE POLICY "Participants view disputes" ON public.business_disputes FOR SELECT TO authenticated USING (reporter_id = auth.uid() OR assigned_to = auth.uid() OR public.is_admin());
CREATE POLICY "Admins manage disputes" ON public.business_disputes FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "Tenant users view approvals" ON public.approval_requests FOR SELECT TO authenticated USING (requester_id = auth.uid() OR public.is_admin() OR tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true));
CREATE POLICY "Users create approvals" ON public.approval_requests FOR INSERT TO authenticated WITH CHECK (requester_id = auth.uid());
CREATE POLICY "Admins manage approvals" ON public.approval_requests FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.decide_approval_request(p_request_id uuid, p_approve boolean, p_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_request public.approval_requests%ROWTYPE; v_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Approval requires admin access' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_request FROM public.approval_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR v_request.status <> 'pending' THEN RAISE EXCEPTION 'Approval request is not pending' USING ERRCODE = '55000'; END IF;
  v_status := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
  UPDATE public.approval_requests SET status = v_status, approved_level = CASE WHEN p_approve THEN required_level ELSE approved_level END,
    decided_by = auth.uid(), decided_at = now(), decision_notes = NULLIF(trim(p_notes), '') WHERE id = p_request_id;
  RETURN jsonb_build_object('request_id', p_request_id, 'status', v_status);
END; $$;
REVOKE ALL ON FUNCTION public.decide_approval_request(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_approval_request(uuid, boolean, text) TO authenticated;
