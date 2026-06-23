-- AlterTable
ALTER TABLE "PassengerScan" ADD COLUMN "scanDay" TEXT;

-- Backfill scanDay as UTC day from scannedAt (YYYY-MM-DD)
UPDATE "PassengerScan"
SET "scanDay" = to_char("scannedAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD')
WHERE "scanDay" IS NULL;

-- Make scanDay required
ALTER TABLE "PassengerScan" ALTER COLUMN "scanDay" SET NOT NULL;

-- Indexes and dedupe constraint
CREATE INDEX "PassengerScan_scanDay_scanPoint_idx" ON "PassengerScan"("scanDay", "scanPoint");
CREATE UNIQUE INDEX "PassengerScan_barcodeValue_scanPoint_scanDay_key"
  ON "PassengerScan"("barcodeValue", "scanPoint", "scanDay");

