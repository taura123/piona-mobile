-- CreateEnum
CREATE TYPE "ScanPointStatus" AS ENUM ('active', 'inactive');

-- CreateEnum
CREATE TYPE "ManualCaptureScanSource" AS ENUM ('normal', 'transit');

-- CreateEnum
CREATE TYPE "ManualEntryWorkflowStatus" AS ENUM ('pending', 'aiGenerated', 'completed', 'trash');

-- CreateEnum
CREATE TYPE "ParseStatus" AS ENUM ('complete', 'partial', 'failed');

-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "username" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "role" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Session" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "airportCode" TEXT NOT NULL,
    "checkpoint" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revokedAt" TIMESTAMP(3),

    CONSTRAINT "Session_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ScanPoint" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "status" "ScanPointStatus" NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ScanPoint_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PassengerScan" (
    "id" TEXT NOT NULL,
    "passengerName" TEXT NOT NULL,
    "boardingDate" TEXT NOT NULL,
    "seat" TEXT NOT NULL,
    "flight" TEXT NOT NULL,
    "origin" TEXT NOT NULL,
    "destination" TEXT NOT NULL,
    "passengerType" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "pnrOrCode" TEXT NOT NULL,
    "scanPoint" TEXT NOT NULL,
    "scannedAt" TIMESTAMP(3) NOT NULL,
    "status" "ParseStatus" NOT NULL,
    "barcodeValue" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PassengerScan_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ManualEntryCapture" (
    "id" TEXT NOT NULL,
    "relativePath" TEXT NOT NULL,
    "displayFileName" TEXT NOT NULL,
    "sizeBytes" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL,
    "source" "ManualCaptureScanSource" NOT NULL,
    "status" "ManualEntryWorkflowStatus" NOT NULL,
    "userDisplay" TEXT NOT NULL,
    "scanPoint" TEXT NOT NULL,
    "airportCode" TEXT NOT NULL,
    "parsed" JSONB,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ManualEntryCapture_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_username_key" ON "User"("username");

-- CreateIndex
CREATE INDEX "Session_userId_createdAt_idx" ON "Session"("userId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "ScanPoint_name_key" ON "ScanPoint"("name");

-- CreateIndex
CREATE INDEX "PassengerScan_scannedAt_idx" ON "PassengerScan"("scannedAt");

-- CreateIndex
CREATE INDEX "PassengerScan_scanPoint_scannedAt_idx" ON "PassengerScan"("scanPoint", "scannedAt");

-- CreateIndex
CREATE INDEX "ManualEntryCapture_createdAt_idx" ON "ManualEntryCapture"("createdAt");

-- CreateIndex
CREATE INDEX "ManualEntryCapture_status_createdAt_idx" ON "ManualEntryCapture"("status", "createdAt");

-- AddForeignKey
ALTER TABLE "Session" ADD CONSTRAINT "Session_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
