-- Keep delivery offer RPCs compatible with projects created before the
-- delivery_assignments.updated_at column was introduced.
ALTER TABLE public.delivery_assignments
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

UPDATE public.delivery_assignments
SET updated_at = COALESCE(updated_at, created_at, now())
WHERE updated_at IS NULL;
