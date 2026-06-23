-- Add scan source
ALTER TABLE "PassengerScan" ADD COLUMN "source" TEXT NOT NULL DEFAULT 'scan';

-- Drop previous full-table unique (dedupe) index
DROP INDEX IF EXISTS "PassengerScan_barcodeValue_scanPoint_scanDay_key";

-- Recreate dedupe as partial unique index for source='scan' only
CREATE UNIQUE INDEX "PassengerScan_barcodeValue_scanPoint_scanDay_scanOnly_key"
  ON "PassengerScan"("barcodeValue", "scanPoint", "scanDay")
  WHERE "source" = 'scan';

