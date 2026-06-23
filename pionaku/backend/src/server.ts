import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import Fastify from 'fastify';
import { z } from 'zod';

import { loadEnv } from './env';
import { prisma } from './db';
import bcrypt from 'bcryptjs';
import {
  LoginStatus,
  ParsingStatus,
  PassengerCategory,
  PassengerType,
  Prisma,
  ScanPointStatus,
  UserRole,
  UserStatus,
} from '@prisma/client';

const env = loadEnv(process.env);

declare module 'fastify' {
  interface FastifyInstance {
    authenticate: (request: unknown) => Promise<void>;
  }
}

export type JwtPayload = {
  sub: string;
  username: string;
  role: UserRole;
};

function toScanDayUtc(d: Date): string {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function jwtUserId(payload: JwtPayload): number {
  const n = Number(payload.sub);
  if (!Number.isInteger(n) || n <= 0) {
    throw new Error('Invalid JWT subject');
  }
  return n;
}

function readJsonObject(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}

function pickNonEmptyString(...parts: unknown[]): string {
  for (const p of parts) {
    if (typeof p !== 'string') continue;
    const t = p.trim();
    if (t.length > 0) return t;
  }
  return '';
}

function looksLikeOpaqueToken(name: string): boolean {
  const t = name.trim();
  if (t.length < 24) return false;
  return /^[A-Za-z0-9+/=_-]+$/.test(t);
}

/** IV:ciphertext style blobs sometimes stored as "name" (not decryptable here). */
function looksLikeEncryptedPayload(s: string): boolean {
  const t = s.trim();
  const i = t.indexOf(':');
  if (i <= 0 || i >= t.length - 1) return false;
  const a = t.slice(0, i);
  const b = t.slice(i + 1);
  if (a.length < 8 || b.length < 8) return false;
  const b64 = /^[A-Za-z0-9+/=_-]+$/;
  return b64.test(a) && b64.test(b);
}

function isUnusablePassengerLabel(s: string | null | undefined): boolean {
  if (s == null) return true;
  const t = s.trim();
  if (t.length === 0) return true;
  if (looksLikeEncryptedPayload(t)) return true;
  if (looksLikeOpaqueToken(t)) return true;
  return false;
}

function pickFirstReadable(...parts: unknown[]): string | null {
  for (const p of parts) {
    if (typeof p !== 'string') continue;
    const t = p.trim();
    if (!isUnusablePassengerLabel(t)) return t.slice(0, 200);
  }
  return null;
}

const NAME_HINT_KEYS = new Set([
  'passengername',
  'name',
  'displayname',
  'fullname',
  'givenname',
  'firstname',
  'lastname',
  'surname',
  'nama',
  'penumpang',
  'passenger_name',
  'passengerfullname',
]);

function looksLikePersonName(s: string): boolean {
  const t = s.trim();
  if (t.length < 3 || t.length > 120) return false;
  if (isUnusablePassengerLabel(t)) return false;
  if (/^\d+$/.test(t)) return false;
  return /^[\p{L}][\p{L}\s.'-]{1,118}[\p{L}.]?$/u.test(t);
}

/** Scan parsed JSON for any plausible human name (nested objects/arrays). */
function deepFindReadableNameInJson(value: unknown, depth = 0): string | null {
  if (depth > 12) return null;
  if (typeof value === 'string') {
    return looksLikePersonName(value) ? value.trim().slice(0, 200) : null;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      const n = deepFindReadableNameInJson(item, depth + 1);
      if (n) return n;
    }
    return null;
  }
  if (value && typeof value === 'object') {
    const o = value as Record<string, unknown>;
    const keys = Object.keys(o);
    for (const k of keys) {
      if (!NAME_HINT_KEYS.has(k.toLowerCase())) continue;
      const n = deepFindReadableNameInJson(o[k], depth + 1);
      if (n) return n;
    }
    for (const k of keys) {
      const n = deepFindReadableNameInJson(o[k], depth + 1);
      if (n) return n;
    }
  }
  return null;
}

/**
 * Name from this bcbp_parser row only (parsed_data JSON).
 * API list uses one parser row joined to passenger via FK — this is the source of truth for display.
 */
function passengerNameFromParsedData(parsedData: unknown): string | null {
  const j = readJsonObject(parsedData);
  if (Object.keys(j).length === 0) return null;
  const direct = pickFirstReadable(
    j['passengerName'],
    j['name'],
    j['displayName'],
    j['passenger_name'],
    j['fullName'],
    j['passengerFullName'],
    j['customerName'],
    j['namaPenumpang'],
  );
  if (direct) return direct;
  const fnRaw = pickNonEmptyString(j['firstName'], j['givenName']);
  const lnRaw = pickNonEmptyString(j['lastName'], j['surname']);
  const fn = isUnusablePassengerLabel(fnRaw) ? '' : fnRaw.trim();
  const ln = isUnusablePassengerLabel(lnRaw) ? '' : lnRaw.trim();
  if (fn.length > 0 || ln.length > 0) {
    return `${fn} ${ln}`.trim().slice(0, 200);
  }
  const nested = j['passenger'];
  if (nested && typeof nested === 'object' && !Array.isArray(nested)) {
    const n = readJsonObject(nested);
    const nestedName = pickFirstReadable(
      n['name'],
      n['fullName'],
      n['passengerName'],
      n['nama'],
    );
    if (nestedName) return nestedName;
  }
  return null;
}

/**
 * For list/detail of bcbp_parser rows: display name comes ONLY from this parser
 * row's parsed_data (FK passenger_id → passengers.id). We intentionally do not
 * trust passengers.name here — legacy rows often store ciphertext there.
 */
function passengerDisplayNameFromBcbpRow(params: {
  parsedData: unknown;
  pnr: string;
}): string {
  const fromParser = passengerNameFromParsedData(params.parsedData);
  if (fromParser != null && fromParser.length > 0) return fromParser;
  const deep = deepFindReadableNameInJson(params.parsedData);
  if (deep) return deep;
  const pnr = params.pnr.trim();
  if (pnr.length > 0 && pnr !== 'UNKNOWN') return pnr.slice(0, 200);
  return 'Penumpang';
}

function displayAirportCode(parsedData: unknown, origin: string): string {
  const j = readJsonObject(parsedData);
  const fromJson = pickNonEmptyString(j['airportCode'], j['airport']);
  if (fromJson.length > 0) return fromJson.toUpperCase().slice(0, 10);
  const o = origin.trim().toUpperCase();
  return o === '' || o === 'UNK' ? '' : o;
}

function buildParsedDataForScan(input: {
  airportCode?: string | undefined;
  passengerName: string;
  boardingDate: string;
  flight: string;
  origin: string;
  destination: string;
  pnrOrCode: string;
}): Prisma.InputJsonValue {
  const rawPn = pickNonEmptyString(input.passengerName);
  const payload: Record<string, unknown> = {
    airportCode: pickNonEmptyString(input.airportCode)?.toUpperCase() ?? null,
    passengerName:
      rawPn.length > 0 && !isUnusablePassengerLabel(rawPn) ? rawPn : null,
    boardingDate: pickNonEmptyString(input.boardingDate) || null,
    flight: pickNonEmptyString(input.flight) || null,
    origin: pickNonEmptyString(input.origin)?.toUpperCase() || null,
    destination: pickNonEmptyString(input.destination)?.toUpperCase() || null,
    pnrOrCode: pickNonEmptyString(input.pnrOrCode) || null,
  };
  return JSON.parse(
    JSON.stringify(payload, (_, v) =>
      v === '' || v === null || v === undefined ? undefined : v,
    ),
  ) as Prisma.InputJsonValue;
}

function assertAdminOrIt(request: any, reply: any) {
  const jwtPayload = request.user as JwtPayload | undefined;
  const role = jwtPayload?.role;
  if (role !== UserRole.Admin && role !== UserRole.IT) {
    reply.code(403).send({ message: 'Forbidden' });
    return false;
  }
  return true;
}

function assertIt(request: any, reply: any) {
  const jwtPayload = request.user as JwtPayload | undefined;
  const role = jwtPayload?.role;
  if (role !== UserRole.IT) {
    reply.code(403).send({ message: 'Forbidden' });
    return false;
  }
  return true;
}

export async function buildServer() {
  const app = Fastify({
    logger: true,
  });

  await app.register(cors, {
    origin: true,
    credentials: true,
  });

  await app.register(jwt, {
    secret: env.JWT_SECRET,
  });

  app.decorate(
    'authenticate',
    async (request: any) => {
      await request.jwtVerify();
    },
  );

  app.get('/health', async () => {
    return { ok: true };
  });

  app.post('/auth/login', async (request, reply) => {
    const Body = z.object({
      username: z.string().min(1),
      password: z.string().min(1),
      airportCode: z.string().optional().default(''),
      checkpoint: z.string().optional().default(''),
    });

    const body = Body.parse(request.body);
    const username = body.username.trim();
    const password = body.password;

    // Ensure a dev default user exists (idempotent).
    const devUsername = env.DEV_DEFAULT_USERNAME.trim();
    if (devUsername) {
      const existing = await prisma.user.findUnique({
        where: { username: devUsername },
      });
      if (!existing) {
        const passwordHash = await bcrypt.hash(env.DEV_DEFAULT_PASSWORD, 10);
        await prisma.user.create({
          data: {
            username: devUsername,
            password: passwordHash,
            role: env.DEV_DEFAULT_ROLE as UserRole,
            status: UserStatus.Active,
          },
        });
      }
    }

    const user = await prisma.user.findUnique({ where: { username } });
    if (!user) {
      return reply.code(401).send({ message: 'Invalid credentials' });
    }

    if (user.status !== UserStatus.Active) {
      return reply.code(403).send({ message: 'Account is inactive' });
    }

    const ok = await bcrypt.compare(password, user.password);
    if (!ok) {
      return reply.code(401).send({ message: 'Invalid credentials' });
    }

    const token = await reply.jwtSign({
      sub: String(user.id),
      username: user.username,
      role: user.role,
    } satisfies JwtPayload);

    const airportCode = body.airportCode.trim();
    const checkpoint = body.checkpoint.trim();

    // Revoke previous active logins so only one checkpoint is active.
    await prisma.logLogin.updateMany({
      where: {
        userId: user.id,
        logoutTimestamp: null,
        loginStatus: LoginStatus.success,
      },
      data: {
        logoutTimestamp: new Date(),
        loginStatus: LoginStatus.forced_logout,
        updatedAt: new Date(),
      },
    });

    // Create a new login/session row (legacy-compatible).
    const ipAddress =
      (request.headers['x-forwarded-for'] as string | undefined) ??
      request.ip ??
      undefined;
    const userAgent = request.headers['user-agent'] as string | undefined;

    await prisma.logLogin.create({
      data: {
        userId: user.id,
        loginTimestamp: new Date(),
        loginStatus: LoginStatus.success,
        ipAddress,
        userAgent,
        scanPoint: checkpoint || null,
        airportBranch: airportCode || null,
        updatedAt: new Date(),
      },
      select: { id: true },
    });

    // Ensure the chosen scan point exists (for login dropdown sync).
    const cpName = checkpoint.trim();
    if (cpName) {
      await prisma.scanPoint.upsert({
        where: { name: cpName },
        create: { name: cpName, status: ScanPointStatus.Active },
        update: {},
        select: { id: true },
      });
    }

    return {
      token,
      user: {
        id: user.id,
        username: user.username,
        role: user.role,
      },
      context: {
        airportCode,
        checkpoint,
      },
    };
  });

  // Heartbeat to keep a session "active" for real-time scan point status.
  app.post(
    '/session/ping',
    { preHandler: app.authenticate },
    async (request: any) => {
      const jwtPayload = request.user as JwtPayload;
      const userId = jwtUserId(jwtPayload);
      await prisma.logLogin.updateMany({
        where: { userId, logoutTimestamp: null, loginStatus: LoginStatus.success },
        data: { updatedAt: new Date() },
      });
      return { ok: true };
    },
  );

  // Public scan point list for LoginScreen (no auth).
  app.get('/public/scan-points', async () => {
    const rows = await prisma.scanPoint.findMany({
      orderBy: { name: 'asc' },
      select: { name: true },
    });
    return { items: rows };
  });

  app.get(
    '/me',
    { preHandler: (app as any).authenticate },
    async (request: any) => {
      const jwtPayload = request.user as JwtPayload;
      return {
        user: {
          id: jwtPayload.sub,
          username: jwtPayload.username,
          role: jwtPayload.role,
        },
      };
    },
  );

  app.get(
    '/users',
    { preHandler: app.authenticate },
    async () => {
      const rows = await prisma.user.findMany({
        orderBy: { createdAt: 'desc' },
        select: {
          id: true,
          username: true,
          role: true,
          status: true,
          createdAt: true,
        },
      });

      const lastLogin = await prisma.logLogin.groupBy({
        by: ['userId'],
        where: { loginStatus: LoginStatus.success },
        _max: { loginTimestamp: true },
      });
      const lastLoginByUserId = new Map<number, Date | null>(
        lastLogin.map((g) => [g.userId, g._max.loginTimestamp ?? null]),
      );

      const items = rows.map((r) => ({
        ...r,
        lastLoginAt: lastLoginByUserId.get(r.id) ?? null,
      }));
      return { items };
    },
  );

  app.post(
    '/users',
    { preHandler: app.authenticate },
    async (request: any, reply) => {
      if (!assertAdminOrIt(request, reply)) return;

      const Body = z.object({
        username: z.string().min(1),
        password: z.string().min(6),
        role: z.enum(['Admin', 'IT', 'Scan', 'View']),
        status: z.enum(['active', 'inactive']).optional(),
      });
      const body = Body.parse(request.body);

      const passwordHash = await bcrypt.hash(body.password, 10);
      try {
        const created = await prisma.user.create({
          data: {
            username: body.username.trim(),
            password: passwordHash,
            role: body.role as UserRole,
            status:
              (body.status ?? 'active') === 'active'
                ? UserStatus.Active
                : UserStatus.Inactive,
          },
          select: {
            id: true,
            username: true,
            role: true,
            status: true,
            createdAt: true,
          },
        });
        return { item: { ...created, lastLoginAt: null } };
      } catch (_) {
        return reply.code(400).send({ message: 'User already exists' });
      }
    },
  );

  app.put(
    '/users/:id',
    { preHandler: app.authenticate },
    async (request: any, reply) => {
      if (!assertAdminOrIt(request, reply)) return;

      const Params = z.object({ id: z.coerce.number().int().positive() });
      const Body = z.object({
        username: z.string().min(1).optional(),
        password: z.string().min(6).optional(),
        role: z.enum(['Admin', 'IT', 'Scan', 'View']).optional(),
        status: z.enum(['active', 'inactive']).optional(),
      });
      const params = Params.parse(request.params);
      const body = Body.parse(request.body);

      const data: Prisma.UserUpdateInput = {};
      if (body.username && body.username.trim().length > 0) {
        data.username = body.username.trim();
      }
      if (body.role) {
        data.role = body.role as UserRole;
      }
      if (body.status) {
        data.status = body.status === 'active' ? UserStatus.Active : UserStatus.Inactive;
      }
      if (body.password && body.password.trim().length > 0) {
        data.password = await bcrypt.hash(body.password, 10);
      }

      try {
        const updated = await prisma.user.update({
          where: { id: params.id },
          data,
          select: {
            id: true,
            username: true,
            role: true,
            status: true,
            createdAt: true,
          },
        });
        return { item: { ...updated, lastLoginAt: null } };
      } catch (_) {
        return reply.code(404).send({ message: 'Not found' });
      }
    },
  );

  app.delete(
    '/users/:id',
    { preHandler: app.authenticate },
    async (request: any, reply) => {
      if (!assertAdminOrIt(request, reply)) return;

      const Params = z.object({ id: z.coerce.number().int().positive() });
      const params = Params.parse(request.params);
      try {
        await prisma.user.delete({ where: { id: params.id } });
        return { ok: true };
      } catch (_) {
        return reply.code(404).send({ message: 'Not found' });
      }
    },
  );

  app.get(
    '/scan-points',
    { preHandler: app.authenticate },
    async () => {
      const rows = await prisma.scanPoint.findMany({
        orderBy: { createdAt: 'desc' },
      });

      // Compute real-time "active" based on log_login heartbeat.
      const activeSince = new Date(Date.now() - 90_000);
      const active = await prisma.logLogin.groupBy({
        by: ['scanPoint'],
        where: {
          logoutTimestamp: null,
          loginStatus: LoginStatus.success,
          updatedAt: { gte: activeSince },
          scanPoint: { not: null },
        },
        _count: { _all: true },
      });
      const activeCountByCheckpoint = new Map<string, number>(
        active
          .filter((g) => (g.scanPoint ?? '').trim().length > 0)
          .map((g) => [g.scanPoint as string, g._count._all]),
      );

      const items = rows.map((r) => {
        const c = activeCountByCheckpoint.get(r.name) ?? 0;
        return {
          ...r,
          status: c > 0 ? 'active' : 'inactive',
          activeSessions: c,
        };
      });
      return { items };
    },
  );

  app.post(
    '/scan-points',
    { preHandler: app.authenticate },
    async (request: any, reply) => {
      if (!assertIt(request, reply)) return;
      const Body = z.object({
        name: z.string().min(1),
      });
      const body = Body.parse(request.body);
      const created = await prisma.scanPoint.create({
        data: {
          name: body.name.trim(),
          status: ScanPointStatus.Active,
        },
      });
      return { item: created };
    },
  );

  app.put(
    '/scan-points/:id',
    { preHandler: app.authenticate },
    async (request, reply) => {
      if (!assertIt(request, reply)) return;
      const Params = z.object({ id: z.coerce.number().int().positive() });
      const Body = z.object({
        name: z.string().min(1),
      });
      const params = Params.parse(request.params);
      const body = Body.parse(request.body);
      try {
        const updated = await prisma.scanPoint.update({
          where: { id: params.id },
          data: {
            name: body.name.trim(),
          },
        });
        return { item: updated };
      } catch (_) {
        return reply.code(404).send({ message: 'Not found' });
      }
    },
  );

  app.delete(
    '/scan-points/:id',
    { preHandler: app.authenticate },
    async (request, reply) => {
      if (!assertIt(request, reply)) return;
      const Params = z.object({ id: z.coerce.number().int().positive() });
      const params = Params.parse(request.params);
      try {
        await prisma.scanPoint.delete({ where: { id: params.id } });
        return { ok: true };
      } catch (_) {
        return reply.code(404).send({ message: 'Not found' });
      }
    },
  );

  app.get(
    '/passenger-scans',
    { preHandler: app.authenticate },
    async (request) => {
      const Query = z.object({
        date: z.string().optional(),
        airportCode: z.string().optional(),
        airportCodes: z.string().optional(),
        scanPoint: z.string().optional(),
        since: z.string().optional(),
      });
      const q = Query.parse(request.query);

      const where: Prisma.BcbpParserWhereInput = {};

      if (q.scanPoint && q.scanPoint.trim().length > 0) {
        where.scanPoint = q.scanPoint.trim();
      }

      if (q.date && q.date.trim().length > 0) {
        const start = new Date(`${q.date.trim()}T00:00:00.000Z`);
        const end = new Date(`${q.date.trim()}T23:59:59.999Z`);
        where.scanTimestamp = { gte: start, lte: end };
      }

      if (q.since && q.since.trim().length > 0) {
        const since = new Date(q.since.trim());
        if (!Number.isNaN(since.getTime())) {
          where.createdAt = { gte: since };
        }
      }

      const fromCodesParam =
        typeof q.airportCodes === 'string' && q.airportCodes.trim().length > 0
          ? q.airportCodes
              .split(',')
              .map((s) => s.trim())
              .filter((s) => s.length > 0)
          : [];
      const fromSingle =
        typeof q.airportCode === 'string' && q.airportCode.trim().length > 0
          ? [q.airportCode.trim()]
          : [];
      const airportFilter =
        fromCodesParam.length > 0 ? fromCodesParam : fromSingle;
      if (airportFilter.length > 0) {
        const ups = [
          ...new Set(airportFilter.map((c) => c.toUpperCase())),
        ].filter((c) => c.length > 0 && c !== 'UNK');
        if (ups.length > 0) {
          where.OR = ups.flatMap((code) => [
            { passenger: { origin: code } },
            { parsedData: { path: ['airportCode'], equals: code } },
          ]);
        }
      }

      const rows = await prisma.bcbpParser.findMany({
        where,
        orderBy: { scanTimestamp: 'desc' },
        include: { passenger: true },
      });

      const items = rows.map((r) => {
        const status =
          r.parsingStatus === ParsingStatus.success
            ? 'complete'
            : r.parsingStatus === ParsingStatus.partial
              ? 'partial'
              : 'failed';
        const passengerName = passengerDisplayNameFromBcbpRow({
          parsedData: r.parsedData,
          pnr: r.passenger.pnr,
        });
        const airportCode = displayAirportCode(
          r.parsedData,
          r.passenger.origin,
        );
        return {
          id: String(r.id),
          passengerName,
          boardingDate:
            r.passenger.flightDate instanceof Date
              ? r.passenger.flightDate.toISOString().slice(0, 10)
              : '',
          seat: r.passenger.seatNumber,
          flight: r.passenger.flightNumber,
          origin: r.passenger.origin,
          destination: r.passenger.destination,
          passengerType: r.passenger.type,
          category: r.passenger.category,
          pnrOrCode: r.passenger.pnr,
          airportCode,
          scanPoint: r.scanPoint,
          scannedAt: r.scanTimestamp,
          scanDay: toScanDayUtc(r.scanTimestamp),
          source: 'scan',
          status,
          barcodeValue: r.rawBarcode,
          createdAt: r.createdAt ?? r.scanTimestamp,
        };
      });

      return { items };
    },
  );

  app.get(
    '/passenger-scans/airports',
    { preHandler: app.authenticate },
    async () => {
      const [pOrigins, jsonCodes] = await Promise.all([
        prisma.passenger.findMany({
          select: { origin: true },
          distinct: ['origin'],
          where: { origin: { not: 'UNK' } },
        }),
        prisma.$queryRaw<Array<{ c: string }>>`
          SELECT DISTINCT UPPER(TRIM(b.parsed_data->>'airportCode')) AS c
          FROM bcbp_parser b
          WHERE COALESCE(TRIM(b.parsed_data->>'airportCode'), '') <> ''
            AND UPPER(TRIM(b.parsed_data->>'airportCode')) <> 'UNK'
        `,
      ]);
      const set = new Set<string>();
      for (const r of pOrigins) {
        const v = r.origin.trim().toUpperCase();
        if (v.length > 0 && v !== 'UNK') set.add(v);
      }
      for (const r of jsonCodes) {
        const v = r.c.trim().toUpperCase();
        if (v.length > 0 && v !== 'UNK') set.add(v);
      }
      return { items: Array.from(set).sort() };
    },
  );

  app.post(
    '/passenger-scans',
    { preHandler: app.authenticate },
    async (request, reply) => {
      const Body = z.object({
        passengerName: z.string(),
        boardingDate: z.string(),
        seat: z.string(),
        flight: z.string(),
        origin: z.string(),
        destination: z.string(),
        passengerType: z.string(),
        category: z.string(),
        pnrOrCode: z.string(),
        airportCode: z.string().optional(),
        scanPoint: z.string(),
        scannedAt: z.coerce.date(),
        status: z.enum(['complete', 'partial', 'failed']),
        barcodeValue: z.string(),
        source: z.enum(['scan', 'manual']).optional(),
      });
      const b = Body.parse(request.body);
      const scanPoint = b.scanPoint.trim();
      const barcodeValue = b.barcodeValue.trim();
      const scanDay = toScanDayUtc(b.scannedAt);
      const source = b.source ?? 'scan';
      void scanDay;
      void source;

      try {
        const jwtPayload = request.user as JwtPayload;
        const scannerUserId = jwtUserId(jwtPayload);

        const passengerType =
          b.passengerType === 'Child'
            ? PassengerType.Child
            : b.passengerType === 'Infant'
              ? PassengerType.Infant
              : PassengerType.Adult;
        const category =
          b.category === 'Transit' ? PassengerCategory.Transit : PassengerCategory.Normal;

        const flightDate =
          /^\d{4}-\d{2}-\d{2}$/.test(b.boardingDate.trim()) &&
          !Number.isNaN(new Date(`${b.boardingDate.trim()}T00:00:00.000Z`).getTime())
            ? new Date(`${b.boardingDate.trim()}T00:00:00.000Z`)
            : new Date(`${b.scannedAt.toISOString().slice(0, 10)}T00:00:00.000Z`);

        const pnr = b.pnrOrCode.trim().slice(0, 10) || 'UNKNOWN';
        const seatNumber = b.seat.trim().slice(0, 10) || 'UNK';
        const flightNumber = b.flight.trim().slice(0, 15) || 'UNKNOWN';

        const displayName =
          b.passengerName.trim().slice(0, 200) || 'UNKNOWN';
        const parsedData = buildParsedDataForScan({
          airportCode: b.airportCode,
          passengerName: b.passengerName,
          boardingDate: b.boardingDate,
          flight: b.flight,
          origin: b.origin,
          destination: b.destination,
          pnrOrCode: b.pnrOrCode,
        });

        const passenger = await prisma.passenger.upsert({
          where: {
            uniquePassenger: {
              type: passengerType,
              seatNumber,
              flightDate,
              flightNumber,
            },
          },
          create: {
            pnr,
            name: displayName,
            flightNumber,
            origin: b.origin.trim().slice(0, 10) || 'UNK',
            destination: b.destination.trim().slice(0, 10) || 'UNK',
            seatNumber,
            flightDate,
            type: passengerType,
            category,
            scannedAt: b.scannedAt,
            scanPoint,
          },
          update: {
            scannedAt: b.scannedAt,
            scanPoint,
            name: displayName,
          },
        });

        const parsingStatus =
          b.status === 'complete'
            ? ParsingStatus.success
            : b.status === 'partial'
              ? ParsingStatus.partial
              : ParsingStatus.failed;

        const existing = await prisma.bcbpParser.findFirst({
          where: {
            rawBarcode: barcodeValue,
            scanPoint,
            scanTimestamp: b.scannedAt,
          },
          select: { id: true },
        });
        if (existing) {
          return reply.code(409).send({ message: 'Duplicate scan' });
        }

        const created = await prisma.bcbpParser.create({
          data: {
            rawBarcode: barcodeValue,
            parsedData,
            parsingStatus,
            scanTimestamp: b.scannedAt,
            scanPoint,
            scannerUserId,
            passengerId: passenger.id,
          },
          include: { passenger: true },
        });

        const syncedPassengerName = passengerDisplayNameFromBcbpRow({
          parsedData: created.parsedData,
          pnr: created.passenger.pnr,
        });
        await prisma.passenger.update({
          where: { id: passenger.id },
          data: { name: syncedPassengerName.slice(0, 200) },
        });

        const item = {
          id: String(created.id),
          passengerName: syncedPassengerName,
          boardingDate: created.passenger.flightDate
            ? created.passenger.flightDate.toISOString().slice(0, 10)
            : '',
          seat: created.passenger.seatNumber,
          flight: created.passenger.flightNumber,
          origin: created.passenger.origin,
          destination: created.passenger.destination,
          passengerType: created.passenger.type,
          category: created.passenger.category,
          pnrOrCode: created.passenger.pnr,
          airportCode: displayAirportCode(
            created.parsedData,
            created.passenger.origin,
          ),
          scanPoint: created.scanPoint,
          scannedAt: created.scanTimestamp,
          scanDay: toScanDayUtc(created.scanTimestamp),
          source: 'scan',
          status: b.status,
          barcodeValue: created.rawBarcode,
          createdAt: created.createdAt ?? created.scanTimestamp,
        };

        return { item, deduped: false };
      } catch (err) {
        throw err;
      }
    },
  );

  app.get(
    '/manual-entry',
    { preHandler: app.authenticate },
    async (request) => {
      const Query = z.object({
        date: z.string().optional(),
        airportCode: z.string().optional(),
        status: z.enum(['pending', 'aiGenerated', 'completed', 'trash']).optional(),
      });
      const q = Query.parse(request.query);

      const where: Prisma.PhotoUploadWhereInput = {};
      if (q.date && q.date.trim().length > 0) {
        const start = new Date(`${q.date.trim()}T00:00:00.000Z`);
        const end = new Date(`${q.date.trim()}T23:59:59.999Z`);
        where.uploadTimestamp = { gte: start, lte: end };
      }

      // Legacy photo_uploads doesn't store airportCode; keep filter param for compatibility.
      void q.airportCode;

      if (q.status === 'trash') {
        where.deletedAt = { not: null };
      } else if (q.status === 'completed') {
        where.manualEntrySaved = true;
        where.deletedAt = null;
      } else if (q.status === 'aiGenerated') {
        where.aiGenerated = true;
        where.manualEntrySaved = false;
        where.deletedAt = null;
      } else if (q.status === 'pending') {
        where.aiGenerated = false;
        where.manualEntrySaved = false;
        where.deletedAt = null;
      }

      const rows = await prisma.photoUpload.findMany({
        where,
        orderBy: { uploadTimestamp: 'desc' },
      });

      const items = rows.map((r) => {
        const status =
          r.deletedAt
            ? 'trash'
            : r.manualEntrySaved
              ? 'completed'
              : r.aiGenerated
                ? 'aiGenerated'
                : 'pending';
        return {
          id: String(r.id),
          relativePath: '',
          displayFileName: r.filename,
          sizeBytes: r.fileSize,
          createdAt: r.uploadTimestamp,
          source: r.sourceType === 'scan_transit' ? 'transit' : 'normal',
          status,
          userDisplay: '',
          scanPoint: '',
          airportCode: '',
          parsed: r.aiGeneratedData ?? undefined,
          updatedAt: r.updatedAt ?? r.createdAt ?? new Date(),
        };
      });

      return { items };
    },
  );

  app.post(
    '/manual-entry',
    { preHandler: app.authenticate },
    async (request) => {
      const Body = z.object({
        relativePath: z.string().optional().default(''),
        displayFileName: z.string().optional().default(''),
        sizeBytes: z.coerce.number().int().nonnegative().optional().default(0),
        createdAt: z.coerce.date().optional(),
        source: z.enum(['normal', 'transit']),
        status: z
          .enum(['pending', 'aiGenerated', 'completed', 'trash'])
          .optional()
          .default('pending'),
        userDisplay: z.string().optional().default(''),
        scanPoint: z.string().optional().default(''),
        airportCode: z.string().optional().default(''),
        parsed: z.record(z.string(), z.unknown()).optional(),
      });
      const b = Body.parse(request.body);

      const uploadTimestamp = b.createdAt ?? new Date();
      const filename = b.displayFileName.trim() || b.relativePath.trim() || 'UNKNOWN';
      const aiGenerated = b.status === 'aiGenerated';
      const manualEntrySaved = b.status === 'completed';
      const deletedAt = b.status === 'trash' ? new Date() : null;

      const created = await prisma.photoUpload.create({
        data: {
          filename,
          fileSize: b.sizeBytes,
          uploadTimestamp,
          sourceType: b.source === 'transit' ? 'scan_transit' : 'data_entry',
          aiGenerated,
          aiGeneratedData: (b.parsed as Prisma.InputJsonValue | undefined) ?? undefined,
          aiGeneratedAt: aiGenerated ? new Date() : null,
          manualEntrySaved,
          deletedAt,
        },
      });

      return {
        item: {
          id: String(created.id),
          relativePath: b.relativePath.trim(),
          displayFileName: b.displayFileName.trim(),
          sizeBytes: created.fileSize,
          createdAt: created.uploadTimestamp,
          source: b.source,
          status: b.status,
          userDisplay: b.userDisplay.trim(),
          scanPoint: b.scanPoint.trim(),
          airportCode: b.airportCode.trim(),
          parsed: b.parsed ?? undefined,
          updatedAt: created.updatedAt ?? created.createdAt ?? new Date(),
        },
      };
    },
  );

  app.put(
    '/manual-entry/:id',
    { preHandler: app.authenticate },
    async (request, reply) => {
      const Params = z.object({ id: z.coerce.number().int().positive() });
      const Body = z.object({
        status: z.enum(['pending', 'aiGenerated', 'completed', 'trash']).optional(),
        parsed: z.record(z.string(), z.unknown()).optional(),
      });
      const params = Params.parse(request.params);
      const body = Body.parse(request.body);
      try {
        const data: Prisma.PhotoUploadUpdateInput = {};
        if (body.parsed) {
          data.aiGeneratedData = body.parsed as Prisma.InputJsonValue;
        }
        if (body.status) {
          data.deletedAt = body.status === 'trash' ? new Date() : null;
          data.aiGenerated = body.status === 'aiGenerated';
          data.manualEntrySaved = body.status === 'completed';
          data.aiGeneratedAt = body.status === 'aiGenerated' ? new Date() : null;
        }

        const updated = await prisma.photoUpload.update({
          where: { id: params.id },
          data,
        });
        const status =
          updated.deletedAt
            ? 'trash'
            : updated.manualEntrySaved
              ? 'completed'
              : updated.aiGenerated
                ? 'aiGenerated'
                : 'pending';
        return {
          item: {
            id: String(updated.id),
            relativePath: '',
            displayFileName: updated.filename,
            sizeBytes: updated.fileSize,
            createdAt: updated.uploadTimestamp,
            source: updated.sourceType === 'scan_transit' ? 'transit' : 'normal',
            status,
            userDisplay: '',
            scanPoint: '',
            airportCode: '',
            parsed: updated.aiGeneratedData ?? undefined,
            updatedAt: updated.updatedAt ?? updated.createdAt ?? new Date(),
          },
        };
      } catch (_) {
        return reply.code(404).send({ message: 'Not found' });
      }
    },
  );

  app.delete(
    '/manual-entry/:id',
    { preHandler: app.authenticate },
    async (request, reply) => {
      const Params = z.object({ id: z.coerce.number().int().positive() });
      const params = Params.parse(request.params);
      try {
        await prisma.photoUpload.update({
          where: { id: params.id },
          data: { deletedAt: new Date() },
          select: { id: true },
        });
        return { ok: true };
      } catch (_) {
        return reply.code(404).send({ message: 'Not found' });
      }
    },
  );

  app.addHook('onClose', async () => {
    await prisma.$disconnect();
  });

  return app;
}

async function main() {
  const app = await buildServer();
  await app.listen({ port: env.PORT, host: env.HOST });
}

main().catch((err) => {
  // eslint-disable-next-line no-console
  console.error(err);
  process.exit(1);
});

