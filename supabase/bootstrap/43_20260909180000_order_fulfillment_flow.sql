-- Order fulfillment flow repair
-- Keeps legacy statuses readable while allowing the complete merchant/buyer lifecycle.
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_status_check;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check CHECK (status IN (
    'NEW',
    'PENDING_CONFIRMATION',
    'PENDING_PAYMENT',
    'PROCESSED',
    'READY',
    'ASSIGNED',
    'COURIER_ASSIGNED',
    'COURIER_ACCEPTED',
    'COURIER_REJECTED',
    'PICKED_UP',
    'SENT',
    'DELIVERING',
    'DELIVERED',
    'DONE',
    'CANCELED',
    'REJECTED',
    'REJECTED_BY_BUYER',
    'REFUNDED'
  ));

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_notes text,
  ADD COLUMN IF NOT EXISTS courier_rejected_ids uuid[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS courier_assigned_at timestamptz,
  ADD COLUMN IF NOT EXISTS courier_accepted_at timestamptz,
  ADD COLUMN IF NOT EXISTS ready_at timestamptz,
  ADD COLUMN IF NOT EXISTS delivered_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_orders_fulfillment_status
  ON public.orders (merchant_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_orders_courier_queue
  ON public.orders (status, delivery_type, created_at DESC)
  WHERE delivery_type = 'INTERNAL';

COMMENT ON COLUMN public.orders.status IS
  'Lifecycle: NEW/PENDING_PAYMENT -> PROCESSED -> READY -> ASSIGNED/COURIER_ACCEPTED -> PICKED_UP -> DELIVERING -> DELIVERED -> DONE';
COMMENT ON COLUMN public.orders.courier_rejected_ids IS
  'Kurir yang menolak order ini dan tidak boleh ditawarkan ulang untuk order yang sama.';
