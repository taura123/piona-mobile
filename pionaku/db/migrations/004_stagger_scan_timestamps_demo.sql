-- Optional demo: vary scan_timestamp per row (same calendar day, different clock).
--
-- If DBeaver shows: ERROR 25P02 "current transaction is aborted":
--   1) Run only:  ROLLBACK;
--   2) Fix the date in WHERE below, then run this whole file again.
--
-- Common mistake: in UPDATE ... FROM ranked r  you must use r.rn, not bare rn.

BEGIN;

WITH ranked AS (
  SELECT
    b.id,
    ROW_NUMBER() OVER (ORDER BY b.id) AS rn
  FROM bcbp_parser b
  INNER JOIN passengers p ON p.id = b.passenger_id
  WHERE p.flight_date = DATE '2026-04-17'
)
UPDATE bcbp_parser b
SET
  scan_timestamp =
    date_trunc('day', b.scan_timestamp)
    + make_interval(
      hours => ((r.rn - 1) % 12),
      mins => ((r.rn * 7) % 55),
      secs => ((r.rn * 3) % 59)
    ),
  updated_at = now()
FROM ranked r
WHERE b.id = r.id;

-- Only passengers tied to rows on that flight_date (not whole table).
UPDATE passengers p
SET scanned_at = x.mx
FROM (
  SELECT b.passenger_id AS pid, MAX(b.scan_timestamp) AS mx
  FROM bcbp_parser b
  INNER JOIN passengers p2 ON p2.id = b.passenger_id
  WHERE p2.flight_date = DATE '2026-04-17'
  GROUP BY b.passenger_id
) x
WHERE p.id = x.pid;

COMMIT;
