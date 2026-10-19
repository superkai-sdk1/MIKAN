import { and, asc, eq, gt, lt, ne, notInArray } from 'drizzle-orm';
import type { DbOrTx } from '../db/client.js';
import { appointments, employees } from '../db/schema.js';
import type { EmployeeRow } from '../lib/serialize.js';
import { isValidCalendarDate, MINUTE_MS } from '../lib/time.js';
import { studioTimezone } from './settings.js';
import { instantOf, scheduleDaysFor, workingIntervals } from './work-schedule.js';
import { fitsWorkingTime } from './working-time.js';

/**
 * Free appointment starts for the bot: inside the master's working time (their own schedule, else the studio hours
 * `workdayStart`–`workdayEnd`; breaks excluded, studio timezone), every SLOT_STEP_MIN minutes from the start of the
 * working day, not overlapping the master's non-cancelled, non-no-show appointments. A master off that day is not
 * offered. Staff may still book any time from the app; this only limits what the bot offers and accepts.
 */

export const SLOT_STEP_MIN = 30;
/** The earliest start the bot offers: at least this long from now. */
export const SLOT_LEAD_MIN = 60;
/** How far ahead the bot looks for free time. */
export const SLOT_HORIZON_DAYS = 90;

const INACTIVE = ['cancelled', 'no_show'];

export interface MasterSlots {
  master: EmployeeRow;
  /** The master does not work that date (listed only when asked for by `masterId`). */
  off: boolean;
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

/** Whether [startsAt, endsAt) lies inside the master's working time on its studio-local day. */
export function withinWorkingHours(db: DbOrTx, startsAt: number, endsAt: number, masterId: number): boolean {
  const master = db.select().from(employees).where(eq(employees.id, masterId)).get();
  return master !== undefined && fitsWorkingTime(db, master, startsAt, endsAt);
}

/** Masters the bot books with: active employees marked as masters (every active employee when none is). */
export function bookableMasters(db: DbOrTx, masterId?: number): EmployeeRow[] {
  const active = db.select().from(employees).where(eq(employees.active, true)).orderBy(asc(employees.name), asc(employees.id)).all();
  if (masterId !== undefined) return active.filter((e) => e.id === masterId);
  const masters = active.filter((e) => e.isMaster);
  return masters.length ? masters : active;
}

export function freeSlots(db: DbOrTx, q: FreeSlotsQuery): MasterSlots[] {
  if (!isValidCalendarDate(q.date) || q.durationMin <= 0) return [];
  const tz = studioTimezone(db);
  const now = q.now ?? Date.now();
  const earliest = now + SLOT_LEAD_MIN * MINUTE_MS;
  const duration = q.durationMin * MINUTE_MS;
  const masters = bookableMasters(db, q.masterId);
  const days = scheduleDaysFor(db, masters, [q.date]);
  return masters.flatMap((master, index): MasterSlots[] => {
    const day = days[index]!;
    const intervals = workingIntervals(day, tz);
    if (!day.working || !day.start || intervals.length === 0) return q.masterId === undefined ? [] : [{ master, off: true, starts: [] }];
    const open = instantOf(day.date, day.start, tz);
    const close = intervals.at(-1)!.end;
    const conditions = [
      eq(appointments.masterId, master.id),
      lt(appointments.startsAt, close),
      gt(appointments.endsAt, open),
      notInArray(appointments.status, INACTIVE),
    ];
    if (q.excludeAppointmentId !== undefined) conditions.push(ne(appointments.id, q.excludeAppointmentId));
    const busy = db.select({ startsAt: appointments.startsAt, endsAt: appointments.endsAt }).from(appointments).where(and(...conditions)).all();
    const starts: number[] = [];
    for (let start = open; start + duration <= close; start += SLOT_STEP_MIN * MINUTE_MS) {
      const end = start + duration;
      if (start < earliest || !intervals.some((i) => start >= i.start && end <= i.end)) continue;
      if (busy.some((b) => b.startsAt < end && b.endsAt > start)) continue;
      starts.push(start);
    }
    return [{ master, off: false, starts }];
  });
}
