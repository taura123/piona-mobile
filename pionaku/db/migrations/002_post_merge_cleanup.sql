-- Post-merge hardening + cleanup.
-- Run only after you've verified the application reads/writes legacy tables.

-- 1) Optional: add a dedupe constraint for parser rows to prevent duplicates.
--    Note: CREATE INDEX CONCURRENTLY cannot run inside a transaction.
--    If you prefer transactional, drop CONCURRENTLY and accept a stronger lock.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'ux_bcbp_parser_dedupe'
  ) THEN
    EXECUTE 'CREATE UNIQUE INDEX ux_bcbp_parser_dedupe ON public.bcbp_parser (raw_barcode, scan_timestamp, scan_point)';
  END IF;
END$$;

-- 2) Drop Prisma PascalCase tables to remove duplication.
--    If you want a safer approach, rename them instead of dropping.
DROP TABLE IF EXISTS "ManualEntryCapture";
DROP TABLE IF EXISTS "PassengerScan";
DROP TABLE IF EXISTS "ScanPoint";
DROP TABLE IF EXISTS "Session";
DROP TABLE IF EXISTS "User";

