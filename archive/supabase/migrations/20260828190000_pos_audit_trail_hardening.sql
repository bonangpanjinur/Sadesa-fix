-- Server-side audit trail for critical POS mutations.

CREATE INDEX IF NOT EXISTS idx_pos_audit_logs_entity_lookup
  ON public.pos_audit_logs(tenant_id, module, entity_type, entity_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.write_pos_audit_log()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row jsonb;
  v_old jsonb;
  v_tenant_id uuid;
  v_outlet_id uuid;
  v_entity_id text;
  v_action text;
BEGIN
  v_row := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  v_old := CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) ELSE NULL END;
  v_tenant_id := NULLIF(v_row->>'tenant_id', '')::uuid;
  v_outlet_id := NULLIF(v_row->>'outlet_id', '')::uuid;
  v_entity_id := COALESCE(v_row->>'id', v_row->>'sale_id', v_row->>'session_id');
  v_action := lower(TG_OP);

  IF v_tenant_id IS NOT NULL THEN
    INSERT INTO public.pos_audit_logs(
      tenant_id, outlet_id, user_id, action, module, entity_type,
      entity_id, description, old_values, new_values
    ) VALUES (
      v_tenant_id, v_outlet_id, auth.uid(), v_action, 'pos', TG_TABLE_NAME,
      v_entity_id, format('%s %s', v_action, TG_TABLE_NAME), v_old,
      CASE WHEN TG_OP <> 'DELETE' THEN v_row ELSE NULL END
    );
  END IF;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_pos_sales ON public.pos_sales;
CREATE TRIGGER trg_audit_pos_sales
AFTER INSERT OR UPDATE OR DELETE ON public.pos_sales
FOR EACH ROW EXECUTE FUNCTION public.write_pos_audit_log();

DROP TRIGGER IF EXISTS trg_audit_pos_sale_returns ON public.pos_sale_returns;
CREATE TRIGGER trg_audit_pos_sale_returns
AFTER INSERT OR UPDATE OR DELETE ON public.pos_sale_returns
FOR EACH ROW EXECUTE FUNCTION public.write_pos_audit_log();

DROP TRIGGER IF EXISTS trg_audit_pos_cash_sessions ON public.pos_cash_sessions;
CREATE TRIGGER trg_audit_pos_cash_sessions
AFTER INSERT OR UPDATE OR DELETE ON public.pos_cash_sessions
FOR EACH ROW EXECUTE FUNCTION public.write_pos_audit_log();

DROP TRIGGER IF EXISTS trg_audit_pos_stock_mutations ON public.pos_stock_mutations;
CREATE TRIGGER trg_audit_pos_stock_mutations
AFTER INSERT OR UPDATE OR DELETE ON public.pos_stock_mutations
FOR EACH ROW EXECUTE FUNCTION public.write_pos_audit_log();

DROP TRIGGER IF EXISTS trg_audit_pos_cash_mutations ON public.pos_cash_mutations;
CREATE TRIGGER trg_audit_pos_cash_mutations
AFTER INSERT OR UPDATE OR DELETE ON public.pos_cash_mutations
FOR EACH ROW EXECUTE FUNCTION public.write_pos_audit_log();

REVOKE ALL ON FUNCTION public.write_pos_audit_log() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.write_pos_audit_log() TO service_role;
