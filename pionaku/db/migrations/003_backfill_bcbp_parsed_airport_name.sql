-- Optional: backfill bcbp_parser.parsed_data for older rows so airport filters
-- and display names work without re-scanning.
-- Run on a backup / maintenance window.

BEGIN;

UPDATE bcbp_parser b
SET parsed_data = COALESCE(b.parsed_data::jsonb, '{}'::jsonb)
  || jsonb_build_object(
    'airportCode',
    NULLIF(UPPER(TRIM(p.origin)), 'UNK'),
    'passengerName',
    CASE
      WHEN LENGTH(TRIM(p.name)) >= 24
        AND TRIM(p.name) ~ '^[A-Za-z0-9+/=_-]+$'
        THEN COALESCE(NULLIF(TRIM(p.pnr), ''), 'Penumpang')
      ELSE TRIM(p.name)
    END
  )
FROM passengers p
WHERE b.passenger_id = p.id
  AND (
    COALESCE(b.parsed_data::text, '') IN ('{}', 'null', '')
    OR NOT (b.parsed_data ? 'airportCode')
  );

COMMIT;
