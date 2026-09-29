-- CI-only regression test for ride_requests RLS (run on a disposable clean DB).
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(id, email) VALUES
  ('a1000000-0000-4000-8000-000000000001', 'ride-rls-buyer-a@test.local'),
  ('a1000000-0000-4000-8000-000000000002', 'ride-rls-buyer-b@test.local'),
  ('a1000000-0000-4000-8000-000000000003', 'ride-rls-courier-a@test.local'),
  ('a1000000-0000-4000-8000-000000000004', 'ride-rls-courier-b@test.local')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.couriers (
  id, user_id, name, phone, province, city, district, subdistrict, address,
  ktp_number, ktp_image_url, photo_url, vehicle_image_url,
  registration_status, status, is_available, current_lat, current_lng, last_location_update
) VALUES
  ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000003', 'CI Courier A', '080000000001', 'CI', 'CI', 'CI', 'CI', 'CI', 'CI-A', 'https://example.invalid/ktp-a', 'https://example.invalid/photo-a', 'https://example.invalid/vehicle-a', 'APPROVED', 'ACTIVE', true, -7.3, 108.2, now()),
  ('a2000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000004', 'CI Courier B', '080000000002', 'CI', 'CI', 'CI', 'CI', 'CI', 'CI-B', 'https://example.invalid/ktp-b', 'https://example.invalid/photo-b', 'https://example.invalid/vehicle-b', 'APPROVED', 'ACTIVE', true, -7.3, 108.2, now())
ON CONFLICT (id) DO NOTHING;

-- Insert as canceled first to avoid firing the legacy AFTER INSERT dispatch trigger,
-- then transition the fixture to SEARCHING without dispatch side effects.
INSERT INTO public.ride_requests (
  id, passenger_id, pickup_lat, pickup_lng, destination_lat, destination_lng, status
) VALUES
  ('a3000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', -7.30, 108.20, -7.31, 108.21, 'CANCELLED'),
  ('a3000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000002', -7.32, 108.22, -7.33, 108.23, 'CANCELLED');
UPDATE public.ride_requests SET status = 'SEARCHING'
WHERE id IN ('a3000000-0000-4000-8000-000000000001', 'a3000000-0000-4000-8000-000000000002');

INSERT INTO public.ride_request_offers (ride_id, courier_id, distance_km, status, offered_at, expires_at)
VALUES (
  'a3000000-0000-4000-8000-000000000001',
  'a2000000-0000-4000-8000-000000000001',
  1.0,
  'PENDING',
  now() - interval '1 second',
  now() + interval '30 seconds'
);

-- A buyer's exact active-ride query must return only their own row without a 500.
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
SET LOCAL "request.jwt.claim.role" = 'authenticated';
DO $$
DECLARE n integer; n_other integer; duplicate_rejected boolean := false;
BEGIN
  SELECT count(*) INTO n
  FROM public.ride_requests
  WHERE passenger_id = auth.uid()
    AND status IN ('SEARCHING', 'ACCEPTED', 'PICKED_UP', 'IN_TRANSIT');
  IF n <> 1 THEN RAISE EXCEPTION 'Buyer active ride visibility failed: expected 1 row, got %', n; END IF;
  SELECT count(*) INTO n_other
  FROM public.ride_requests
  WHERE id = 'a3000000-0000-4000-8000-000000000002';
  IF n_other <> 0 THEN RAISE EXCEPTION 'Buyer read another passenger ride'; END IF;
  BEGIN
    PERFORM public.create_ride_request(-7.30, 108.20, 'CI pickup', -7.31, 108.21, 'CI destination');
  EXCEPTION WHEN unique_violation THEN
    duplicate_rejected := true;
  END;
  IF NOT duplicate_rejected THEN
    RAISE EXCEPTION 'create_ride_request allowed a second active ride for the same buyer';
  END IF;
END $$;
RESET ROLE;

-- The courier holding the unexpired offer sees the SEARCHING ride.
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000003';
SET LOCAL "request.jwt.claim.role" = 'authenticated';
DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n
  FROM public.ride_requests
  WHERE id = 'a3000000-0000-4000-8000-000000000001'
    AND status = 'SEARCHING';
  IF n <> 1 THEN RAISE EXCEPTION 'Target courier offer visibility failed: expected 1 row, got %', n; END IF;
END $$;
RESET ROLE;

-- A different courier cannot read a ride without their own live offer.
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000004';
SET LOCAL "request.jwt.claim.role" = 'authenticated';
DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n
  FROM public.ride_requests
  WHERE status = 'SEARCHING';
  IF n <> 0 THEN RAISE EXCEPTION 'Untargeted courier saw % SEARCHING rides', n; END IF;
END $$;
RESET ROLE;

-- Once the courier has an active ride, a stale/other SEARCHING offer is hidden,
-- while their assigned active ride remains readable.
INSERT INTO public.ride_requests (
  id, passenger_id, driver_id, pickup_lat, pickup_lng, destination_lat, destination_lng, status
) VALUES (
  'a3000000-0000-4000-8000-000000000003',
  'a1000000-0000-4000-8000-000000000002',
  'a2000000-0000-4000-8000-000000000001',
  -7.34, 108.24, -7.35, 108.25, 'ACCEPTED'
);
INSERT INTO public.ride_requests (
  id, passenger_id, driver_id, pickup_lat, pickup_lng, destination_lat, destination_lng, status
) VALUES (
  'a3000000-0000-4000-8000-000000000004',
  'a1000000-0000-4000-8000-000000000001',
  'a2000000-0000-4000-8000-000000000002',
  -7.36, 108.26, -7.37, 108.27, 'ACCEPTED'
);
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000003';
SET LOCAL "request.jwt.claim.role" = 'authenticated';
DO $$
DECLARE n_active integer; n_searching integer; accepted boolean;
BEGIN
  SELECT count(*) INTO n_active
  FROM public.ride_requests
  WHERE driver_id = 'a2000000-0000-4000-8000-000000000001'
    AND status IN ('ACCEPTED', 'PICKED_UP', 'IN_TRANSIT');
  SELECT count(*) INTO n_searching
  FROM public.ride_requests
  WHERE id = 'a3000000-0000-4000-8000-000000000001'
    AND status = 'SEARCHING';
  IF n_active <> 1 OR n_searching <> 0 THEN
    RAISE EXCEPTION 'Active courier visibility failed: active %, targeted searching %', n_active, n_searching;
  END IF;
  accepted := public.accept_ride(
    'a3000000-0000-4000-8000-000000000001',
    'a2000000-0000-4000-8000-000000000001'
  );
  IF accepted IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'accept_ride allowed a courier with an active ride to accept another ride';
  END IF;
END $$;
RESET ROLE;

-- Clean up fixtures; deleting a ride cascades its offer.
DELETE FROM public.ride_requests
WHERE id IN (
  'a3000000-0000-4000-8000-000000000001',
  'a3000000-0000-4000-8000-000000000002',
  'a3000000-0000-4000-8000-000000000003',
  'a3000000-0000-4000-8000-000000000004'
);
DELETE FROM public.couriers
WHERE id IN ('a2000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000002');
COMMIT;
