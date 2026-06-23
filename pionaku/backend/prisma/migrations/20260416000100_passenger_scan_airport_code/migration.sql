-- Add airportCode to PassengerScan for per-airport filtering.
ALTER TABLE "PassengerScan"
ADD COLUMN "airportCode" TEXT NOT NULL DEFAULT '';

CREATE INDEX "PassengerScan_airportCode_scannedAt_idx"
ON "PassengerScan"("airportCode", "scannedAt");

