-- Sinkronkan passengers.name dari bcbp_parser.parsed_data
-- (FK: bcbp_parser.passenger_id -> passengers.id).
-- Per penumpang: baris parser TERBARU (scan_timestamp DESC, id DESC).
--
-- Jika ERROR 25P02:
--   1) Buka file 005a_rollback_stuck_postgres.sql dan jalankan ISI-NYA saja (satu perintah).
--   2) Atau: klik kanan koneksi DB -> Disconnect, lalu Connect lagi.
--   3) JANGAN pilih teks COMMIT/BEGIN dari skrip lama di editor yang sama.
--   4) Baru jalankan UPDATE di bawah (sorot hanya blok UPDATE, atau semua tanpa COMMIT).

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
  AND LENGTH(TRIM(src.nm)) > 0;
