-- Samakan passengers.name dengan nama terbaca dari bcbp_parser (FK: passenger_id).
-- Dipakai: SATU baris parser TERBARU per passenger_id (scan_timestamp DESC).
-- Hanya update jika JSON punya nama teks (bukan ciphertext base64:base64).

UPDATE passengers p
SET name = LEFT(src.nm, 200)
FROM (
  SELECT DISTINCT ON (b.passenger_id)
    b.passenger_id AS pid,
    COALESCE(
      NULLIF(TRIM(b.parsed_data->>'passengerName'), ''),
      NULLIF(TRIM(b.parsed_data->>'name'), ''),
      NULLIF(TRIM(b.parsed_data->>'displayName'), ''),
      NULLIF(TRIM(b.parsed_data->>'fullName'), ''),
      NULLIF(TRIM(b.parsed_data->>'passengerFullName'), '')
    ) AS nm
  FROM bcbp_parser b
  WHERE b.parsed_data IS NOT NULL
  ORDER BY
    b.passenger_id,
    b.scan_timestamp DESC NULLS LAST,
    b.id DESC
) src
WHERE p.id = src.pid
  AND src.nm IS NOT NULL
  AND LENGTH(TRIM(src.nm)) > 0
  AND TRIM(src.nm) !~ '^[A-Za-z0-9+/=]+:[A-Za-z0-9+/=]+$';

-- Baris yang masih ciphertext di passengers tapi tidak ada nama di JSON:
UPDATE passengers
SET name = LEFT(COALESCE(NULLIF(TRIM(pnr), ''), 'Penumpang'), 200)
WHERE name ~ '^[A-Za-z0-9+/=]+:[A-Za-z0-9+/=]+$';
