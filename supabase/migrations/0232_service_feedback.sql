-- Migration 0232: Service feedback system
DO $$
BEGIN
  PERFORM 1 FROM pg_catalog.pg_class c
   JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'businesses' AND c.relkind = 'r';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Required table public.businesses does not exist';
  END IF;

  PERFORM 1 FROM pg_catalog.pg_class c
   JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'appointments' AND c.relkind = 'r';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Required table public.appointments does not exist';
  END IF;

  PERFORM 1 FROM pg_catalog.pg_class c
   JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'profiles' AND c.relkind = 'r';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Required table public.profiles does not exist';
  END IF;
END;
$$;

BEGIN;

CREATE TABLE IF NOT EXISTS service_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  appointment_id uuid UNIQUE NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
  profile_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  rating int NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reviews_business ON service_reviews(business_id);
CREATE INDEX IF NOT EXISTS idx_reviews_rating ON service_reviews(business_id, rating);
CREATE INDEX IF NOT EXISTS idx_reviews_profile ON service_reviews(profile_id);

COMMENT ON TABLE service_reviews IS
  'Valoraciones de clientes post-servicio. n8n envía solicitud 2h después del appointment.end_time.';

ALTER TABLE service_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS reviews_owner_all ON service_reviews;
CREATE POLICY reviews_owner_all ON service_reviews
  FOR ALL TO authenticated
  USING (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  );

DROP POLICY IF EXISTS reviews_lead_own ON service_reviews;
CREATE POLICY reviews_lead_own ON service_reviews
  FOR SELECT TO authenticated
  USING (
    business_id = public.get_user_business_id()
    AND EXISTS (
      SELECT 1 FROM profiles p 
      WHERE p.id = service_reviews.profile_id 
        AND p.phone_number = (auth.jwt()->>'phone_number')
    )
  );

CREATE OR REPLACE VIEW service_ratings_summary AS
SELECT 
  s.business_id,
  s.id as service_id,
  s.name as service_name,
  COUNT(r.id) as total_reviews,
  ROUND(AVG(r.rating), 2) as avg_rating,
  COUNT(*) FILTER (WHERE r.rating = 5) as five_stars,
  COUNT(*) FILTER (WHERE r.rating = 4) as four_stars,
  COUNT(*) FILTER (WHERE r.rating = 3) as three_stars,
  COUNT(*) FILTER (WHERE r.rating = 2) as two_stars,
  COUNT(*) FILTER (WHERE r.rating = 1) as one_star
FROM services s
LEFT JOIN appointments a ON a.service_id = s.id
LEFT JOIN service_reviews r ON r.appointment_id = a.id
GROUP BY s.business_id, s.id, s.name;

GRANT SELECT ON service_ratings_summary TO authenticated;

COMMIT;
