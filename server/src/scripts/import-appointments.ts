/**
 * Imports appointment history (e.g. a converted YCLIENTS «Отчёт по записям») from a JSON file.
 *
 *   node dist/scripts/import-appointments.js <visits.json> [--apply]
 *
 * - Masters are matched by name; missing ones become master employees with a random password
 *   (an admin sets a real one in the app). Masters without visits in the last 90 days (or ahead) are inactive.
 * - Clients are matched by phone, then by the «неполный номер» note, then by a unique name; unknown ones are
 *   created; visits without any client go to one placeholder client.
 * - Rows are inserted directly: no reminders or aftercare messages are scheduled.
 * Without --apply it is a dry run. Re-running is safe (same client + master + start time is skipped).
 * Written with erasable TypeScript only, so Node can run the .ts file directly inside the server image.
 */
import { randomBytes } from 'node:crypto';
import bcrypt from 'bcryptjs';
import { and, count, eq, isNull, like } from 'drizzle-orm';
import { z } from 'zod';
import type { Db, DbOrTx } from '../db/client.js';
import { appointments, clients, employees } from '../db/schema.js';
import { BCRYPT_ROUNDS, EMPLOYEE_PALETTE } from '../db/seed.js';
import { createClient, findClientByPhone } from '../domain/clients.js';
import { isPlausiblePhone, normalizePhone } from '../lib/phone.js';
import { instant, money, nullableText, requiredText } from '../lib/validation.js';
import { isEntryPoint, runImportCli, type ImportOptions } from './cli.js';

const ACTIVE_WINDOW_MS = 90 * 24 * 60 * 60 * 1000;
export const PLACEHOLDER_CLIENT_NAME = 'Клиент без карточки (YCLIENTS)';

const visitSchema = z.object({
  masterName: requiredText(100),
  clientName: z.string().trim().max(200).nullish(),
  clientPhone: z.string().regex(/^\d{5,15}$/).nullish(),
  startsAt: instant,
  durationMin: z.number().int().min(5).max(24 * 60),
  status: z.enum(['scheduled', 'confirmed', 'completed', 'cancelled', 'no_show']),
  title: nullableText(500),
  price: money,
  notes: nullableText(5000),
  createdAt: instant.nullish(),
});

type Visit = z.output<typeof visitSchema>;
export type VisitImportRecord = z.input<typeof visitSchema>;

export interface AppointmentImportSummary {
  total: number;
  created: number;
  existing: number;
  invalid: Array<{ index: number; error: string }>;
  mastersCreated: Array<{ name: string; login: string; active: boolean }>;
  clientsMatched: number;
  clientsCreated: number;
  placeholderVisits: number;
}

const TRANSLIT: Record<string, string> = {
  а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ё: 'e', ж: 'zh', з: 'z', и: 'i', й: 'y', к: 'k', л: 'l', м: 'm',
  н: 'n', о: 'o', п: 'p', р: 'r', с: 's', т: 't', у: 'u', ф: 'f', х: 'kh', ц: 'ts', ч: 'ch', ш: 'sh', щ: 'sch',
  ъ: '', ы: 'y', ь: '', э: 'e', ю: 'yu', я: 'ya',
};

export function loginFor(name: string): string {
  const latin = [...name.toLowerCase()].map((ch) => TRANSLIT[ch] ?? ch).join('');
  return latin.replace(/[^a-z0-9]+/g, '.').replace(/^\.+|\.+$/g, '') || 'master';
}

function freeLogin(db: DbOrTx, base: string): string {
  for (let n = 1; ; n += 1) {
    const login = n === 1 ? base : `${base}${n}`;
    if (!db.select({ id: employees.id }).from(employees).where(eq(employees.login, login)).get()) return login;
  }
}

function ensureMaster(db: DbOrTx, name: string, active: boolean, apply: boolean, summary: AppointmentImportSummary): number {
  const existing = db.select({ id: employees.id }).from(employees).where(eq(employees.name, name)).get();
  if (existing) return existing.id;
  const login = freeLogin(db, loginFor(name));
  summary.mastersCreated.push({ name, login, active });
  if (!apply) return -summary.mastersCreated.length;
  const total = db.select({ n: count() }).from(employees).get()?.n ?? 0;
  const now = Date.now();
  return db
    .insert(employees)
    .values({
      name,
      login,
      passwordHash: bcrypt.hashSync(randomBytes(24).toString('hex'), BCRYPT_ROUNDS),
      phone: null,
      color: EMPLOYEE_PALETTE[total % EMPLOYEE_PALETTE.length]!,
      isMaster: true,
      active,
      createdAt: now,
      updatedAt: now,
    })
    .returning({ id: employees.id })
    .get().id;
}

function findClient(db: DbOrTx, visit: Visit): number | null {
  const digits = visit.clientPhone ?? null;
  const phone = digits ? normalizePhone(digits) : null;
  if (phone && isPlausiblePhone(phone) && digits!.length >= 11) {
    const byPhone = findClientByPhone(db, phone);
    if (byPhone) return byPhone.id;
  }
  if (digits && digits.length < 11) {
    const byNote = db
      .select({ id: clients.id })
      .from(clients)
      .where(and(isNull(clients.phone), like(clients.notes, `%Неполный номер в YCLIENTS: ${digits} %`)))
      .get();
    if (byNote) return byNote.id;
  }
  if (visit.clientName) {
    const byName = db.select({ id: clients.id }).from(clients).where(eq(clients.name, visit.clientName)).all();
    if (byName.length === 1) return byName[0]!.id;
  }
  return null;
}

function resolveClient(db: DbOrTx, visit: Visit, opts: ImportOptions, summary: AppointmentImportSummary): number {
  if (!visit.clientName && !visit.clientPhone) {
    summary.placeholderVisits += 1;
    const placeholder = db.select({ id: clients.id }).from(clients).where(eq(clients.name, PLACEHOLDER_CLIENT_NAME)).get();
    if (placeholder) return placeholder.id;
    if (!opts.apply) return -1;
    return createClient(db, {
      name: PLACEHOLDER_CLIENT_NAME,
      notes: 'Визиты из YCLIENTS, у которых не было клиентской карточки.',
      source: opts.source,
      botEnabled: false,
    }).id;
  }
  const found = findClient(db, visit);
  if (found !== null) {
    summary.clientsMatched += 1;
    return found;
  }
  summary.clientsCreated += 1;
  if (!opts.apply) return -1;
  const phone = visit.clientPhone && visit.clientPhone.length >= 11 ? normalizePhone(visit.clientPhone) : null;
  const usablePhone = phone && isPlausiblePhone(phone) && !findClientByPhone(db, phone) ? phone : null;
  return createClient(db, {
    name: visit.clientName ?? `Клиент ${visit.clientPhone}`,
    phone: usablePhone,
    notes: 'Создан из отчёта по записям YCLIENTS.',
    source: opts.source,
  }).id;
}

/**
 * A visit counts as already imported only on a full match: a cancelled booking and its re-booking in the same
 * slot, or two walk-ins on the placeholder client, are different visits.
 */
function appointmentExists(db: DbOrTx, clientId: number, masterId: number, visit: Visit): boolean {
  if (clientId < 0 || masterId < 0) return false;
  const title = visit.title ?? null;
  const row = db
    .select({ id: appointments.id })
    .from(appointments)
    .where(
      and(
        eq(appointments.clientId, clientId),
        eq(appointments.masterId, masterId),
        eq(appointments.startsAt, visit.startsAt),
        eq(appointments.status, visit.status),
        eq(appointments.price, visit.price),
        title === null ? isNull(appointments.title) : eq(appointments.title, title),
      ),
    )
    .get();
  return row !== undefined;
}

/** Validates and inserts the visits in one transaction; with `apply: false` nothing is written. */
export function importAppointments(db: Db, records: unknown[], opts: ImportOptions, now = Date.now()): AppointmentImportSummary {
  const summary: AppointmentImportSummary = {
    total: records.length,
    created: 0,
    existing: 0,
    invalid: [],
    mastersCreated: [],
    clientsMatched: 0,
    clientsCreated: 0,
    placeholderVisits: 0,
  };
  const visits: Visit[] = [];
  records.forEach((raw, index) => {
    const parsed = visitSchema.safeParse(raw);
    if (parsed.success) visits.push(parsed.data);
    else summary.invalid.push({ index, error: parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ') });
  });

  const lastVisitByMaster = new Map<string, number>();
  for (const v of visits) lastVisitByMaster.set(v.masterName, Math.max(lastVisitByMaster.get(v.masterName) ?? 0, v.startsAt));

  db.transaction((tx) => {
    const masterIds = new Map<string, number>();
    for (const [name, last] of lastVisitByMaster) {
      masterIds.set(name, ensureMaster(tx, name, last >= now - ACTIVE_WINDOW_MS, opts.apply, summary));
    }
    for (const visit of visits) {
      const masterId = masterIds.get(visit.masterName)!;
      const clientId = resolveClient(tx, visit, opts, summary);
      if (appointmentExists(tx, clientId, masterId, visit)) {
        summary.existing += 1;
        continue;
      }
      summary.created += 1;
      if (!opts.apply) continue;
      const endsAt = visit.startsAt + visit.durationMin * 60_000;
      tx.insert(appointments)
        .values({
          clientId,
          masterId,
          serviceId: null,
          title: visit.title ?? null,
          startsAt: visit.startsAt,
          endsAt,
          status: visit.status,
          price: visit.price,
          deposit: 0,
          notes: visit.notes ?? null,
          saleId: null,
          completedAt: visit.status === 'completed' ? endsAt : null,
          createdAt: visit.createdAt ?? now,
          updatedAt: now,
        })
        .run();
    }
  });

  return summary;
}

if (isEntryPoint(import.meta.url)) runImportCli('import-appointments', importAppointments);
