-- Compatibility fix for existing Supabase projects.
-- The delivery_assignments table may have been created before the
-- create_courier_order RPC started writing created_by.

ALTER TABLE public.delivery_assignments
  ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_delivery_assignments_created_by
  ON public.delivery_assignments(created_by);

NOTIFY pgrst, 'reload schema';

-- Existing assignments remain unchanged; created_by is NULL for old rows.
-- New courier bookings will store auth.uid() in this column.
