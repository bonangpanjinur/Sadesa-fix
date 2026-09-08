-- Repair the dispute/refund contract used by buyer, merchant, and admin pages.
-- The original refund_requests table predates the dispute workflow. This
-- bundle is safe to rerun on projects that already have some of these columns.

ALTER TABLE public.refund_requests
  ADD COLUMN IF NOT EXISTS title TEXT,
  ADD COLUMN IF NOT EXISTS category TEXT,
  ADD COLUMN IF NOT EXISTS dispute_status TEXT DEFAULT 'OPEN',
  ADD COLUMN IF NOT EXISTS merchant_response TEXT,
  ADD COLUMN IF NOT EXISTS merchant_responded_at TIMESTAMPTZ;

UPDATE public.refund_requests
SET title = 'Komplain Pesanan'
WHERE title IS NULL;

UPDATE public.refund_requests
SET category = 'Lainnya'
WHERE category IS NULL;

UPDATE public.refund_requests
SET dispute_status = CASE
  WHEN upper(COALESCE(status, '')) = 'APPROVED' THEN 'RESOLVED_REFUND'
  WHEN upper(COALESCE(status, '')) = 'REJECTED' THEN 'RESOLVED_REJECTED'
  ELSE 'OPEN'
END
WHERE dispute_status IS NULL
   OR dispute_status NOT IN (
     'OPEN',
     'IN_MEDIATION',
     'MERCHANT_RESPONDED',
     'RESOLVED_REFUND',
     'RESOLVED_REJECTED',
     'CLOSED'
   );

ALTER TABLE public.refund_requests
  ALTER COLUMN title SET DEFAULT 'Komplain Pesanan',
  ALTER COLUMN title SET NOT NULL,
  ALTER COLUMN category SET DEFAULT 'Lainnya',
  ALTER COLUMN category SET NOT NULL,
  ALTER COLUMN dispute_status SET DEFAULT 'OPEN',
  ALTER COLUMN dispute_status SET NOT NULL;

ALTER TABLE public.refund_requests
  DROP CONSTRAINT IF EXISTS refund_requests_dispute_status_check;
ALTER TABLE public.refund_requests
  ADD CONSTRAINT refund_requests_dispute_status_check CHECK (
    dispute_status IN (
      'OPEN',
      'IN_MEDIATION',
      'MERCHANT_RESPONDED',
      'RESOLVED_REFUND',
      'RESOLVED_REJECTED',
      'CLOSED'
    )
  );

CREATE INDEX IF NOT EXISTS idx_refund_requests_dispute_status
  ON public.refund_requests(dispute_status, created_at DESC);

NOTIFY pgrst, 'reload schema';