-- CRM campaign dispatch into the durable notification queue.
ALTER TABLE public.notification_delivery_jobs
  ADD COLUMN IF NOT EXISTS dedupe_key text;
CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_jobs_tenant_dedupe
  ON public.notification_delivery_jobs(tenant_id, dedupe_key)
  WHERE dedupe_key IS NOT NULL;

CREATE OR REPLACE FUNCTION public.enqueue_due_crm_campaign_jobs(p_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_campaign record;
  v_member record;
  v_delivery_id uuid;
  v_job_id uuid;
  v_queued integer := 0;
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
  v_phone text;
  v_message text;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'CRM dispatcher requires admin or service role' USING ERRCODE = '42501';
  END IF;
  FOR v_campaign IN
    SELECT c.* FROM public.crm_campaigns c
    WHERE c.status = 'scheduled' AND COALESCE(c.scheduled_at, now()) <= now()
    ORDER BY COALESCE(c.scheduled_at, c.created_at)
    LIMIT v_limit
    FOR UPDATE SKIP LOCKED
  LOOP
    FOR v_member IN
      SELECT sm.customer_id
      FROM public.crm_segment_members sm
      WHERE v_campaign.segment_id IS NOT NULL AND sm.segment_id = v_campaign.segment_id
    LOOP
      INSERT INTO public.crm_campaign_deliveries(campaign_id, customer_id, status)
      VALUES (v_campaign.id, v_member.customer_id, 'queued')
      ON CONFLICT (campaign_id, customer_id) DO NOTHING
      RETURNING id INTO v_delivery_id;
      IF v_delivery_id IS NULL THEN CONTINUE; END IF;

      SELECT COALESCE(u.raw_user_meta_data->>'phone', u.phone) INTO v_phone
      FROM auth.users u WHERE u.id = v_member.customer_id;
      v_message := replace(replace(v_campaign.template, '{{customer_id}}', v_member.customer_id::text), '{{campaign_name}}', v_campaign.name);
      INSERT INTO public.notification_delivery_jobs(
        tenant_id, recipient_id, channel, template_key, payload, dedupe_key
      ) VALUES (
        v_campaign.tenant_id, v_member.customer_id, v_campaign.channel, 'crm_campaign',
        jsonb_build_object('campaign_id', v_campaign.id, 'delivery_id', v_delivery_id, 'to', v_phone, 'message', v_message),
        'crm:' || v_campaign.id::text || ':' || v_member.customer_id::text
      )
      ON CONFLICT (tenant_id, dedupe_key) DO NOTHING
      RETURNING id INTO v_job_id;
      IF v_job_id IS NOT NULL THEN v_queued := v_queued + 1; END IF;
    END LOOP;
    UPDATE public.crm_campaigns SET status = 'sending' WHERE id = v_campaign.id;
  END LOOP;
  RETURN jsonb_build_object('queued', v_queued);
END;
$$;
REVOKE ALL ON FUNCTION public.enqueue_due_crm_campaign_jobs(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_due_crm_campaign_jobs(integer) TO service_role;
