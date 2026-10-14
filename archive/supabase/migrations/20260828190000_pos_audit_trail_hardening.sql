-- Server-side audit trail for critical POS mutations.

CREATE INDEX IF NOT EXISTS idx_pos_audit_logs_entity_lookup
  ON public.pos_audit_logs(tenant_id, module, entity_type, entity_id, created_at DESC)$bootstrap_sql_856e136dbf92$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_856e136dbf92$;

DO $bootstrap_do_ff51f69a16c0$
BEGIN
  EXECUTE $bootstrap_sql_ff51f69a16c0$CREATE OR REPLACE FUNCTION public.write_pos_audit_log()
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
$$$bootstrap_sql_ff51f69a16c0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ff51f69a16c0$;

DO $bootstrap_do_472bf91ff960$
BEGIN
  EXECUTE $bootstrap_sql_472bf91ff960$DROP TRIGGER IF EXISTS trg_audit_pos_sales ON public.pos_sales$bootstrap_sql_472bf91ff960$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_472bf91ff960$;

DO $bootstrap_do_0103625bae96$
BEGIN
  EXECUTE $bootstrap_sql_0103625bae96$CREATE TRIGGER trg_audit_pos_sales
AFTER INSERT OR UPDATE OR DELETE ON public.pos_sales
FOR EACH ROW EXECUTE FUNCTION public.write_pos_audit_log()$bootstrap_sql_0103625bae96$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0103625bae96$;

DO $bootstrap_do_47bf40ee7797$
BEGIN
  EXECUTE $bootstrap_sql_47bf40ee7797$DROP TRIGGER IF EXISTS trg_audit_pos_sale_returns ON public.pos_sale_returns$bootstrap_sql_47bf40ee7797$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_47bf40ee7797$;

DO $bootstrap_do_588789c09b10$
BEGIN
  EXECUTE $bootstrap_sql_588789c09b10$CREATE TRIGGER trg_audit_pos_sale_returns
AFTER INSERT OR UPDATE OR DELETE ON public.pos_sale_returns
FOR EACH ROW EXECUTE FUNCTION public.write_pos_audit_log()$bootstrap_sql_588789c09b10$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_588789c09b10$;

DO $bootstrap_do_bcb3f9866ee2$
BEGIN
  EXECUTE $bootstrap_sql_bcb3f9866ee2$DROP TRIGGER IF EXISTS trg_audit_pos_cash_sessions ON public.pos_cash_sessions$bootstrap_sql_bcb3f9866ee2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bcb3f9866ee2$;

DO $bootstrap_do_b4b1d4cb4886$
BEGIN
  EXECUTE $bootstrap_sql_b4b1d4cb4886$CREATE TRIGGER trg_audit_pos_cash_sessions
AFTER INSERT OR UPDATE OR DELETE ON public.pos_cash_sessions
FOR EACH ROW EXECUTE FUNCTION public.write_pos_audit_log()$bootstrap_sql_b4b1d4cb4886$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b4b1d4cb4886$;

DO $bootstrap_do_60f183780e7b$
BEGIN
  EXECUTE $bootstrap_sql_60f183780e7b$DROP TRIGGER IF EXISTS trg_audit_pos_stock_mutations ON public.pos_stock_mutations$bootstrap_sql_60f183780e7b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_60f183780e7b$;

DO $bootstrap_do_3897fcb6ee3a$
BEGIN
  EXECUTE $bootstrap_sql_3897fcb6ee3a$CREATE TRIGGER trg_audit_pos_stock_mutations
AFTER INSERT OR UPDATE OR DELETE ON public.pos_stock_mutations
FOR EACH ROW EXECUTE FUNCTION public.write_pos_audit_log()$bootstrap_sql_3897fcb6ee3a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3897fcb6ee3a$;

DO $bootstrap_do_534c061c75d7$
BEGIN
  EXECUTE $bootstrap_sql_534c061c75d7$DROP TRIGGER IF EXISTS trg_audit_pos_cash_mutations ON public.pos_cash_mutations$bootstrap_sql_534c061c75d7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_534c061c75d7$;

DO $bootstrap_do_e231c727c410$
BEGIN
  EXECUTE $bootstrap_sql_e231c727c410$CREATE TRIGGER trg_audit_pos_cash_mutations
AFTER INSERT OR UPDATE OR DELETE ON public.pos_cash_mutations
FOR EACH ROW EXECUTE FUNCTION public.write_pos_audit_log()$bootstrap_sql_e231c727c410$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e231c727c410$;

DO $bootstrap_do_0f1f2b0fcdc9$
BEGIN
  EXECUTE $bootstrap_sql_0f1f2b0fcdc9$REVOKE ALL ON FUNCTION public.write_pos_audit_log() FROM PUBLIC, anon, authenticated$bootstrap_sql_0f1f2b0fcdc9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0f1f2b0fcdc9$;

DO $bootstrap_do_b6bef175cf01$
BEGIN
  EXECUTE $bootstrap_sql_b6bef175cf01$GRANT EXECUTE ON FUNCTION public.write_pos_audit_log() TO service_role$bootstrap_sql_b6bef175cf01$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b6bef175cf01$;

DO $bootstrap_do_8a675dea2122$
BEGIN
  EXECUTE $bootstrap_sql_8a675dea2122$
