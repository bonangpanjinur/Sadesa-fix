-- Create storage bucket for courier documents
INSERT INTO storage.buckets (id, name, public) VALUES ('courier-documents', 'courier-documents', false)
ON CONFLICT DO NOTHING$bootstrap_sql_360b35257b74$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_360b35257b74$;

DO $bootstrap_do_5a5229db5792$
BEGIN
  EXECUTE $bootstrap_sql_5a5229db5792$-- Storage policies for courier-documents bucket (safe to retry)
DROP POLICY IF EXISTS "Anyone can upload courier documents" ON storage.objects$bootstrap_sql_5a5229db5792$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5a5229db5792$;

DO $bootstrap_do_d7ac9ceda076$
BEGIN
  EXECUTE $bootstrap_sql_d7ac9ceda076$DROP POLICY IF EXISTS "Admins can view all courier documents" ON storage.objects$bootstrap_sql_d7ac9ceda076$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d7ac9ceda076$;

DO $bootstrap_do_a6eaa6b85021$
BEGIN
  EXECUTE $bootstrap_sql_a6eaa6b85021$DROP POLICY IF EXISTS "Couriers can view own documents" ON storage.objects$bootstrap_sql_a6eaa6b85021$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a6eaa6b85021$;

DO $bootstrap_do_b914c23c42dd$
BEGIN
  EXECUTE $bootstrap_sql_b914c23c42dd$DROP POLICY IF EXISTS "Admins can delete courier documents" ON storage.objects$bootstrap_sql_b914c23c42dd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b914c23c42dd$;

DO $bootstrap_do_3ad60cc8f9bb$
BEGIN
  EXECUTE $bootstrap_sql_3ad60cc8f9bb$DROP POLICY IF EXISTS "Anyone can upload courier documents" ON storage.objects$bootstrap_sql_3ad60cc8f9bb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3ad60cc8f9bb$;

DO $bootstrap_do_9671ea5d3fd6$
BEGIN
  EXECUTE $bootstrap_sql_9671ea5d3fd6$CREATE POLICY "Anyone can upload courier documents" ON storage.objects
FOR INSERT WITH CHECK (bucket_id = 'courier-documents')$bootstrap_sql_9671ea5d3fd6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9671ea5d3fd6$;

DO $bootstrap_do_4d4760b432ca$
BEGIN
  EXECUTE $bootstrap_sql_4d4760b432ca$DROP POLICY IF EXISTS "Admins can view all courier documents" ON storage.objects$bootstrap_sql_4d4760b432ca$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4d4760b432ca$;

DO $bootstrap_do_0a7d0cf26f27$
BEGIN
  EXECUTE $bootstrap_sql_0a7d0cf26f27$CREATE POLICY "Admins can view all courier documents" ON storage.objects
FOR SELECT USING (bucket_id = 'courier-documents' AND (is_admin() OR is_verifikator()))$bootstrap_sql_0a7d0cf26f27$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0a7d0cf26f27$;

DO $bootstrap_do_fc94e527197c$
BEGIN
  EXECUTE $bootstrap_sql_fc94e527197c$DROP POLICY IF EXISTS "Couriers can view own documents" ON storage.objects$bootstrap_sql_fc94e527197c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fc94e527197c$;

DO $bootstrap_do_9cda47098dd3$
BEGIN
  EXECUTE $bootstrap_sql_9cda47098dd3$CREATE POLICY "Couriers can view own documents" ON storage.objects
FOR SELECT USING (
    bucket_id = 'courier-documents'
    AND auth.uid()::text = (storage.foldername(name))[1]
)$bootstrap_sql_9cda47098dd3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9cda47098dd3$;

DO $bootstrap_do_0a4d625b3743$
BEGIN
  EXECUTE $bootstrap_sql_0a4d625b3743$DROP POLICY IF EXISTS "Admins can delete courier documents" ON storage.objects$bootstrap_sql_0a4d625b3743$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0a4d625b3743$;

DO $bootstrap_do_df91f7f5efe4$
BEGIN
  EXECUTE $bootstrap_sql_df91f7f5efe4$CREATE POLICY "Admins can delete courier documents" ON storage.objects
FOR DELETE USING (bucket_id = 'courier-documents' AND is_admin())$bootstrap_sql_df91f7f5efe4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_df91f7f5efe4$;

DO $bootstrap_do_f14be90e4e47$
BEGIN
  EXECUTE $bootstrap_sql_f14be90e4e47$
