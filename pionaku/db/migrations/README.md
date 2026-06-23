# Database migration: legacy schema as source of truth

Target state:

- Application uses **legacy snake_case tables** (`users`, `scan_points`, `passengers`, `bcbp_parser`, `log_login`, `photo_uploads`, ...).
- Prisma models map to legacy tables (see `backend/prisma/schema.prisma`).
- Data from Prisma PascalCase tables (`"User"`, `"ScanPoint"`, `"PassengerScan"`, ...) is merged into legacy tables.
- After verification, PascalCase tables are removed to avoid duplicated tables.

## 0) Backup (required)

Run a full backup before any changes:

```bash
pg_dump --format=custom --file backup.before_legacy_merge.dump <DATABASE_NAME>
```

## 1) Merge data into legacy tables

Run:

- `db/migrations/001_merge_pascalcase_into_legacy.sql`

This will:

- Upsert users from `"User"` into `users`
- Insert missing scan points from `"ScanPoint"` into `scan_points`
- Copy scans from `"PassengerScan"` into `passengers` + `bcbp_parser` with dummy/default values where needed

## 2) Deploy / run the backend with legacy Prisma schema

In `backend/`:

```bash
npm run prisma:generate
npm run typecheck
npm run start
```

## 3) Verification queries (recommended)

### Basic sanity

```sql
select 'users' as t, count(*) from users
union all select 'scan_points', count(*) from scan_points
union all select 'passengers', count(*) from passengers
union all select 'bcbp_parser', count(*) from bcbp_parser;
```

### Confirm new writes go to legacy

After using the app (login + create a scan):

```sql
select max(login_timestamp) from log_login;
select max(scan_timestamp) from bcbp_parser;
```

### Dedupe check (should be 0 rows after index is added)

```sql
select raw_barcode, scan_timestamp, scan_point, count(*) as c
from bcbp_parser
group by raw_barcode, scan_timestamp, scan_point
having count(*) > 1;
```

## 4) Cleanup (drop PascalCase tables)

Only after you are confident the app works on legacy tables, run:

- `db/migrations/002_post_merge_cleanup.sql`

If you want a safer rollout, rename PascalCase tables first instead of dropping.

