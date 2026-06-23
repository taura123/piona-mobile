import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

const __filename = url.fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const MYSQL_DUMP = path.join(__dirname, 'scan_boarding_pass_new_ho.sql');
const PG_SCHEMA = path.join(__dirname, 'pg_schema.sql');
const PG_DATA = path.join(__dirname, 'pg_data.sql');

const JSON_COLUMNS = new Set([
  'bcbp_parser.parsed_data',
  'log_login.device_info',
  'log_login.security_events',
  'photo_uploads.session_data',
  'photo_uploads.ai_generated_data',
]);

const tableColumns = {
  users: ['id', 'username', 'password', 'role', 'status', 'created_at'],
  scan_points: ['id', 'name', 'status', 'created_at'],
  system_settings: [
    'id',
    'setting_key',
    'setting_value',
    'description',
    'updated_at',
    'updated_by',
  ],
  passengers: [
    'id',
    'pnr',
    'name',
    'flight_number',
    'origin',
    'destination',
    'seat_number',
    'sequence_number',
    'flight_date',
    'type',
    'category',
    'scanned_at',
    'scan_point',
    'sent',
    'send_date',
    'deleted_at',
  ],
  bcbp_parser: [
    'id',
    'raw_barcode',
    'parsed_data',
    'parsing_status',
    'error_message',
    'scan_timestamp',
    'scan_point',
    'scanner_user_id',
    'created_at',
    'updated_at',
    'passenger_id',
  ],
  cost_ai_api: [
    'id',
    'transaction_type',
    'batch_id',
    'photo_upload_id',
    'input_tokens',
    'output_tokens',
    'total_tokens',
    'cost_usd',
    'cost_idr',
    'status',
    'error_message',
    'total_items',
    'processed_items',
    'success_count',
    'error_count',
    'created_at',
    'updated_at',
  ],
  flight_schedule: [
    'id',
    'scheduled',
    'estimated',
    'actual',
    'longname',
    'terminal_id',
    'iata_airline_code',
    'flight_no',
    'description',
    'arr_dep',
    'dom_int',
    'desk_no',
    'gate_code',
    'reclaim_no',
    'branch_code',
    'iata_airline_desc',
    'station1',
    'insert_date',
    'boarding',
  ],
  flight_sync_log: [
    'id',
    'airport_code',
    'sync_date',
    'sync_time',
    'status',
    'message',
    'created_at',
  ],
  flights: ['id', 'flight_number', 'origin', 'destination', 'created_at'],
  log_login: [
    'id',
    'user_id',
    'username',
    'login_timestamp',
    'logout_timestamp',
    'session_duration_seconds',
    'login_status',
    'ip_address',
    'user_agent',
    'login_method',
    'failure_reason',
    'scan_point',
    'airport_branch',
    'device_info',
    'security_events',
    'created_at',
    'updated_at',
  ],
  photo_uploads: [
    'id',
    'passenger_id',
    'filename',
    'file_size',
    'upload_timestamp',
    'session_data',
    'source_type',
    'manual_entry_saved',
    'created_at',
    'updated_at',
    'deleted_at',
    'ai_generated',
    'ai_generated_data',
    'ai_generated_at',
  ],
  wib_debug_test: ['id', 'test_time', 'created_at'],
};

function unescapeMysqlSingleQuoted(inner) {
  // MySQL dump uses backslash escapes.
  return inner
    .replaceAll('\\\\', '\\')
    .replaceAll("\\'", "'")
    .replaceAll('\\"', '"')
    .replaceAll('\\n', '\n')
    .replaceAll('\\r', '\r')
    .replaceAll('\\t', '\t');
}

function pgQuote(text) {
  return `'${text.replaceAll("'", "''")}'`;
}

function splitMysqlValues(valuesSql) {
  const out = [];
  let i = 0;
  const n = valuesSql.length;
  let cur = '';
  let inStr = false;

  while (i < n) {
    const ch = valuesSql[i];
    if (inStr) {
      cur += ch;
      if (ch === '\\' && i + 1 < n) {
        i += 1;
        cur += valuesSql[i];
      } else if (ch === "'") {
        inStr = false;
      }
      i += 1;
      continue;
    }

    if (ch === "'") {
      inStr = true;
      cur += ch;
      i += 1;
      continue;
    }

    if (ch === ',') {
      out.push(cur.trim());
      cur = '';
      i += 1;
      continue;
    }

    cur += ch;
    i += 1;
  }

  const last = cur.trim();
  if (last.length > 0) out.push(last);
  return out;
}

function parseMysqlInsertLine(line) {
  const m = line.match(/^INSERT INTO `([^`]+)` VALUES \((.*)\);$/);
  if (!m) return null;
  const table = m[1];
  const valsSql = m[2];
  const values = splitMysqlValues(valsSql);
  return { table, values };
}

function normalizeValueForPg(table, colName, rawToken) {
  const tok = rawToken.trim();
  if (tok.toUpperCase() === 'NULL') return 'NULL';

  // MySQL uses 0/1 for booleans.
  if (
    table === 'photo_uploads' &&
    (colName === 'manual_entry_saved' || colName === 'ai_generated')
  ) {
    if (tok === '0') return 'false';
    if (tok === '1') return 'true';
  }

  if (tok.startsWith("'") && tok.endsWith("'") && tok.length >= 2) {
    const inner = tok.slice(1, -1);
    const unescaped = unescapeMysqlSingleQuoted(inner);

    if (JSON_COLUMNS.has(`${table}.${colName}`)) {
      return `${pgQuote(unescaped.trim())}::jsonb`;
    }
    return pgQuote(unescaped);
  }

  return tok;
}

function pgSchemaSql() {
  return `-- Generated from MySQL dump for PostgreSQL
-- Source: scan_boarding_pass_new_ho.sql

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'parsing_status') THEN
    CREATE TYPE parsing_status AS ENUM ('success','failed','partial');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'transaction_type') THEN
    CREATE TYPE transaction_type AS ENUM ('single','batch');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'cost_status') THEN
    CREATE TYPE cost_status AS ENUM ('success','error','cancelled');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'login_status') THEN
    CREATE TYPE login_status AS ENUM ('success','failed','timeout','forced_logout');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'login_method') THEN
    CREATE TYPE login_method AS ENUM ('password','session','token','sso');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'passenger_type') THEN
    CREATE TYPE passenger_type AS ENUM ('Adult','Child','Infant');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'passenger_category') THEN
    CREATE TYPE passenger_category AS ENUM ('Normal','Transit');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'scan_point_status') THEN
    CREATE TYPE scan_point_status AS ENUM ('Active','Inactive');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    CREATE TYPE user_role AS ENUM ('Admin','Scan','View','IT');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_status') THEN
    CREATE TYPE user_status AS ENUM ('Active','Inactive');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'photo_source_type') THEN
    CREATE TYPE photo_source_type AS ENUM ('scan-transit','data-entry');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sync_status') THEN
    CREATE TYPE sync_status AS ENUM ('success','error');
  END IF;
END$$;

DROP VIEW IF EXISTS bcbp_parser_daily_summary;
DROP VIEW IF EXISTS bcbp_parser_stats;
DROP VIEW IF EXISTS log_login_daily_summary;
DROP VIEW IF EXISTS log_login_security_monitoring;
DROP VIEW IF EXISTS log_login_stats;
DROP VIEW IF EXISTS log_login_user_sessions;

DROP TABLE IF EXISTS bcbp_parser CASCADE;
DROP TABLE IF EXISTS cost_ai_api CASCADE;
DROP TABLE IF EXISTS flight_schedule CASCADE;
DROP TABLE IF EXISTS flight_sync_log CASCADE;
DROP TABLE IF EXISTS flights CASCADE;
DROP TABLE IF EXISTS log_login CASCADE;
DROP TABLE IF EXISTS photo_uploads CASCADE;
DROP TABLE IF EXISTS passengers CASCADE;
DROP TABLE IF EXISTS scan_points CASCADE;
DROP TABLE IF EXISTS system_settings CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS wib_debug_test CASCADE;

CREATE TABLE users (
  id integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  username varchar(50) NOT NULL UNIQUE,
  password varchar(255) NOT NULL,
  role user_role NOT NULL,
  status user_status NOT NULL DEFAULT 'Active',
  created_at timestamptz DEFAULT now()
);

CREATE TABLE scan_points (
  id integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  name varchar(100) NOT NULL UNIQUE,
  status scan_point_status NOT NULL DEFAULT 'Active',
  created_at timestamptz DEFAULT now()
);

CREATE TABLE system_settings (
  id integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  setting_key varchar(100) NOT NULL UNIQUE,
  setting_value text NOT NULL,
  description varchar(255),
  updated_at timestamptz DEFAULT now(),
  updated_by varchar(50)
);

CREATE TABLE passengers (
  id integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  pnr varchar(10) NOT NULL,
  name varchar(200) NOT NULL,
  flight_number varchar(15) NOT NULL,
  origin varchar(10) NOT NULL,
  destination varchar(10) NOT NULL,
  seat_number varchar(10) NOT NULL,
  sequence_number varchar(10),
  flight_date date,
  type passenger_type NOT NULL,
  category passenger_category NOT NULL,
  scanned_at timestamp NOT NULL,
  scan_point varchar(100) NOT NULL,
  sent varchar(1) DEFAULT '0',
  send_date timestamp,
  deleted_at timestamp,
  CONSTRAINT unique_passenger UNIQUE (type, seat_number, flight_date, flight_number)
);

CREATE INDEX idx_passengers_flight_date ON passengers (flight_date);
CREATE INDEX idx_passengers_scan_point ON passengers (scan_point);
CREATE INDEX idx_passengers_scanned_at ON passengers (scanned_at DESC);
CREATE INDEX idx_passengers_deleted_at ON passengers (deleted_at);

CREATE TABLE bcbp_parser (
  id integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  raw_barcode varchar(255) NOT NULL,
  parsed_data jsonb NOT NULL,
  parsing_status parsing_status NOT NULL DEFAULT 'success',
  error_message text,
  scan_timestamp timestamp NOT NULL,
  scan_point varchar(100) NOT NULL,
  scanner_user_id integer NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  passenger_id integer NOT NULL,
  CONSTRAINT fk_bcbp_passenger FOREIGN KEY (passenger_id) REFERENCES passengers(id) ON DELETE RESTRICT,
  CONSTRAINT fk_bcbp_user FOREIGN KEY (scanner_user_id) REFERENCES users(id) ON DELETE RESTRICT
);

CREATE INDEX idx_bcbp_parser_scan_point ON bcbp_parser (scan_point);
CREATE INDEX idx_bcbp_parser_scanner_user ON bcbp_parser (scanner_user_id);
CREATE INDEX idx_bcbp_parser_raw ON bcbp_parser (raw_barcode);

CREATE TABLE flights (
  id integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  flight_number varchar(15) NOT NULL UNIQUE,
  origin varchar(10) NOT NULL,
  destination varchar(10) NOT NULL,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE flight_schedule (
  id varchar(50) PRIMARY KEY,
  scheduled timestamp,
  estimated timestamp,
  actual timestamp,
  longname varchar(100),
  terminal_id varchar(10),
  iata_airline_code varchar(10),
  flight_no varchar(20),
  description varchar(50),
  arr_dep char(1),
  dom_int char(1),
  desk_no varchar(20),
  gate_code varchar(20),
  reclaim_no varchar(20),
  branch_code varchar(10),
  iata_airline_desc varchar(100),
  station1 varchar(10),
  insert_date timestamp DEFAULT now(),
  boarding time
);

CREATE INDEX idx_flight_schedule_lookup ON flight_schedule (flight_no, scheduled);

CREATE TABLE flight_sync_log (
  id integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  airport_code varchar(10),
  sync_date date,
  sync_time timestamp,
  status sync_status NOT NULL,
  message text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE log_login (
  id integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  user_id integer NOT NULL,
  username varchar(50) NOT NULL,
  login_timestamp timestamp NOT NULL,
  logout_timestamp timestamp,
  session_duration_seconds integer,
  login_status login_status NOT NULL DEFAULT 'success',
  ip_address varchar(45),
  user_agent text,
  login_method login_method NOT NULL DEFAULT 'password',
  failure_reason varchar(255),
  scan_point varchar(100),
  airport_branch varchar(10),
  device_info jsonb,
  security_events jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT fk_log_login_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT
);

CREATE INDEX idx_log_login_user_id ON log_login (user_id);
CREATE INDEX idx_log_login_username ON log_login (username);
CREATE INDEX idx_log_login_timestamp ON log_login (login_timestamp);
CREATE INDEX idx_log_login_status ON log_login (login_status);
CREATE INDEX idx_log_login_ip_address ON log_login (ip_address);
CREATE INDEX idx_log_login_scan_point ON log_login (scan_point);
CREATE INDEX idx_log_login_airport_branch ON log_login (airport_branch);
CREATE INDEX idx_log_login_created_at ON log_login (created_at);
CREATE INDEX idx_log_login_user_date ON log_login (user_id, login_timestamp);
CREATE INDEX idx_log_login_status_date ON log_login (login_status, login_timestamp);
CREATE INDEX idx_log_login_scan_point_date ON log_login (scan_point, login_timestamp);

CREATE TABLE photo_uploads (
  id integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  passenger_id integer,
  filename varchar(255) NOT NULL,
  file_size integer NOT NULL,
  upload_timestamp timestamp NOT NULL,
  session_data jsonb,
  source_type photo_source_type NOT NULL DEFAULT 'data-entry',
  manual_entry_saved boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamp,
  ai_generated boolean DEFAULT false,
  ai_generated_data jsonb,
  ai_generated_at timestamp,
  CONSTRAINT fk_photo_uploads_passenger FOREIGN KEY (passenger_id) REFERENCES passengers(id) ON DELETE SET NULL
);

CREATE INDEX idx_photo_uploads_timestamp ON photo_uploads (upload_timestamp);
CREATE INDEX idx_photo_uploads_filename ON photo_uploads (filename);
CREATE INDEX idx_photo_uploads_passenger_id ON photo_uploads (passenger_id);
CREATE INDEX idx_photo_uploads_deleted_at ON photo_uploads (deleted_at);
CREATE INDEX idx_photo_uploads_ai_generated ON photo_uploads (ai_generated);

CREATE TABLE cost_ai_api (
  id integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  transaction_type transaction_type NOT NULL DEFAULT 'single',
  batch_id varchar(255),
  photo_upload_id integer,
  input_tokens integer NOT NULL DEFAULT 0,
  output_tokens integer NOT NULL DEFAULT 0,
  total_tokens integer GENERATED ALWAYS AS (input_tokens + output_tokens) STORED,
  cost_usd numeric(15, 8) NOT NULL DEFAULT 0.00000000,
  cost_idr numeric(18, 2) NOT NULL DEFAULT 0.00,
  status cost_status NOT NULL DEFAULT 'success',
  error_message text,
  total_items integer,
  processed_items integer,
  success_count integer,
  error_count integer,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_batch_id ON cost_ai_api (batch_id);
CREATE INDEX idx_photo_upload_id ON cost_ai_api (photo_upload_id);
CREATE INDEX idx_transaction_type ON cost_ai_api (transaction_type);
CREATE INDEX idx_cost_status ON cost_ai_api (status);
CREATE INDEX idx_cost_created_at ON cost_ai_api (created_at);
CREATE INDEX idx_batch_id_created_at ON cost_ai_api (batch_id, created_at);

CREATE TABLE wib_debug_test (
  id integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  test_time timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE VIEW bcbp_parser_daily_summary AS
SELECT
  (scan_timestamp::date) AS scan_date,
  count(*) AS total_scans,
  count(*) FILTER (WHERE parsing_status = 'success') AS successful_parses,
  count(*) FILTER (WHERE parsing_status = 'failed') AS failed_parses,
  count(*) FILTER (WHERE parsing_status = 'partial') AS partial_parses,
  round(
    (count(*) FILTER (WHERE parsing_status = 'success')::numeric
      / NULLIF(count(*)::numeric, 0)) * 100,
    2
  ) AS success_rate_percent
FROM bcbp_parser
GROUP BY scan_timestamp::date
ORDER BY scan_date DESC;

CREATE VIEW bcbp_parser_stats AS
SELECT
  (scan_timestamp::date) AS scan_date,
  scan_point,
  parsing_status,
  count(*) AS total_scans,
  count(*) FILTER (WHERE parsing_status = 'success') AS successful_parses,
  count(*) FILTER (WHERE parsing_status = 'failed') AS failed_parses,
  count(*) FILTER (WHERE parsing_status = 'partial') AS partial_parses
FROM bcbp_parser
GROUP BY scan_timestamp::date, scan_point, parsing_status
ORDER BY scan_date DESC, scan_point, parsing_status;

CREATE VIEW log_login_daily_summary AS
SELECT
  (login_timestamp::date) AS login_date,
  count(*) AS total_logins,
  count(*) FILTER (WHERE login_status = 'success') AS successful_logins,
  count(*) FILTER (WHERE login_status = 'failed') AS failed_logins,
  count(*) FILTER (WHERE login_status = 'timeout') AS timeout_logins,
  count(*) FILTER (WHERE login_status = 'forced_logout') AS forced_logouts,
  round(
    (count(*) FILTER (WHERE login_status = 'success')::numeric
      / NULLIF(count(*)::numeric, 0)) * 100,
    2
  ) AS success_rate_percent,
  avg(session_duration_seconds) AS avg_session_duration_seconds,
  count(DISTINCT username) AS unique_users,
  count(DISTINCT scan_point) AS active_scan_points
FROM log_login
GROUP BY login_timestamp::date
ORDER BY login_date DESC;

CREATE VIEW log_login_security_monitoring AS
SELECT
  ip_address,
  count(*) AS total_attempts,
  count(*) FILTER (WHERE login_status = 'success') AS successful_logins,
  count(*) FILTER (WHERE login_status = 'failed') AS failed_attempts,
  count(DISTINCT username) AS unique_users_attempted,
  min(login_timestamp) AS first_attempt,
  max(login_timestamp) AS last_attempt,
  CASE
    WHEN count(*) FILTER (WHERE login_status = 'failed') > 5 THEN 'HIGH_RISK'
    WHEN count(*) FILTER (WHERE login_status = 'failed') > 3 THEN 'MEDIUM_RISK'
    ELSE 'LOW_RISK'
  END AS risk_level
FROM log_login
GROUP BY ip_address
HAVING count(*) > 1
ORDER BY failed_attempts DESC, total_attempts DESC;

CREATE VIEW log_login_stats AS
SELECT
  (login_timestamp::date) AS login_date,
  username,
  scan_point,
  login_status,
  count(*) AS total_logins,
  count(*) FILTER (WHERE login_status = 'success') AS successful_logins,
  count(*) FILTER (WHERE login_status = 'failed') AS failed_logins,
  count(*) FILTER (WHERE login_status = 'timeout') AS timeout_logins,
  count(*) FILTER (WHERE login_status = 'forced_logout') AS forced_logouts,
  avg(session_duration_seconds) AS avg_session_duration,
  max(session_duration_seconds) AS max_session_duration
FROM log_login
GROUP BY login_timestamp::date, username, scan_point, login_status
ORDER BY login_date DESC, username, scan_point;

CREATE VIEW log_login_user_sessions AS
SELECT
  user_id,
  username,
  count(*) AS total_sessions,
  count(*) FILTER (WHERE login_status = 'success') AS successful_sessions,
  count(*) FILTER (WHERE login_status = 'failed') AS failed_attempts,
  avg(session_duration_seconds) AS avg_session_duration,
  max(session_duration_seconds) AS max_session_duration,
  min(login_timestamp) AS first_login,
  max(login_timestamp) AS last_login,
  count(DISTINCT (login_timestamp::date)) AS active_days
FROM log_login
GROUP BY user_id, username
ORDER BY total_sessions DESC;

COMMIT;
`;
}

function main() {
  if (!fs.existsSync(MYSQL_DUMP)) {
    throw new Error(`Missing MySQL dump: ${MYSQL_DUMP}`);
  }

  const text = fs.readFileSync(MYSQL_DUMP, 'utf8');
  const lines = text.split(/\r?\n/);

  const inserts = [];
  for (const line of lines) {
    const trimmed = line.trim();
    const parsed = parseMysqlInsertLine(trimmed);
    if (parsed) inserts.push(parsed);
  }

  const passengerIds = new Set();
  for (const ins of inserts) {
    if (ins.table !== 'passengers') continue;
    const idTok = ins.values[0]?.trim();
    const id = Number.parseInt(idTok ?? '', 10);
    if (Number.isFinite(id)) passengerIds.add(id);
  }

  fs.writeFileSync(PG_SCHEMA, pgSchemaSql(), 'utf8');

  const out = [];
  out.push('-- Generated data for PostgreSQL');
  out.push('-- NOTE: photo_uploads rows with invalid passenger_id are skipped');
  out.push('');
  out.push('BEGIN;');

  const tableOrder = [
    'users',
    'scan_points',
    'system_settings',
    'passengers',
    'bcbp_parser',
    'flights',
    'flight_schedule',
    'flight_sync_log',
    'log_login',
    'photo_uploads',
    'cost_ai_api',
    'wib_debug_test',
  ];

  const byTable = new Map(tableOrder.map((t) => [t, []]));
  for (const ins of inserts) {
    if (byTable.has(ins.table)) byTable.get(ins.table).push(ins);
  }

  let skippedPhoto = 0;

  for (const table of tableOrder) {
    const rows = byTable.get(table) ?? [];
    const cols = tableColumns[table];
    for (const ins of rows) {
      if (!cols || ins.values.length !== cols.length) continue;

      if (table === 'photo_uploads') {
        const pidTok = ins.values[1]?.trim() ?? 'NULL';
        if (pidTok.toUpperCase() !== 'NULL') {
          const pid = Number.parseInt(pidTok, 10);
          if (!Number.isFinite(pid) || !passengerIds.has(pid)) {
            skippedPhoto += 1;
            continue;
          }
        }
      }

      const normalized = cols.map((colName, idx) =>
        normalizeValueForPg(table, colName, ins.values[idx] ?? 'NULL'),
      );

      out.push(
        `INSERT INTO ${table} (${cols.join(', ')}) VALUES (${normalized.join(', ')});`,
      );
    }
    out.push('');
  }

  const seqTables = [
    'users',
    'scan_points',
    'system_settings',
    'passengers',
    'bcbp_parser',
    'flights',
    'flight_sync_log',
    'log_login',
    'photo_uploads',
    'cost_ai_api',
    'wib_debug_test',
  ];
  for (const t of seqTables) {
    out.push(
      `SELECT setval(pg_get_serial_sequence('${t}', 'id'), COALESCE((SELECT MAX(id) FROM ${t}), 1), true);`,
    );
  }

  out.push('COMMIT;');
  out.push(`-- skipped_photo_uploads_rows=${skippedPhoto}`);

  fs.writeFileSync(PG_DATA, `${out.join('\n')}\n`, 'utf8');

  // eslint-disable-next-line no-console
  console.log(`Wrote ${PG_SCHEMA}`);
  // eslint-disable-next-line no-console
  console.log(`Wrote ${PG_DATA}`);
  // eslint-disable-next-line no-console
  console.log(`skipped_photo_uploads_rows=${skippedPhoto}`);
}

main();

