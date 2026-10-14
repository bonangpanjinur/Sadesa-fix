-- Unify POS customers with CRM while keeping legacy auth-user references compatible.
ALTER TABLE public.pos_customers
  ADD COLUMN IF NOT EXISTS auth_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL$bootstrap_sql_29238c01ec37$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_29238c01ec37$;

DO $bootstrap_do_dda0ecb47a01$
BEGIN
  EXECUTE $bootstrap_sql_dda0ecb47a01$CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_customers_tenant_auth_user
  ON public.pos_customers(tenant_id, auth_user_id) WHERE auth_user_id IS NOT NULL$bootstrap_sql_dda0ecb47a01$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dda0ecb47a01$;

DO $bootstrap_do_3e2e61fa1590$
BEGIN
  EXECUTE $bootstrap_sql_3e2e61fa1590$CREATE INDEX IF NOT EXISTS idx_pos_customers_tenant_phone
  ON public.pos_customers(tenant_id, phone) WHERE phone IS NOT NULL$bootstrap_sql_3e2e61fa1590$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3e2e61fa1590$;

DO $bootstrap_do_b209a1cd0526$
BEGIN
  EXECUTE $bootstrap_sql_b209a1cd0526$ALTER TABLE public.crm_segment_members DROP CONSTRAINT IF EXISTS crm_segment_members_pkey$bootstrap_sql_b209a1cd0526$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b209a1cd0526$;

DO $bootstrap_do_b260a58a164e$
BEGIN
  EXECUTE $bootstrap_sql_b260a58a164e$ALTER TABLE public.crm_segment_members
  ALTER COLUMN customer_id DROP NOT NULL$bootstrap_sql_b260a58a164e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b260a58a164e$;

DO $bootstrap_do_945ac06f18f2$
BEGIN
  EXECUTE $bootstrap_sql_945ac06f18f2$ALTER TABLE public.crm_segment_members
  ADD COLUMN IF NOT EXISTS pos_customer_id uuid REFERENCES public.pos_customers(id) ON DELETE CASCADE$bootstrap_sql_945ac06f18f2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_945ac06f18f2$;

DO $bootstrap_do_491723525ee0$
BEGIN
  EXECUTE $bootstrap_sql_491723525ee0$CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_segment_members_auth
  ON public.crm_segment_members(segment_id, customer_id) WHERE customer_id IS NOT NULL$bootstrap_sql_491723525ee0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_491723525ee0$;

DO $bootstrap_do_be3cf7c2ef7f$
BEGIN
  EXECUTE $bootstrap_sql_be3cf7c2ef7f$CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_segment_members_pos
  ON public.crm_segment_members(segment_id, pos_customer_id) WHERE pos_customer_id IS NOT NULL$bootstrap_sql_be3cf7c2ef7f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_be3cf7c2ef7f$;

DO $bootstrap_do_76602de34177$
BEGIN
  EXECUTE $bootstrap_sql_76602de34177$ALTER TABLE public.crm_segment_members
  DROP CONSTRAINT IF EXISTS crm_segment_members_target_check$bootstrap_sql_76602de34177$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_76602de34177$;

DO $bootstrap_do_24221a384881$
BEGIN
  EXECUTE $bootstrap_sql_24221a384881$ALTER TABLE public.crm_segment_members
  ADD CONSTRAINT crm_segment_members_target_check CHECK (customer_id IS NOT NULL OR pos_customer_id IS NOT NULL)$bootstrap_sql_24221a384881$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_24221a384881$;

DO $bootstrap_do_2ffe00e1dc22$
BEGIN
  EXECUTE $bootstrap_sql_2ffe00e1dc22$ALTER TABLE public.crm_campaign_deliveries
  ALTER COLUMN customer_id DROP NOT NULL$bootstrap_sql_2ffe00e1dc22$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2ffe00e1dc22$;

DO $bootstrap_do_b2ef251433c6$
BEGIN
  EXECUTE $bootstrap_sql_b2ef251433c6$ALTER TABLE public.crm_campaign_deliveries
  ADD COLUMN IF NOT EXISTS pos_customer_id uuid REFERENCES public.pos_customers(id) ON DELETE CASCADE$bootstrap_sql_b2ef251433c6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b2ef251433c6$;

DO $bootstrap_do_07400bf432f3$
BEGIN
  EXECUTE $bootstrap_sql_07400bf432f3$CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_campaign_deliveries_pos
  ON public.crm_campaign_deliveries(campaign_id, pos_customer_id) WHERE pos_customer_id IS NOT NULL$bootstrap_sql_07400bf432f3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_07400bf432f3$;

DO $bootstrap_do_3075445bd077$
BEGIN
  EXECUTE $bootstrap_sql_3075445bd077$ALTER TABLE public.crm_campaign_deliveries
  DROP CONSTRAINT IF EXISTS crm_campaign_deliveries_target_check$bootstrap_sql_3075445bd077$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3075445bd077$;

DO $bootstrap_do_c61def2ebbd4$
BEGIN
  EXECUTE $bootstrap_sql_c61def2ebbd4$ALTER TABLE public.crm_campaign_deliveries
  ADD CONSTRAINT crm_campaign_deliveries_target_check CHECK (customer_id IS NOT NULL OR pos_customer_id IS NOT NULL)$bootstrap_sql_c61def2ebbd4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c61def2ebbd4$;

DO $bootstrap_do_c9a6da3e9c13$
BEGIN
  EXECUTE $bootstrap_sql_c9a6da3e9c13$ALTER TABLE public.crm_abandoned_carts
  ALTER COLUMN customer_id DROP NOT NULL$bootstrap_sql_c9a6da3e9c13$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c9a6da3e9c13$;

DO $bootstrap_do_d601740ad3af$
BEGIN
  EXECUTE $bootstrap_sql_d601740ad3af$ALTER TABLE public.crm_abandoned_carts
  ADD COLUMN IF NOT EXISTS pos_customer_id uuid REFERENCES public.pos_customers(id) ON DELETE CASCADE$bootstrap_sql_d601740ad3af$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d601740ad3af$;

DO $bootstrap_do_380b6aabaabf$
BEGIN
  EXECUTE $bootstrap_sql_380b6aabaabf$ALTER TABLE public.crm_abandoned_carts
  DROP CONSTRAINT IF EXISTS crm_abandoned_carts_target_check$bootstrap_sql_380b6aabaabf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_380b6aabaabf$;

DO $bootstrap_do_4abf4bf9fb7c$
BEGIN
  EXECUTE $bootstrap_sql_4abf4bf9fb7c$ALTER TABLE public.crm_abandoned_carts
  ADD CONSTRAINT crm_abandoned_carts_target_check CHECK (customer_id IS NOT NULL OR pos_customer_id IS NOT NULL)$bootstrap_sql_4abf4bf9fb7c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4abf4bf9fb7c$;

DO $bootstrap_do_b9e50a5b15a1$
BEGIN
  EXECUTE $bootstrap_sql_b9e50a5b15a1$ALTER TABLE public.notification_delivery_jobs
  ALTER COLUMN recipient_id DROP NOT NULL$bootstrap_sql_b9e50a5b15a1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b9e50a5b15a1$;

DO $bootstrap_do_2504aac475f6$
BEGIN
  EXECUTE $bootstrap_sql_2504aac475f6$ALTER TABLE public.notification_delivery_jobs
  ADD COLUMN IF NOT EXISTS recipient_pos_customer_id uuid REFERENCES public.pos_customers(id) ON DELETE CASCADE$bootstrap_sql_2504aac475f6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2504aac475f6$;

DO $bootstrap_do_89354410cb9d$
BEGIN
  EXECUTE $bootstrap_sql_89354410cb9d$ALTER TABLE public.notification_delivery_jobs
  DROP CONSTRAINT IF EXISTS notification_delivery_jobs_recipient_check$bootstrap_sql_89354410cb9d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_89354410cb9d$;

DO $bootstrap_do_bc3f223af9d4$
BEGIN
  EXECUTE $bootstrap_sql_bc3f223af9d4$ALTER TABLE public.notification_delivery_jobs
  ADD CONSTRAINT notification_delivery_jobs_recipient_check CHECK (recipient_id IS NOT NULL OR recipient_pos_customer_id IS NOT NULL)$bootstrap_sql_bc3f223af9d4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bc3f223af9d4$;

DO $bootstrap_do_776ecb5f5d68$
BEGIN
  EXECUTE $bootstrap_sql_776ecb5f5d68$CREATE INDEX IF NOT EXISTS idx_notification_jobs_pos_recipient
  ON public.notification_delivery_jobs(recipient_pos_customer_id, created_at DESC)$bootstrap_sql_776ecb5f5d68$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_776ecb5f5d68$;

DO $bootstrap_do_19e30bdcade6$
BEGIN
  EXECUTE $bootstrap_sql_19e30bdcade6$DROP POLICY IF EXISTS "Users view own notification jobs" ON public.notification_delivery_jobs$bootstrap_sql_19e30bdcade6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_19e30bdcade6$;

DO $bootstrap_do_204cabf05e6c$
BEGIN
  EXECUTE $bootstrap_sql_204cabf05e6c$CREATE POLICY "Users view own notification jobs" ON public.notification_delivery_jobs FOR SELECT TO authenticated
  USING (
    recipient_id = auth.uid()
    OR recipient_pos_customer_id IN (SELECT id FROM public.pos_customers WHERE auth_user_id = auth.uid())
    OR public.is_admin()
  )$bootstrap_sql_204cabf05e6c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_204cabf05e6c$;

DO $bootstrap_do_edb636ad5498$
BEGIN
  EXECUTE $bootstrap_sql_edb636ad5498$CREATE OR REPLACE FUNCTION public.enqueue_due_crm_campaign_jobs(p_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_campaign record;
  v_target record;
  v_delivery_id uuid;
  v_job_id uuid;
  v_queued integer := 0;
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'CRM dispatcher requires admin or service role' USING ERRCODE = '42501';
  END IF;
  FOR v_campaign IN
    SELECT c.* FROM public.crm_campaigns c
    WHERE c.status = 'scheduled' AND COALESCE(c.scheduled_at, now()) <= now()
    ORDER BY COALESCE(c.scheduled_at, c.created_at)
    LIMIT v_limit FOR UPDATE SKIP LOCKED
  LOOP
    FOR v_target IN
      SELECT sm.customer_id, NULL::uuid AS pos_customer_id, COALESCE(u.raw_user_meta_data->>'phone', u.phone) AS phone
      FROM public.crm_segment_members sm JOIN auth.users u ON u.id = sm.customer_id
      WHERE v_campaign.segment_id IS NOT NULL AND sm.segment_id = v_campaign.segment_id
      UNION ALL
      SELECT NULL::uuid, sm.pos_customer_id, pc.phone
      FROM public.crm_segment_members sm JOIN public.pos_customers pc ON pc.id = sm.pos_customer_id
      WHERE v_campaign.segment_id IS NOT NULL AND sm.segment_id = v_campaign.segment_id AND pc.is_active = true
    LOOP
      INSERT INTO public.crm_campaign_deliveries(campaign_id, customer_id, pos_customer_id, status)
      VALUES (v_campaign.id, v_target.customer_id, v_target.pos_customer_id, 'queued')
      ON CONFLICT DO NOTHING
      RETURNING id INTO v_delivery_id;
      IF v_delivery_id IS NULL THEN CONTINUE; END IF;
      INSERT INTO public.notification_delivery_jobs(
        tenant_id, recipient_id, recipient_pos_customer_id, channel, template_key, payload, dedupe_key
      ) VALUES (
        v_campaign.tenant_id, v_target.customer_id, v_target.pos_customer_id, v_campaign.channel, 'crm_campaign',
        jsonb_build_object('campaign_id', v_campaign.id, 'delivery_id', v_delivery_id, 'to', v_target.phone, 'message', v_campaign.template),
        'crm:' || v_campaign.id::text || ':' || COALESCE(v_target.customer_id, v_target.pos_customer_id)::text
      )
      ON CONFLICT (tenant_id, dedupe_key) DO NOTHING
      RETURNING id INTO v_job_id;
      IF v_job_id IS NOT NULL THEN v_queued := v_queued + 1; END IF;
    END LOOP;
    UPDATE public.crm_campaigns SET status = 'sending' WHERE id = v_campaign.id;
  END LOOP;
  RETURN jsonb_build_object('queued', v_queued);
END; $$$bootstrap_sql_edb636ad5498$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_edb636ad5498$;

DO $bootstrap_do_b1edf0c291d5$
BEGIN
  EXECUTE $bootstrap_sql_b1edf0c291d5$CREATE OR REPLACE FUNCTION public.mark_crm_cart_recovered_after_pos_sale()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.customer_id IS NOT NULL THEN
    UPDATE public.crm_abandoned_carts
    SET recovered_at = now()
    WHERE tenant_id = NEW.tenant_id
      AND (customer_id = NEW.customer_id OR pos_customer_id = NEW.customer_id)
      AND recovered_at IS NULL;
  END IF;
  RETURN NEW;
END; $$$bootstrap_sql_b1edf0c291d5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b1edf0c291d5$;

DO $bootstrap_do_9bac00e61516$
BEGIN
  EXECUTE $bootstrap_sql_9bac00e61516$DROP TRIGGER IF EXISTS trg_mark_crm_cart_recovered ON public.pos_sales$bootstrap_sql_9bac00e61516$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9bac00e61516$;

DO $bootstrap_do_a2e628f9c8ef$
BEGIN
  EXECUTE $bootstrap_sql_a2e628f9c8ef$CREATE TRIGGER trg_mark_crm_cart_recovered
AFTER INSERT ON public.pos_sales FOR EACH ROW EXECUTE FUNCTION public.mark_crm_cart_recovered_after_pos_sale()$bootstrap_sql_a2e628f9c8ef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a2e628f9c8ef$;

DO $bootstrap_do_72df01e736ac$
BEGIN
  EXECUTE $bootstrap_sql_72df01e736ac$-- Best-effort deterministic backfill for existing customers. Ambiguous emails remain unmapped.
UPDATE public.pos_customers pc
SET auth_user_id = u.id
FROM auth.users u
WHERE pc.auth_user_id IS NULL
  AND pc.email IS NOT NULL
  AND lower(trim(pc.email)) = lower(trim(u.email))
  AND NOT EXISTS (
    SELECT 1 FROM public.pos_customers occupied
    WHERE occupied.tenant_id = pc.tenant_id AND occupied.auth_user_id = u.id
  )$bootstrap_sql_72df01e736ac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_72df01e736ac$;

DO $bootstrap_do_47166d3316f4$
BEGIN
  EXECUTE $bootstrap_sql_47166d3316f4$
