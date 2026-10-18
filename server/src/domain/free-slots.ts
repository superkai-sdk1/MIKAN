import { and, asc, eq, gt, lt, ne, notInArray } from 'drizzle-orm';
import { DateTime } from 'luxon';
import type { DbOrTx } from '../db/client.js';
import { appointments, employees } from '../db/schema.js';
import type { EmployeeRow } from '../lib/serialize.js';
import { MINUTE_MS, parseTimeOfDay } from '../lib/time.js';
import { getStudioSettings } from './settings.js';

/**
 * Free appointment starts for the bot: inside the studio working hours (`workdayStart`–`workdayEnd`, studio
 * timezone), every SLOT_STEP_MIN minutes, not overlapping the master's non-cancelled, non-no-show appointments.
 * Staff may still book any time from the app; this only limits what the bot offers and accepts.
 */

export const SLOT_STEP_MIN = 30;
/** The earliest start the bot offers: at least this long from now. */
export const SLOT_LEAD_MIN = 60;
/** How far ahead the bot looks for free time. */
export const SLOT_HORIZON_DAYS = 90;

const INACTIVE = ['cancelled', 'no_show'];

export interface MasterSlots {
  master: EmployeeRow;
  /** Free starts (ms), ascending. */
  starts: number[];
}

export interface FreeSlotsQuery {
  /** Studio-local calendar date "YYYY-MM-DD". */
  date: string;
  durationMin: number;
  /** A specific master, else every active master. */
  masterId?: number;
  /** The appointment being moved: its own time does not count as busy. */
  excludeAppointmentId?: number;
  now?: number;
}

/** Working hours of a studio-local date as instants; null for an invalid date. */
export function workingWindow(db: DbOrTx, date: string): { open: number; close: number; tz: string } | null {
  const studio = getStudioSettings(db);
  const day = DateTime.fromISO(date, { zone: studio.timezone });
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !day.isValid) return null;
  const at = (minutes: number) =>
    minutes >= 24 * 60
      ? day.startOf('day').plus({ days: 1 }).toMillis()
      : day.startOf('day').set({ hour: Math.floor(minutes / 60), minute: minutes % 60 }).toMillis();
  const open = parseTimeOfDay(studio.workdayStart) ?? 11 * 60;
  const close = parseTimeOfDay(studio.workdayEnd) ?? 21 * 60;
  return { open: at(open), close: at(close), tz: studio.timezone };
}

/** Whether [startsAt, endsAt) lies inside the working hours of its studio-local day. */
export function withinWorkingHours(db: DbOrTx, startsAt: number, endsAt: number): boolean {
  const tz = getStudioSettings(db).timezone;
  const window = workingWindow(db, DateTime.fromMillis(startsAt, { zone: tz }).toISODate() ?? '');
  return window !== null && startsAt >= window.open && endsAt <= window.close;
}

/** Masters the bot books with: active employees marked as masters (every active employee when none is). */
export function bookableMasters(db: DbOrTx, masterId?: number): EmployeeRow[] {
  const active = db.select().from(employees).where(eq(employees.active, true)).orderBy(asc(employees.name), asc(employees.id)).all();
  if (masterId !== undefined) return active.filter((e) => e.id === masterId);
  const masters = active.filter((e) => e.isMaster);
  return masters.length ? masters : active;
}

export function freeSlots(db: DbOrTx, q: FreeSlotsQuery): MasterSlots[] {
  const window = workingWindow(db, q.date);
  if (!window || q.durationMin <= 0) return [];
  const now = q.now ?? Date.now();
  const earliest = now + SLOT_LEAD_MIN * MINUTE_MS;
  const duration = q.durationMin * MINUTE_MS;
  return bookableMasters(db, q.masterId).map((master) => {
    const conditions = [
      eq(appointments.masterId, master.id),
      lt(appointments.startsAt, window.close),
      gt(appointments.endsAt, window.open),
      notInArray(appointments.status, INACTIVE),
    ];
    if (q.excludeAppointmentId !== undefined) conditions.push(ne(appointments.id, q.excludeAppointmentId));
    const busy = db.select({ startsAt: appointments.startsAt, endsAt: appointments.endsAt }).from(appointments).where(and(...conditions)).all();
    const starts: number[] = [];
    for (let start = window.open; start + duration <= window.close; start += SLOT_STEP_MIN * MINUTE_MS) {
      if (start < earliest) continue;
      const end = start + duration;
      if (busy.some((b) => b.startsAt < end && b.endsAt > start)) continue;
      starts.push(start);
    }
    return { master, starts };
  });
}
