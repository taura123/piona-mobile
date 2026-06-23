/*
  Warnings:

  - You are about to drop the `ManualEntryCapture` table. If the table is not empty, all the data it contains will be lost.
  - You are about to drop the `PassengerScan` table. If the table is not empty, all the data it contains will be lost.
  - You are about to drop the `ScanPoint` table. If the table is not empty, all the data it contains will be lost.
  - You are about to drop the `Session` table. If the table is not empty, all the data it contains will be lost.
  - You are about to drop the `User` table. If the table is not empty, all the data it contains will be lost.

*/
-- CreateEnum
CREATE TYPE "parsing_status" AS ENUM ('success', 'failed', 'partial');

-- CreateEnum
CREATE TYPE "passenger_type" AS ENUM ('Adult', 'Child', 'Infant');

-- CreateEnum
CREATE TYPE "passenger_category" AS ENUM ('Normal', 'Transit');

-- CreateEnum
CREATE TYPE "scan_point_status" AS ENUM ('Active', 'Inactive');

-- CreateEnum
CREATE TYPE "user_role" AS ENUM ('Admin', 'Scan', 'View', 'IT');

-- CreateEnum
CREATE TYPE "user_status" AS ENUM ('Active', 'Inactive');

-- CreateEnum
CREATE TYPE "login_status" AS ENUM ('success', 'failed', 'timeout', 'forced_logout');

-- CreateEnum
CREATE TYPE "login_method" AS ENUM ('password', 'session', 'token', 'sso');

-- CreateEnum
CREATE TYPE "photo_source_type" AS ENUM ('scan-transit', 'data-entry');

-- DropForeignKey
ALTER TABLE "Session" DROP CONSTRAINT "Session_userId_fkey";

-- DropTable
DROP TABLE "ManualEntryCapture";

-- DropTable
DROP TABLE "PassengerScan";

-- DropTable
DROP TABLE "ScanPoint";

-- DropTable
DROP TABLE "Session";

-- DropTable
DROP TABLE "User";

-- DropEnum
DROP TYPE "ManualCaptureScanSource";

-- DropEnum
DROP TYPE "ManualEntryWorkflowStatus";

-- DropEnum
DROP TYPE "ParseStatus";

-- DropEnum
DROP TYPE "ScanPointStatus";

-- CreateTable
CREATE TABLE "users" (
    "id" SERIAL NOT NULL,
    "username" VARCHAR(50) NOT NULL,
    "password" VARCHAR(255) NOT NULL,
    "role" "user_role" NOT NULL,
    "status" "user_status" NOT NULL DEFAULT 'Active',
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "scan_points" (
    "id" SERIAL NOT NULL,
    "name" VARCHAR(100) NOT NULL,
    "status" "scan_point_status" NOT NULL DEFAULT 'Active',
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "scan_points_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "passengers" (
    "id" SERIAL NOT NULL,
    "pnr" VARCHAR(10) NOT NULL,
    "name" VARCHAR(200) NOT NULL,
    "flight_number" VARCHAR(15) NOT NULL,
    "origin" VARCHAR(10) NOT NULL,
    "destination" VARCHAR(10) NOT NULL,
    "seat_number" VARCHAR(10) NOT NULL,
    "sequence_number" VARCHAR(10),
    "flight_date" DATE,
    "type" "passenger_type" NOT NULL,
    "category" "passenger_category" NOT NULL,
    "scanned_at" TIMESTAMP(6) NOT NULL,
    "scan_point" VARCHAR(100) NOT NULL,
    "sent" VARCHAR(1) DEFAULT '0',
    "send_date" TIMESTAMP(6),
    "deleted_at" TIMESTAMP(6),

    CONSTRAINT "passengers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "bcbp_parser" (
    "id" SERIAL NOT NULL,
    "raw_barcode" VARCHAR(255) NOT NULL,
    "parsed_data" JSONB NOT NULL,
    "parsing_status" "parsing_status" NOT NULL DEFAULT 'success',
    "error_message" TEXT,
    "scan_timestamp" TIMESTAMP(6) NOT NULL,
    "scan_point" VARCHAR(100) NOT NULL,
    "scanner_user_id" INTEGER NOT NULL,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "passenger_id" INTEGER NOT NULL,

    CONSTRAINT "bcbp_parser_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "log_login" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "username" VARCHAR(50) NOT NULL,
    "login_timestamp" TIMESTAMP(6) NOT NULL,
    "logout_timestamp" TIMESTAMP(6),
    "session_duration_seconds" INTEGER,
    "login_status" "login_status" NOT NULL DEFAULT 'success',
    "ip_address" VARCHAR(45),
    "user_agent" TEXT,
    "login_method" "login_method" NOT NULL DEFAULT 'password',
    "failure_reason" VARCHAR(255),
    "scan_point" VARCHAR(100),
    "airport_branch" VARCHAR(10),
    "device_info" JSONB,
    "security_events" JSONB,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "log_login_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "photo_uploads" (
    "id" SERIAL NOT NULL,
    "passenger_id" INTEGER,
    "filename" VARCHAR(255) NOT NULL,
    "file_size" INTEGER NOT NULL,
    "upload_timestamp" TIMESTAMP(6) NOT NULL,
    "session_data" JSONB,
    "source_type" "photo_source_type" NOT NULL DEFAULT 'data-entry',
    "manual_entry_saved" BOOLEAN DEFAULT false,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMP(6),
    "ai_generated" BOOLEAN DEFAULT false,
    "ai_generated_data" JSONB,
    "ai_generated_at" TIMESTAMP(6),

    CONSTRAINT "photo_uploads_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_username_key" ON "users"("username");

-- CreateIndex
CREATE UNIQUE INDEX "scan_points_name_key" ON "scan_points"("name");

-- CreateIndex
CREATE INDEX "idx_passengers_flight_date" ON "passengers"("flight_date");

-- CreateIndex
CREATE INDEX "idx_passengers_scan_point" ON "passengers"("scan_point");

-- CreateIndex
CREATE INDEX "idx_passengers_scanned_at" ON "passengers"("scanned_at" DESC);

-- CreateIndex
CREATE INDEX "idx_passengers_deleted_at" ON "passengers"("deleted_at");

-- CreateIndex
CREATE UNIQUE INDEX "unique_passenger" ON "passengers"("type", "seat_number", "flight_date", "flight_number");

-- CreateIndex
CREATE INDEX "idx_bcbp_parser_scan_point" ON "bcbp_parser"("scan_point");

-- CreateIndex
CREATE INDEX "idx_bcbp_parser_scanner_user" ON "bcbp_parser"("scanner_user_id");

-- CreateIndex
CREATE INDEX "idx_bcbp_parser_raw" ON "bcbp_parser"("raw_barcode");

-- CreateIndex
CREATE INDEX "idx_log_login_user_id" ON "log_login"("user_id");

-- CreateIndex
CREATE INDEX "idx_log_login_username" ON "log_login"("username");

-- CreateIndex
CREATE INDEX "idx_log_login_timestamp" ON "log_login"("login_timestamp");

-- CreateIndex
CREATE INDEX "idx_log_login_status" ON "log_login"("login_status");

-- CreateIndex
CREATE INDEX "idx_log_login_ip_address" ON "log_login"("ip_address");

-- CreateIndex
CREATE INDEX "idx_log_login_scan_point" ON "log_login"("scan_point");

-- CreateIndex
CREATE INDEX "idx_log_login_airport_branch" ON "log_login"("airport_branch");

-- CreateIndex
CREATE INDEX "idx_log_login_created_at" ON "log_login"("created_at");

-- CreateIndex
CREATE INDEX "idx_log_login_user_date" ON "log_login"("user_id", "login_timestamp");

-- CreateIndex
CREATE INDEX "idx_log_login_status_date" ON "log_login"("login_status", "login_timestamp");

-- CreateIndex
CREATE INDEX "idx_log_login_scan_point_date" ON "log_login"("scan_point", "login_timestamp");

-- CreateIndex
CREATE INDEX "idx_photo_uploads_timestamp" ON "photo_uploads"("upload_timestamp");

-- CreateIndex
CREATE INDEX "idx_photo_uploads_filename" ON "photo_uploads"("filename");

-- CreateIndex
CREATE INDEX "idx_photo_uploads_passenger_id" ON "photo_uploads"("passenger_id");

-- CreateIndex
CREATE INDEX "idx_photo_uploads_deleted_at" ON "photo_uploads"("deleted_at");

-- CreateIndex
CREATE INDEX "idx_photo_uploads_ai_generated" ON "photo_uploads"("ai_generated");

-- AddForeignKey
ALTER TABLE "bcbp_parser" ADD CONSTRAINT "bcbp_parser_passenger_id_fkey" FOREIGN KEY ("passenger_id") REFERENCES "passengers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bcbp_parser" ADD CONSTRAINT "bcbp_parser_scanner_user_id_fkey" FOREIGN KEY ("scanner_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "log_login" ADD CONSTRAINT "log_login_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "photo_uploads" ADD CONSTRAINT "photo_uploads_passenger_id_fkey" FOREIGN KEY ("passenger_id") REFERENCES "passengers"("id") ON DELETE SET NULL ON UPDATE CASCADE;
