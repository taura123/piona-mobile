-- AlterTable
ALTER TABLE "Session" ADD COLUMN     "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- CreateIndex
CREATE INDEX "Session_checkpoint_lastSeenAt_idx" ON "Session"("checkpoint", "lastSeenAt");
