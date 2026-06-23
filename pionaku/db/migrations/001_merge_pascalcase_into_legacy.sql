-- Merge data from Prisma PascalCase tables into legacy snake_case tables.
-- Assumptions:
-- - Legacy tables already exist (users, scan_points, passengers, bcbp_parser, log_login, photo_uploads, ...).
-- - Prisma PascalCase tables still exist ("User", "ScanPoint", "PassengerScan", "ManualEntryCapture", "Session").
-- - This script is idempotent-ish: it uses ON CONFLICT / WHERE NOT EXISTS for common duplicates.
--
-- IMPORTANT: Run on a backup / during maintenance window.

BEGIN;

-- 1) Ensure a non-login system user exists for migrations / unknown scanner.
INSERT INTO users (username, password, role, status)
SELECT 'system_migrator', '!', 'IT'::user_role, 'Inactive'::user_status
WHERE NOT EXISTS (SELECT 1 FROM users WHERE username = 'system_migrator');

-- 2) Merge Prisma "User" -> legacy users
INSERT INTO users (username, password, role, status, created_at)
SELECT
  u."username",
  COALESCE(NULLIF(u."passwordHash", ''), '!') AS password,
  CASE upper(COALESCE(NULLIF(u."role", ''), 'View'))
    WHEN 'ADMIN' THEN 'Admin'::user_role
    WHEN 'IT' THEN 'IT'::user_role
    WHEN 'SCAN' THEN 'Scan'::user_role
    WHEN 'VIEW' THEN 'View'::user_role
    ELSE 'View'::user_role
  END AS role,
  CASE lower(COALESCE(NULLIF(u."status", ''), 'active'))
    WHEN 'inactive' THEN 'Inactive'::user_status
    ELSE 'Active'::user_status
  END AS status,
  COALESCE(u."createdAt", now()) AS created_at
FROM "User" u
ON CONFLICT (username) DO UPDATE
SET
  password = EXCLUDED.password,
  role = EXCLUDED.role,
  status = EXCLUDED.status;

-- 3) Merge Prisma "ScanPoint" -> legacy scan_points
INSERT INTO scan_points (name, status, created_at)
SELECT
  sp."name",
  CASE sp."status"
    WHEN 'inactive' THEN 'Inactive'::scan_point_status
    ELSE 'Active'::scan_point_status
  END AS status,
  COALESCE(sp."createdAt", now()) AS created_at
FROM "ScanPoint" sp
ON CONFLICT (name) DO NOTHING;

-- 4) Merge Prisma "PassengerScan" -> legacy passengers + bcbp_parser
WITH src AS (
  SELECT
    ps.*
  FROM "PassengerScan" ps
),
normalized AS (
  SELECT
    COALESCE(NULLIF(trim(s."pnrOrCode"), ''), 'UNKNOWN')::varchar(10) AS pnr,
    COALESCE(NULLIF(trim(s."passengerName"), ''), 'UNKNOWN')::varchar(200) AS name,
    COALESCE(NULLIF(trim(s."flight"), ''), 'UNKNOWN')::varchar(15) AS flight_number,
    COALESCE(NULLIF(trim(s."origin"), ''), 'UNK')::varchar(10) AS origin,
    COALESCE(NULLIF(trim(s."destination"), ''), 'UNK')::varchar(10) AS destination,
    COALESCE(NULLIF(trim(s."seat"), ''), 'UNK')::varchar(10) AS seat_number,
    NULLIF(trim(s."barcodeValue"), '')::varchar(255) AS raw_barcode,
    COALESCE(s."scannedAt", now()) AS scanned_at,
    COALESCE(NULLIF(trim(s."scanPoint"), ''), 'UNKNOWN')::varchar(100) AS scan_point,
    CASE
      WHEN s."boardingDate" ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN (s."boardingDate")::date
      ELSE (COALESCE(s."scannedAt", now()))::date
    END AS flight_date,
    CASE upper(COALESCE(NULLIF(trim(s."passengerType"), ''), 'ADULT'))
      WHEN 'CHILD' THEN 'Child'::passenger_type
      WHEN 'INFANT' THEN 'Infant'::passenger_type
      ELSE 'Adult'::passenger_type
    END AS type,
    CASE upper(COALESCE(NULLIF(trim(s."category"), ''), 'NORMAL'))
      WHEN 'TRANSIT' THEN 'Transit'::passenger_category
      ELSE 'Normal'::passenger_category
    END AS category,
    CASE lower(COALESCE(NULLIF(trim(s."status"), ''), 'complete'))
      WHEN 'failed' THEN 'failed'::parsing_status
      WHEN 'partial' THEN 'partial'::parsing_status
      ELSE 'success'::parsing_status
    END AS parsing_status,
    s."createdAt" AS created_at
  FROM src s
),
ins_passengers AS (
  INSERT INTO passengers (
    pnr,
    name,
    flight_number,
    origin,
    destination,
    seat_number,
    flight_date,
    type,
    category,
    scanned_at,
    scan_point
  )
  SELECT DISTINCT
    n.pnr,
    n.name,
    n.flight_number,
    n.origin,
    n.destination,
    n.seat_number,
    n.flight_date,
    n.type,
    n.category,
    n.scanned_at,
    n.scan_point
  FROM normalized n
  ON CONFLICT ON CONSTRAINT unique_passenger DO UPDATE
  SET
    scanned_at = EXCLUDED.scanned_at,
    scan_point = EXCLUDED.scan_point,
    name = EXCLUDED.name,
    origin = EXCLUDED.origin,
    destination = EXCLUDED.destination
  RETURNING id, type, seat_number, flight_date, flight_number
)
INSERT INTO bcbp_parser (
  raw_barcode,
  parsed_data,
  parsing_status,
  error_message,
  scan_timestamp,
  scan_point,
  scanner_user_id,
  passenger_id,
  created_at,
  updated_at
)
SELECT
  COALESCE(NULLIF(n.raw_barcode, ''), 'UNKNOWN'),
  '{}'::jsonb AS parsed_data,
  n.parsing_status,
  NULL::text AS error_message,
  n.scanned_at AS scan_timestamp,
  n.scan_point,
  (SELECT id FROM users WHERE username = 'system_migrator') AS scanner_user_id,
  p.id AS passenger_id,
  COALESCE(n.created_at, now()) AS created_at,
  now() AS updated_at
FROM normalized n
JOIN passengers p
  ON p.type = n.type
 AND p.seat_number = n.seat_number
 AND p.flight_date = n.flight_date
 AND p.flight_number = n.flight_number
WHERE NOT EXISTS (
  SELECT 1
  FROM bcbp_parser bp
  WHERE bp.raw_barcode = COALESCE(NULLIF(n.raw_barcode, ''), 'UNKNOWN')
    AND bp.scan_timestamp = n.scanned_at
    AND bp.scan_point = n.scan_point
);

COMMIT;

